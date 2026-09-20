#!/bin/bash
# Rotates, in ONE running environment, the credentials the public repository exposed — and proves
# it — without printing a single value. Run ON THE SERVER, as root, one step at a time, in the order
# of the rotation runbook:
#
#   bash rotate-secrets.sh <namespace> <step> [args]
#
#   check-old [--live]    preflight: is every exposed value the refusal proofs need in $OLD_TAR?
#                         --live (run it BEFORE rotating): and does the environment accept each today?
#   backup                keep a copy of the namespace's Secrets in /root/secret-backup-<ns>-<time>/
#   adopt                 create keycloak-clients from the client secrets Keycloak holds NOW, so the
#                         manifest change that points the services at it changes nothing by itself
#   demo-logins           a new password for each demo login, set in Keycloak, kept in demo-logins
#   webhooks [--restart]  new whatsapp-webhook and sms-dlr values (in force when whatsapp-service and
#                         sms-connector next start; --restart starts them now)
#   ops-auth              a new ops basic-auth password: its hash in ops-auth-users, the password in
#                         /root/ops-auth-password-<env>.txt (mode 600)
#   vault-reseed          restart Vault so its seed stops carrying the two client secrets
#   client <clientId>     regenerate one service account's secret in Keycloak, store it, restart the
#                         service that presents it (onboarding-service | accounting-service |
#                         notifications-manager)
#   drop-stale-keys       remove ONBOARDING_CLIENT_SECRET from platform-secrets once nothing reads it
#   lock-unused-db-roles  NOLOGIN for the database roles no service logs in as
#   test-accounts [--disable]  count (and, with --disable, disable) accounts the repository's test
#                         scripts created with passcodes printed in those scripts
#   user-profile-stamp    declare the admin-only onboardingApplicationId attribute in the live
#                         realm's user profile (the rider sign-up needs it; idempotent)
#   edge-identity         bring a LIVE realm to what the realm file says for PT-3 and PT-7: the
#                         delivery-portal client loses the password grant and offline_access and
#                         gains an 8 h / 24 h client session, its loopback redirect URIs are kept on
#                         dev and dropped on qa, mobile-app keeps the public site's web origin, and
#                         the realm requires TLS from outside. Idempotent; signs nobody out.
#   refresh-rotation      turn ON realm-wide refresh-token rotation (revoke on use, no reuse).
#                         SEPARATE from edge-identity on purpose: it is the one change that can end
#                         a session, so it goes LAST, after the new portal build is served and the
#                         new APK is out. A client that runs two refresh grants at once is signed
#                         out by it. Idempotent.
#   verify                prove all of it: pods Ready, API 401/200, every consumer holds its Secret's
#                         value, current values accepted, the repository's values refused
#
# The "refused" proofs need the values the repository exposed. They come from a tar of the base
# commit's files placed at $OLD_TAR (default /dev/shm/rotation-old.tar: RAM, root-only; the runbook
# streams it in over ssh and deletes it at the end). Without it those proofs are skipped, not faked.
#
# Nothing here prints a value, passes one on a command line (any user on this box can read any
# process's arguments) or writes one outside a private directory in RAM, a Secret, Keycloak, or the
# ops password file. Secrets are written with create/replace, never apply: apply copies every value
# into a last-applied-configuration annotation that `kubectl describe` prints.
set -uo pipefail

NS="${1:?usage: rotate-secrets.sh <namespace> <step> [args]}"
STEP="${2:?usage: rotate-secrets.sh <namespace> <step> [args]}"
shift 2
ENV_NAME="${NS#delivery-}"
REALM=delivery-platform
IAM="${IAM:-https://iam-$ENV_NAME.youdrop.shop}"     # overridable for the offline tests only
API="${API:-https://api-$ENV_NAME.youdrop.shop}"
MON="${MON:-https://monitoring-$ENV_NAME.youdrop.shop}"
TOKEN_URL="$IAM/realms/$REALM/protocol/openid-connect/token"
# The admin REST API's base, set by kc_login once the in-cluster forward is up. NOT derived from
# $IAM any more: the edge refuses /admin on the public iam hostname (PT-7). See kc_admin_up.
ADMIN=""
OLD_TAR="${OLD_TAR:-/dev/shm/rotation-old.tar}"
OPS_PASSWORD_FILE="${OPS_PASSWORD_FILE:-/root/ops-auth-password-$ENV_NAME.txt}"
CLIENTS="onboarding-service accounting-service notifications-manager"
DEMO_USERS="customer rider merchant backoffice carrier"
UNUSED_ROLES="delivery_readonly identity_service file_service corebanking_simulator"

umask 077
WORK=$(mktemp -d "${SHM_DIR:-/dev/shm}/rotate-secrets.XXXXXX") || { echo "no private directory in ${SHM_DIR:-/dev/shm}" >&2; exit 1; }
KC_PF_PORT="$WORK/kc-admin-port"
KC_PF_PID="$WORK/kc-admin-pid"
cleanup() {
  [ -s "$KC_PF_PID" ] && kill "$(cat "$KC_PF_PID")" 2>/dev/null
  rm -rf "$WORK"
}
trap cleanup EXIT INT TERM

FAILS=0
ok()   { echo "  ok    $*"; }
bad()  { echo "  FAIL  $*"; FAILS=$((FAILS + 1)); }
skip() { echo "  --    $*"; }
die()  { echo "STOP: $*" >&2; exit 1; }
# check <label> <expected> <actual> — actual is always a code, a count or same/different, never a value
check() { if [ "$2" = "$3" ]; then ok "$1 ($3)"; else bad "$1: expected $2, got ${3:-nothing}"; fi; }
same() { [ -n "$1" ] && [ "$1" = "$2" ] && echo same || echo different; }

k() { kubectl -n "$NS" "$@"; }
sha() { sha256sum | cut -c1-64; }
file_sha() { sha < "$1"; }
rand() { head -c 48 /dev/urandom | base64 | tr -d '/+=\n' | head -c 32; }
# Six uniform random digits: the app's sign-in accepts a passcode of exactly six digits.
passcode() {
  local n
  while :; do
    n=$(od -An -N4 -tu4 /dev/urandom | tr -d ' \n')
    [ "$n" -lt 4294000000 ] && { printf '%06d' $((n % 1000000)); return 0; }
  done
}

# ---------------------------------------------------------------------------------------- Secrets
secret_exists() { k get secret "$1" -o name >/dev/null 2>&1; }
secret_keys() { k get secret "$1" -o json 2>/dev/null | jq -r '.data // {} | keys | join(",")'; }
secret_has() { secret_keys "$1" | tr ',' '\n' | grep -qx "$2"; }
secret_key_to() { k get secret "$1" -o "jsonpath={.data.$2}" | base64 -d > "$3"; }   # value -> private file
secret_sha() { k get secret "$1" -o "jsonpath={.data.$2}" 2>/dev/null | base64 -d | sha; }
# secret_set_key <secret> <key> <file>: one key, other keys untouched; creates the Secret if absent.
secret_set_key() {
  if secret_exists "$1"; then
    k get secret "$1" -o json \
      | KEY="$2" VALFILE="$3" python3 -c '
import base64, json, os, sys
s = json.load(sys.stdin)
s.setdefault("data", {})[os.environ["KEY"]] = base64.b64encode(open(os.environ["VALFILE"], "rb").read()).decode()
s["metadata"].pop("managedFields", None)
json.dump(s, sys.stdout)' \
      | k replace -f - >/dev/null || die "could not update $1/$2"
  else
    mkdir -p "$WORK/new-$1" && cp "$3" "$WORK/new-$1/$2"
    k create secret generic "$1" --from-file="$WORK/new-$1" >/dev/null || die "could not create $1"
  fi
}
# secret_replace_from_dir <secret> <dir>: the whole Secret becomes the files in <dir> (key = file name).
secret_replace_from_dir() {
  if secret_exists "$1"; then
    k create secret generic "$1" --from-file="$2" --dry-run=client -o json | k replace -f - >/dev/null || die "could not replace $1"
  else
    k create secret generic "$1" --from-file="$2" >/dev/null || die "could not create $1"
  fi
}

# ------------------------------------------------------------------------- the running workloads
# The sha256 of the value a running pod holds in its environment (the value itself stays in the pod).
env_sha() { k exec "deploy/$1" -- sh -c "printf %s \"\$$2\"" 2>/dev/null | sha; }
restart() {
  k rollout restart "deploy/$1" >/dev/null || die "could not restart deploy/$1"
  k rollout status "deploy/$1" --timeout=300s >/dev/null || die "deploy/$1 did not become ready"
}
client_key() {
  case "$1" in
    onboarding-service) echo ONBOARDING_CLIENT_SECRET ;;
    accounting-service) echo ACCOUNTING_CLIENT_SECRET ;;
    notifications-manager) echo NOTIFICATIONS_CLIENT_SECRET ;;
    *) return 1 ;;
  esac
}
# Every demo login signs in on mobile-app now, backoffice included. delivery-portal's password
# grant is off (PT-3): a public client with direct access grants turns a phished back-office
# password straight into a session. The user's realm roles are the same either way — a token's
# roles come from the account, not from the client it was minted for.
demo_client() { echo mobile-app; }
# Key NAMES of a Vault path, read through the reseed sidecar (which holds the token); never values.
vault_keys() { k exec deploy/vault -c vault-reseed -- vault kv get -format=json "secret/$1" 2>/dev/null | jq -r '.data.data | keys | join(",")'; }
psqlq() { k exec postgres-0 -- psql -U delivery -d delivery -At -c "$1"; }
# db_login <role> <password-file>: psql as <role> over TCP to the pod's own address, where pg_hba
# demands the password (the socket and 127.0.0.1 are trust, and would prove nothing). The password
# goes in on stdin. Prints psql's answer: "1", or its error.
db_login() {
  k exec -i postgres-0 -- sh -c 'IFS= read -r PGPASSWORD; export PGPASSWORD; psql -h "$(hostname -i | cut -d" " -f1)" -U "$1" -d delivery -At -c "select 1" 2>&1' sh "$1" < "$2"
}
# config_sources <app>: config-server's HTTP code and the NAMES of its property sources for <app>,
# e.g. "200 application-default,vault:accounting-service,vault:application". The body holds values
# and stays in the private directory.
config_sources() {
  local ip code
  ip=$(k get svc config-server -o jsonpath='{.spec.clusterIP}')
  if [ ! -s "$WORK/cfg-curl" ]; then
    secret_key_to platform-secrets CONFIG_SERVER_USER "$WORK/cfg-u"
    secret_key_to platform-secrets CONFIG_SERVER_PASSWORD "$WORK/cfg-p"
    { printf 'user = "'; cat "$WORK/cfg-u"; printf ':'; cat "$WORK/cfg-p"; printf '"\n'; } > "$WORK/cfg-curl"
    rm -f "$WORK/cfg-u" "$WORK/cfg-p"
  fi
  code=$(curl -s -o "$WORK/cfg-body" -w '%{http_code}' -K "$WORK/cfg-curl" "http://$ip:8888/$1/default")
  printf '%s %s' "$code" "$(jq -r '[.propertySources[]?.name] | join(",")' "$WORK/cfg-body" 2>/dev/null)"
  rm -f "$WORK/cfg-body"
}

# -------------------------------------------------------------------------------------- Keycloak
# The admin API is reached INSIDE the cluster, never over the public iam hostname.
#
# PT-7 closed /admin at the edge: the admin console was a login form open to the internet, and the
# admin REST API sat on the same prefix. This script was the only caller that used that hostname
# for it — every other script in the repository already spoke to keycloak:8080 — so it forwards a
# loopback port onto the keycloak Service instead. Nothing leaves the box, and the token's issuer
# is unchanged (KC_HOSTNAME pins it to the public URL whichever address the request arrives on).
#
# The port and the pid live in FILES rather than variables. kc() is called inside $(...) all
# through this script, and a variable assigned in a subshell is gone the moment it returns — so a
# forward started lazily would be started again, and leaked, on every single call.
kc_admin_up() {
  if [ -s "$KC_PF_PORT" ] && kill -0 "$(cat "$KC_PF_PID" 2>/dev/null)" 2>/dev/null; then
    return 0
  fi
  : > "$WORK/kc-pf.log"
  # `:8080` asks kubectl to pick a free local port and print it, which is race-free where choosing
  # a number here would not be.
  kubectl -n "$NS" port-forward svc/keycloak :8080 --address 127.0.0.1 >"$WORK/kc-pf.log" 2>&1 &
  echo $! > "$KC_PF_PID"
  local i=0 port=""
  while [ "$i" -lt 150 ]; do
    port=$(sed -n 's/^Forwarding from 127\.0\.0\.1:\([0-9][0-9]*\).*/\1/p' "$WORK/kc-pf.log" | head -n1)
    [ -n "$port" ] && break
    kill -0 "$(cat "$KC_PF_PID")" 2>/dev/null || die "kubectl port-forward to svc/keycloak in $NS exited: $(cat "$WORK/kc-pf.log")"
    sleep 0.1
    i=$((i + 1))
  done
  [ -n "$port" ] || die "kubectl port-forward to svc/keycloak in $NS never reported a local port"
  echo "$port" > "$KC_PF_PORT"
}
kc_url() { kc_admin_up; printf 'http://127.0.0.1:%s' "$(cat "$KC_PF_PORT")"; }

KC_AT=0
kc_login() {   # a fresh admin token, into a header file; the admin password goes by file, never argv
  local base; base=$(kc_url)
  ADMIN="$base/admin/realms/$REALM"
  secret_key_to platform-secrets KEYCLOAK_ADMIN "$WORK/kc-user"
  secret_key_to platform-secrets KEYCLOAK_ADMIN_PASSWORD "$WORK/kc-pass"
  curl -s -X POST "$base/realms/master/protocol/openid-connect/token" -d client_id=admin-cli \
    -d grant_type=password --data-urlencode "username@$WORK/kc-user" --data-urlencode "password@$WORK/kc-pass" \
    | jq -j '.access_token // empty' > "$WORK/kc-token"
  rm -f "$WORK/kc-pass"
  [ -s "$WORK/kc-token" ] || die "no Keycloak admin token from svc/keycloak in $NS"
  { printf 'Authorization: Bearer '; cat "$WORK/kc-token"; echo; } > "$WORK/auth"
  rm -f "$WORK/kc-token"
  KC_AT=$(date +%s)
}
# Master-realm admin tokens live 60 s. kc_fresh renews one older than 40 s; call it in the step
# itself (a renewal inside a $(...) subshell cannot update KC_AT for the calls after it).
kc_fresh() { [ $(( $(date +%s) - KC_AT )) -lt 40 ] || kc_login; }
kc() {   # kc <curl args...>: the admin API
  kc_fresh
  curl -s -H @"$WORK/auth" "$@"
}
client_uuid() { kc "$ADMIN/clients?clientId=$1" | jq -r '.[0].id // empty'; }
client_secret_to() {   # Keycloak's current secret of <clientId> -> <file>
  local id; id=$(client_uuid "$1"); [ -n "$id" ] || die "client $1 not found in $IAM"
  kc "$ADMIN/clients/$id/client-secret" | jq -j '.value // empty' > "$2"
  [ -s "$2" ] || die "Keycloak returned no secret for $1"
}
client_secret_regenerate_to() {
  local id; id=$(client_uuid "$1"); [ -n "$id" ] || die "client $1 not found in $IAM"
  kc -X POST "$ADMIN/clients/$id/client-secret" | jq -j '.value // empty' > "$2"
  [ -s "$2" ] || die "Keycloak did not regenerate the secret of $1 (nothing changed)"
}
user_id() { kc "$ADMIN/users?username=$1&exact=true" | jq -r '.[0].id // empty'; }
# HTTP codes of the two grants, the secret or password read from a file.
cc_code() { curl -s -o /dev/null -w '%{http_code}' -X POST "$TOKEN_URL" -d grant_type=client_credentials --data-urlencode "client_id=$1" --data-urlencode "client_secret@$2"; }
pw_code() { curl -s -o /dev/null -w '%{http_code}' -X POST "$TOKEN_URL" -d grant_type=password --data-urlencode "client_id=$1" --data-urlencode "username=$2" --data-urlencode "password@$3"; }

# ------------------------------------------------------------------------------------- webhooks
hmac_hex() { KEYFILE="$1" BODY="$2" python3 -c 'import hashlib, hmac, os; print(hmac.new(open(os.environ["KEYFILE"], "rb").read(), os.environ["BODY"].encode(), hashlib.sha256).hexdigest())'; }
# An empty envelope, signed with <key-file>: a verified one is answered 2xx and records nothing.
wa_code()  { curl -s -o /dev/null -w '%{http_code}' -X POST "$API/webhooks/whatsapp" -H 'Content-Type: application/json' -H "X-Hub-Signature-256: sha256=$(hmac_hex "$1" '{}')" --data-binary '{}'; }
dlr_code() { curl -s -o /dev/null -w '%{http_code}' -X POST "$API/webhooks/dlr/dev_passthrough" -H 'Content-Type: application/json' -H "x-delivery-signature: $(hmac_hex "$1" '{}')" --data-binary '{}'; }
verify_token_code() { curl -s -o /dev/null -w '%{http_code}' -G "$API/webhooks/whatsapp" --data-urlencode 'hub.mode=subscribe' --data-urlencode "hub.verify_token@$1" --data-urlencode 'hub.challenge=1'; }
ops_code() {   # ops_code [<password-file>]: the monitoring route, with that ops password or none
  if [ -n "${1:-}" ]; then printf 'user = "ops:%s"\n' "$(head -n1 "$1")" > "$WORK/ops-curl"; curl -s -o /dev/null -w '%{http_code}' -K "$WORK/ops-curl" "$MON/mailpit/"
  else curl -s -o /dev/null -w '%{http_code}' "$MON/mailpit/"; fi
}

# -------------------------------------------------------------- the values the repository exposed
# old_value <kind> <name> <file>: one exposed value, read from $OLD_TAR into a private file.
old_value() {
  [ -s "$OLD_TAR" ] || return 1
  OLD_TAR="$OLD_TAR" python3 - "$1" "$2" "$3" <<'PY'
import json, os, re, sys, tarfile
kind, name, out = sys.argv[1:4]
tar = tarfile.open(os.environ["OLD_TAR"])
def text(p):
    try:
        return tar.extractfile(p).read().decode()
    except KeyError:
        sys.exit(1)
REALM = "deploy/k3s/base/assets/keycloak/realm-delivery-platform.json"
v = None
if kind == "client":
    v = next((c.get("secret") for c in json.loads(text(REALM))["clients"] if c.get("clientId") == name), None)
elif kind == "user":
    for u in json.loads(text(REALM))["users"]:
        if u.get("username") == name:
            v = next((c.get("value") for c in u.get("credentials", []) if c.get("type") == "password"), None)
elif kind == "whatsapp":
    m = re.search(r"^\s*" + re.escape(name) + r":\s*\"?([^\"\n]*?)\"?\s*$", text("deploy/k3s/base/configmap-common.yaml"), re.M)
    v = m and m.group(1)
elif kind == "dlr":
    m = re.search(r"dlr-secret:\s*\$\{SMS_DEV_DLR_SECRET:([^}]*)\}", text("services/sms-connector/src/main/resources/application.yml"))
    v = m and m.group(1)
elif kind == "opsline":
    m = re.search(r"--from-literal=users='([^']*)'", text("deploy/k3s/scripts/gen-secrets.sh"))
    v = m and m.group(1)
elif kind == "dbrole":
    sql = text("deploy/k3s/base/assets/postgres-init/02-service-roles.sql")
    if name == "delivery_readonly":
        m = re.search(r"CREATE ROLE delivery_readonly LOGIN PASSWORD '([^']*)'", sql)
        v = m and m.group(1)
    else:
        m = re.search(r"svc \|\| '([^']*)'", sql)
        v = m and name + m.group(1)
if not v:
    sys.exit(1)
with open(out, "w") as f:
    f.write(v)
PY
}

# ========================================================================================= steps
step_backup() {
  local d; d="/root/secret-backup-$NS-$(date +%Y%m%d-%H%M%S)"
  mkdir -m 700 "$d" || die "cannot create $d"
  for s in platform-secrets ops-auth-users keycloak-clients demo-logins whatsapp-webhook sms-dlr; do
    secret_exists "$s" && k get secret "$s" -o json > "$d/$s.json"
  done
  echo "backup of $NS's Secrets (root-only): $d — $(ls "$d" | tr '\n' ' ')"
}

step_check_old() {   # a preflight: is every exposed value the refusal proofs need in $OLD_TAR?
  local c u p r
  [ -s "$OLD_TAR" ] || die "no $OLD_TAR — stream the base commit's files in first (see the runbook)"
  for c in $CLIENTS; do check "old secret of $c" found "$(old_value client "$c" "$WORK/x" && echo found || echo missing)"; done
  for u in $DEMO_USERS; do check "old password of $u" found "$(old_value user "$u" "$WORK/x" && echo found || echo missing)"; done
  for p in WHATSAPP_APP_SECRET WHATSAPP_VERIFY_TOKEN; do check "old $p" found "$(old_value whatsapp "$p" "$WORK/x" && echo found || echo missing)"; done
  check "old DLR secret" found "$(old_value dlr - "$WORK/x" && echo found || echo missing)"
  check "old ops-auth line" found "$(old_value opsline - "$WORK/x" && echo found || echo missing)"
  for r in $UNUSED_ROLES; do check "old password of $r" found "$(old_value dbrole "$r" "$WORK/x" && echo found || echo missing)"; done
  rm -f "$WORK/x"
  [ "${1:-}" = --live ] || return 0
  # BEFORE rotating: each exposed value must be what the environment accepts today. Otherwise a
  # value extracted wrongly would be "refused" afterwards too, and every refusal proof would be
  # vacuous. This authenticates with the exposed values once each; it changes nothing.
  echo "== each exposed value is live in $NS today"
  local code
  kc_login
  for c in $CLIENTS; do old_value client "$c" "$WORK/x"; check "$c gets a token with the repository's secret" 200 "$(cc_code "$c" "$WORK/x")"; done
  for u in $DEMO_USERS; do old_value user "$u" "$WORK/x"; check "$u signs in with the repository's password" 200 "$(pw_code "$(demo_client "$u")" "$u" "$WORK/x")"; done
  old_value whatsapp WHATSAPP_APP_SECRET "$WORK/x"; check "the WhatsApp webhook accepts the repository's signature" 200 "$(wa_code "$WORK/x")"
  old_value whatsapp WHATSAPP_VERIFY_TOKEN "$WORK/x"; check "the WhatsApp handshake accepts the repository's token" 200 "$(verify_token_code "$WORK/x")"
  old_value dlr - "$WORK/x"; check "the DLR webhook accepts the repository's signature" 204 "$(dlr_code "$WORK/x")"
  old_value opsline - "$WORK/x"; check "ops-auth-users holds the repository's hash" 1 "$(k get secret ops-auth-users -o jsonpath='{.data.users}' | base64 -d | grep -c -F -f "$WORK/x")"
  for r in $UNUSED_ROLES; do
    old_value dbrole "$r" "$WORK/x"
    check "$r logs in with the repository's password" 1 "$(db_login "$r" "$WORK/x")"
  done
  rm -f "$WORK/x"
}

step_adopt() {
  local c key
  kc_login
  mkdir "$WORK/adopt"
  for c in $CLIENTS; do key=$(client_key "$c"); client_secret_to "$c" "$WORK/adopt/$key"; done
  if secret_exists keycloak-clients; then
    echo "keycloak-clients already exists in $NS; comparing it with Keycloak:"
  else
    k create secret generic keycloak-clients --from-file="$WORK/adopt" >/dev/null || die "could not create keycloak-clients"
    echo "keycloak-clients created in $NS from the secrets Keycloak holds now (nothing rotated yet)."
  fi
  for c in $CLIENTS; do
    key=$(client_key "$c")
    check "keycloak-clients/$key == Keycloak's $c" same "$(same "$(secret_sha keycloak-clients "$key")" "$(file_sha "$WORK/adopt/$key")")"
  done
  if secret_has platform-secrets ONBOARDING_CLIENT_SECRET; then
    check "...and == platform-secrets/ONBOARDING_CLIENT_SECRET, which onboarding-service reads today" same \
      "$(same "$(secret_sha keycloak-clients ONBOARDING_CLIENT_SECRET)" "$(secret_sha platform-secrets ONBOARDING_CLIENT_SECRET)")"
  fi
}

step_demo_logins() {
  local u uid client code
  kc_login
  mkdir "$WORK/demo"
  for u in $DEMO_USERS; do
    kc_fresh
    client=$(demo_client "$u")
    uid=$(user_id "$u"); [ -n "$uid" ] || die "demo login $u not found in $IAM"
    rm -f "$WORK/demo/old"
    if secret_has demo-logins "$u"; then secret_key_to demo-logins "$u" "$WORK/demo/old"; else old_value user "$u" "$WORK/demo/old"; fi
    if [ "$u" = backoffice ]; then rand > "$WORK/demo/new"; else passcode > "$WORK/demo/new"; fi
    NEWFILE="$WORK/demo/new" python3 -c 'import json, os; print(json.dumps({"type": "password", "temporary": False, "value": open(os.environ["NEWFILE"]).read()}))' > "$WORK/demo/body"
    code=$(kc -o /dev/null -w '%{http_code}' -X PUT -H 'Content-Type: application/json' --data-binary @"$WORK/demo/body" "$ADMIN/users/$uid/reset-password")
    rm -f "$WORK/demo/body"
    [ "$code" = 204 ] || die "Keycloak answered $code to the new password for $u (its password is unchanged)"
    secret_set_key demo-logins "$u" "$WORK/demo/new"
    # A new password does not end a session: whoever signed in with the published one would keep
    # refreshing their tokens. End them all.
    check "$u: every session signed out" 204 "$(kc -o /dev/null -w '%{http_code}' -X POST "$ADMIN/users/$uid/logout")"
    # A login locked by past failures would make the proof below lie.
    kc -o /dev/null -X DELETE "$ADMIN/attack-detection/brute-force/users/$uid"
    if [ -s "$WORK/demo/old" ]; then check "$u: the old password is refused" 401 "$(pw_code "$client" "$u" "$WORK/demo/old")"
    else skip "$u: no old password to test (no demo-logins yet and no $OLD_TAR)"; fi
    check "$u: the new password signs in" 200 "$(pw_code "$client" "$u" "$WORK/demo/new")"
  done
  echo "demo-logins holds the new passwords; read one on this box with:"
  echo "  kubectl -n $NS get secret demo-logins -o jsonpath='{.data.<user>}' | base64 -d; echo"
}

step_webhooks() {
  mkdir "$WORK/wa" "$WORK/dlr"
  rand > "$WORK/wa/WHATSAPP_APP_SECRET"
  rand > "$WORK/wa/WHATSAPP_VERIFY_TOKEN"
  rand > "$WORK/dlr/SMS_DEV_DLR_SECRET"
  secret_replace_from_dir whatsapp-webhook "$WORK/wa"
  secret_replace_from_dir sms-dlr "$WORK/dlr"
  echo "whatsapp-webhook and sms-dlr hold new values."
  if [ "${1:-}" = --restart ]; then
    restart whatsapp-service
    restart sms-connector
    check "whatsapp-service holds the new app secret" same "$(same "$(env_sha whatsapp-service WHATSAPP_APP_SECRET)" "$(secret_sha whatsapp-webhook WHATSAPP_APP_SECRET)")"
    check "sms-connector holds the new DLR secret" same "$(same "$(env_sha sms-connector SMS_DEV_DLR_SECRET)" "$(secret_sha sms-dlr SMS_DEV_DLR_SECRET)")"
  else
    echo "They take effect when whatsapp-service and sms-connector next start (the manifest change starts them)."
  fi
}

step_ops_auth() {
  local before after code i
  before=$(k get secret ops-auth-users -o jsonpath='{.data.users}' 2>/dev/null | base64 -d | sha)
  rand > "$WORK/ops-pw"
  { cat "$WORK/ops-pw"; echo; } > "$OPS_PASSWORD_FILE" && chmod 600 "$OPS_PASSWORD_FILE" || die "cannot write $OPS_PASSWORD_FILE"
  mkdir "$WORK/ops"
  printf 'ops:%s\n' "$(openssl passwd -apr1 -stdin < "$WORK/ops-pw" | tr -d '\r')" > "$WORK/ops/users"
  secret_replace_from_dir ops-auth-users "$WORK/ops"
  after=$(k get secret ops-auth-users -o jsonpath='{.data.users}' | base64 -d | sha)
  check "ops-auth-users changed" changed "$([ "$before" != "$after" ] && echo changed || echo unchanged)"
  for i in $(seq 1 30); do   # Traefik reloads a middleware's Secret on its own; give it a minute
    code=$(ops_code "$OPS_PASSWORD_FILE"); [ "$code" != 401 ] && [ "$code" != 000 ] && break; sleep 3
  done
  check "the new password opens $MON/mailpit/" accepted "$([ "$code" != 401 ] && [ "$code" != 000 ] && echo accepted || echo "$code")"
  check "no password is refused" 401 "$(ops_code)"
  rand > "$WORK/ops-wrong"
  check "a wrong password is refused" 401 "$(ops_code "$WORK/ops-wrong")"
  if old_value opsline - "$WORK/ops-old"; then
    check "the repository's hash is gone from ops-auth-users" 0 "$(k get secret ops-auth-users -o jsonpath='{.data.users}' | base64 -d | grep -c -F -f "$WORK/ops-old")"
  fi
  echo "The new password is in $OPS_PASSWORD_FILE (user ops, mode 600). It is not printed."
}

step_vault_reseed() {
  local p
  k get cm vault-bootstrap -o jsonpath='{.data.bootstrap\.sh}' | grep -q 'keycloak\.client-secret' \
    && die "vault-bootstrap still seeds the client secrets: the manifest change has not reached $NS"
  k rollout restart deploy/vault >/dev/null || die "could not restart vault"
  # Ready means seeded: the sidecar's readiness gates on the seed's completion marker.
  k rollout status deploy/vault --timeout=300s >/dev/null || die "vault did not come back"
  # The Config Server logged in to the Vault that just went away. It renews or logs in again only on
  # its token's schedule (up to an hour), and until then a service that starts could not fetch its
  # configuration. A restart logs it in to this Vault now.
  restart config-server
  for p in accounting-service notifications-manager; do
    check "Vault's secret/$p no longer carries a client secret" absent "$(vault_keys "$p" | grep -q client-secret && echo present || echo absent)"
    r=$(config_sources "$p")
    check "config-server serves $p its Vault source again" yes "$(case "$r" in "200 "*"vault:$p"*) echo yes ;; *) echo "no: $r" ;; esac)"
  done
}

step_client() {
  local c="${1:?usage: client <onboarding-service|accounting-service|notifications-manager>}" key ref
  key=$(client_key "$c") || die "unknown client $c"
  secret_exists keycloak-clients || die "keycloak-clients does not exist in $NS: run 'adopt' first"
  ref=$(k get deploy "$c" -o json | jq -r '.spec.template.spec.containers[0].env[]? | select(.name == "KEYCLOAK_CLIENT_SECRET") | .valueFrom.secretKeyRef | "\(.name)/\(.key)"')
  [ "$ref" = "keycloak-clients/$key" ] || die "deploy/$c reads its client secret from '${ref:-nowhere}', not keycloak-clients/$key: the manifest change has not reached $NS"
  if [ "$c" != onboarding-service ] && vault_keys "$c" | grep -q client-secret; then
    die "Vault still hands $c the old client secret, and the Config Server's value would win: run 'vault-reseed' first"
  fi
  kc_login
  client_secret_to "$c" "$WORK/old"
  client_secret_regenerate_to "$c" "$WORK/new"
  secret_set_key keycloak-clients "$key" "$WORK/new"
  echo "$c: Keycloak regenerated its secret and keycloak-clients/$key holds it; restarting deploy/$c ..."
  restart "$c"
  check "$c: the new secret gets a token" 200 "$(cc_code "$c" "$WORK/new")"
  check "$c: the old secret is refused" 401 "$(cc_code "$c" "$WORK/old")"
  check "$c: the running pod holds the Secret's value" same "$(same "$(env_sha "$c" KEYCLOAK_CLIENT_SECRET)" "$(secret_sha keycloak-clients "$key")")"
  check "$c: the Secret holds Keycloak's value" same "$(same "$(secret_sha keycloak-clients "$key")" "$(file_sha "$WORK/new")")"
}

step_drop_stale_keys() {
  local readers
  readers=$(k get deploy,sts -o json | jq -r '.items[] | .metadata.name as $n | .spec.template.spec.containers[].env[]? | select(.valueFrom.secretKeyRef.name == "platform-secrets" and .valueFrom.secretKeyRef.key == "ONBOARDING_CLIENT_SECRET") | $n')
  [ -z "$readers" ] || die "platform-secrets/ONBOARDING_CLIENT_SECRET is still read by: $readers"
  if secret_has platform-secrets ONBOARDING_CLIENT_SECRET; then
    k patch secret platform-secrets --type=json -p '[{"op":"remove","path":"/data/ONBOARDING_CLIENT_SECRET"}]' >/dev/null || die "patch failed"
  fi
  check "platform-secrets no longer holds ONBOARDING_CLIENT_SECRET" absent "$(secret_has platform-secrets ONBOARDING_CLIENT_SECRET && echo present || echo absent)"
  echo "Pods started before this keep the stale variable until their next restart; nothing reads it."
}

step_lock_unused_db_roles() {
  local r n out
  for r in $UNUSED_ROLES; do
    n=$(psqlq "select count(*) from pg_stat_activity where usename = '$r'")
    [ "$n" = 0 ] || die "$r has $n open connection(s), so something does use it"
  done
  for r in $UNUSED_ROLES; do psqlq "ALTER ROLE $r NOLOGIN" >/dev/null || die "ALTER ROLE $r failed"; done
  for r in $UNUSED_ROLES; do
    check "$r cannot log in" f "$(psqlq "select rolcanlogin from pg_roles where rolname = '$r'")"
    if old_value dbrole "$r" "$WORK/db-old"; then
      out=$(db_login "$r" "$WORK/db-old")
      check "$r with the repository's password" refused "$(printf '%s' "$out" | grep -q 'not permitted to log in' && echo refused || echo not-refused)"
    fi
  done
}

step_user_profile_stamp() {
  # The rider sign-up stamps the account it creates with its application's id, in an attribute only
  # an administrator (the onboarding service account) may see or write. Keycloak's declarative user
  # profile DISCARDS any attribute it does not declare, silently, and a realm-file change never
  # reaches an existing realm, so the declaration goes in here, through the admin API, exactly as the
  # realm file has it: view and edit admin only, no user permission, not required, single-valued.
  # Idempotent: present and right is left alone; present and wrong is corrected.
  local state before after code
  kc_login
  kc "$ADMIN/users/profile" > "$WORK/up.json"
  jq -e '.attributes | type == "array"' "$WORK/up.json" >/dev/null 2>&1 || die "could not read the realm's user profile"
  before=$(jq -r '[.attributes[].name] | sort | join(",")' "$WORK/up.json")
  state=$(python3 - "$WORK/up.json" "$WORK/up-new.json" <<'PY'
import json, sys
cfg = json.load(open(sys.argv[1]))
want = {"name": "onboardingApplicationId", "displayName": "Onboarding application",
        "permissions": {"view": ["admin"], "edit": ["admin"]}, "multivalued": False}
attrs = cfg["attributes"]
cur = next((a for a in attrs if a.get("name") == want["name"]), None)
def right(a):
    p = a.get("permissions") or {}
    return p.get("view") == ["admin"] and p.get("edit") == ["admin"] and not a.get("required") and not a.get("multivalued")
if cur is None:
    attrs.append(want); state = "added"
elif right(cur):
    state = "present"
else:
    attrs[attrs.index(cur)] = want; state = "corrected"
json.dump(cfg, open(sys.argv[2], "w"))
print(state)
PY
)
  if [ "$state" != present ]; then
    code=$(kc -o /dev/null -w '%{http_code}' -X PUT -H 'Content-Type: application/json' --data-binary @"$WORK/up-new.json" "$ADMIN/users/profile")
    check "the user profile accepted onboardingApplicationId ($state)" 200 "$code"
  else
    ok "onboardingApplicationId was already declared this way; nothing written"
  fi
  kc "$ADMIN/users/profile" > "$WORK/up.json"
  check "onboardingApplicationId: view admin only" '["admin"]' "$(jq -c '.attributes[] | select(.name == "onboardingApplicationId") | .permissions.view' "$WORK/up.json")"
  check "onboardingApplicationId: edit admin only" '["admin"]' "$(jq -c '.attributes[] | select(.name == "onboardingApplicationId") | .permissions.edit' "$WORK/up.json")"
  check "onboardingApplicationId: not required, single-valued" 'null false' "$(jq -r '.attributes[] | select(.name == "onboardingApplicationId") | "\(.required) \(.multivalued // false)"' "$WORK/up.json")"
  after=$(jq -r '[.attributes[].name] | sort | join(",")' "$WORK/up.json")
  check "every attribute declared before is still declared" yes "$(python3 -c 'import sys; b=set(sys.argv[1].split(",")); a=set(sys.argv[2].split(",")); print("yes" if b <= a else "no: lost " + ",".join(sorted(b - a)))' "$before" "$after")"
}

# Drops one client scope from a client's default AND optional lists, if it is on either.
client_scope_drop() {   # client_scope_drop <client-uuid> <clientId, for the message> <scope>
  local kind sid
  for kind in default optional; do
    kc_fresh
    sid=$(kc "$ADMIN/clients/$1/$kind-client-scopes" | jq -r --arg n "$3" '.[] | select(.name == $n) | .id // empty')
    if [ -n "$sid" ]; then
      check "$2: $3 removed from the $kind client scopes" 204 \
        "$(kc -o /dev/null -w '%{http_code}' -X DELETE "$ADMIN/clients/$1/$kind-client-scopes/$sid")"
    else
      ok "$2: $3 is not among the $kind client scopes"
    fi
  done
}

step_edge_identity() {
  # PT-3 and PT-7 in a LIVE realm. The realm file only ever imports into an empty database, so
  # everything it now says about delivery-portal has to be asserted here as well — and the two
  # must not drift: scripts/verify.sh checks the file, and the proofs at the end of this step
  # check the realm.
  #
  # Nothing here ends a session. Turning the password grant off stops NEW direct grants; sessions
  # that already exist keep refreshing. Rotation, which can end one, is its own step.
  local id code loopback
  kc_login

  # dev keeps its loopback redirect URIs: `flutter run -d chrome --web-port=5010` lands there and
  # signing in locally is what they are for. qa is reached over the internet, where a redirect URI
  # pointing at somebody's own machine is only a way to hand an authorization code to whatever is
  # listening on their port 5010.
  if [ "$ENV_NAME" = dev ]; then loopback=keep; else loopback=drop; fi

  echo "== the realm"
  kc "$ADMIN" > "$WORK/realm.json"
  jq -e '.realm' "$WORK/realm.json" >/dev/null 2>&1 || die "could not read realm $REALM from the admin API"
  if [ "$(jq -r '.sslRequired' "$WORK/realm.json")" = external ]; then
    ok "sslRequired was already external; nothing written"
  else
    jq '.sslRequired = "external"' "$WORK/realm.json" > "$WORK/realm-new.json"
    code=$(kc -o /dev/null -w '%{http_code}' -X PUT -H 'Content-Type: application/json' --data-binary @"$WORK/realm-new.json" "$ADMIN")
    check "the realm accepted sslRequired external" 204 "$code"
  fi

  echo "== the delivery-portal client"
  id=$(client_uuid delivery-portal); [ -n "$id" ] || die "client delivery-portal not found in $REALM"
  kc "$ADMIN/clients/$id" > "$WORK/portal.json"
  LOOPBACK="$loopback" python3 - "$WORK/portal.json" "$WORK/portal-new.json" <<'PY'
import json, os, re, sys

c = json.load(open(sys.argv[1]))
loopback = os.environ["LOOPBACK"]

# A public client with direct access grants turns a phished password into a session, with no
# browser, no SSO and nowhere to put a second factor. The portal signs in with Authorization Code
# + PKCE and never used this.
c["directAccessGrantsEnabled"] = False

attrs = c.setdefault("attributes", {})
# 8 hours idle and 24 hours absolute, per client. This is also the ceiling on the refresh token
# this client is given, which used to be the realm's 30 days. The realm's SSO session is left
# alone deliberately: it is the phones' session too, and shortening it here would sign riders and
# customers out to tighten the back office.
attrs["client.session.idle.timeout"] = "28800"
attrs["client.session.max.lifespan"] = "86400"
attrs.setdefault("pkce.code.challenge.method", "S256")

loop = re.compile(r"^http://(localhost|127\.0\.0\.1)(:\d+)?(/|$)")
if loopback == "drop":
    c["redirectUris"] = [u for u in c.get("redirectUris", []) if not loop.match(u)]
    logout = [u for u in (attrs.get("post.logout.redirect.uris") or "").split("##") if u and not loop.match(u)]
else:
    logout = [u for u in (attrs.get("post.logout.redirect.uris") or "").split("##") if u]

# Every registered redirect URI is a place this client may be sent back to after a logout; the
# qa host was missing, so a logout there was refused by Keycloak with nowhere to return to.
for uri in c.get("redirectUris", []):
    if uri not in logout:
        logout.append(uri)
attrs["post.logout.redirect.uris"] = "##".join(logout)

json.dump(c, open(sys.argv[2], "w"))
PY
  code=$(kc -o /dev/null -w '%{http_code}' -X PUT -H 'Content-Type: application/json' --data-binary @"$WORK/portal-new.json" "$ADMIN/clients/$id")
  check "delivery-portal accepted the update" 204 "$code"
  # offline_access is a scope Keycloak hands out by default. It is why the back office could ask
  # for a token that never expires, and it was never something the app requested.
  client_scope_drop "$id" delivery-portal offline_access

  echo "== the mobile-app client"
  # The public site's receipt panel exchanges an applicant's passcode at the token endpoint from
  # www, in a browser, with this client id. Keycloak's own CORS answer for that comes from the
  # client's web origins, and "+" covers only the origins of its redirect URIs — none of which is
  # www. Additive and idempotent: nothing else in the list is touched.
  id=$(client_uuid mobile-app); [ -n "$id" ] || die "client mobile-app not found in $REALM"
  kc "$ADMIN/clients/$id" > "$WORK/mobile.json"
  if jq -e '.webOrigins | index("https://www.youdrop.shop")' "$WORK/mobile.json" >/dev/null; then
    ok "mobile-app already allows the public site's origin"
  else
    jq '.webOrigins += ["https://www.youdrop.shop"]' "$WORK/mobile.json" > "$WORK/mobile-new.json"
    check "mobile-app accepted the public site's origin" 204 \
      "$(kc -o /dev/null -w '%{http_code}' -X PUT -H 'Content-Type: application/json' --data-binary @"$WORK/mobile-new.json" "$ADMIN/clients/$id")"
  fi

  edge_identity_proofs "$loopback"
}

# What the environment reports about itself afterwards. Codes, counts and names only.
edge_identity_proofs() {   # edge_identity_proofs <keep|drop>
  local loopback="$1" id
  echo "== what the realm says now"
  kc_fresh
  check "sslRequired" external "$(kc "$ADMIN" | jq -r '.sslRequired')"
  id=$(client_uuid delivery-portal)
  kc "$ADMIN/clients/$id" > "$WORK/portal-now.json"
  check "delivery-portal: the password grant is off" false "$(jq -r '.directAccessGrantsEnabled' "$WORK/portal-now.json")"
  check "delivery-portal: client session idle" 28800 "$(jq -r '.attributes["client.session.idle.timeout"]' "$WORK/portal-now.json")"
  check "delivery-portal: client session max" 86400 "$(jq -r '.attributes["client.session.max.lifespan"]' "$WORK/portal-now.json")"
  check "delivery-portal: loopback redirect URIs ($loopback)" \
    "$([ "$loopback" = keep ] && echo present || echo none)" \
    "$(jq -r '[.redirectUris[] | select(test("^http://(localhost|127\\.0\\.0\\.1)"))] | if length > 0 then "present" else "none" end' "$WORK/portal-now.json")"
  check "delivery-portal: the deployed portal can still be redirected to" present \
    "$(jq -r --arg h "https://portal-$ENV_NAME.youdrop.shop/*" '[.redirectUris[] | select(. == $h)] | if length > 0 then "present" else "MISSING" end' "$WORK/portal-now.json")"
  kc_fresh
  check "delivery-portal: offline_access is gone" 0 \
    "$( { kc "$ADMIN/clients/$id/default-client-scopes"; kc "$ADMIN/clients/$id/optional-client-scopes"; } | jq -s -r '[.[][] | select(.name == "offline_access")] | length')"

  echo "== what a client can actually do"
  # The password the proof needs comes out of the Secret into a private file and is never printed
  # or passed on a command line.
  if secret_has demo-logins backoffice; then
    secret_key_to demo-logins backoffice "$WORK/bo-pass"
    # 400 unauthorized_client: Keycloak's answer when a client has no direct access grant. A 401
    # would mean the password was wrong, which would make this proof meaningless.
    check "delivery-portal refuses the password grant" 400 "$(pw_code delivery-portal backoffice "$WORK/bo-pass")"
    check "mobile-app still signs the back office in" 200 "$(pw_code mobile-app backoffice "$WORK/bo-pass")"
    rm -f "$WORK/bo-pass"
  else
    skip "no demo-logins/backoffice in $NS, so the grant proofs are skipped"
  fi

  echo "== the public hostname"
  # These prove the EDGE, which Argo applies from the manifests — not this script. They fail until
  # overlays/<env>/ingress.yaml is synced, and that is the point: this is where you find out.
  check "the admin console is refused on $IAM" 403 "$(curl -s -o /dev/null -w '%{http_code}' "$IAM/admin/master/console/")"
  check "the admin REST API is refused on $IAM" 403 "$(curl -s -o /dev/null -w '%{http_code}' "$IAM/admin/realms/$REALM")"
  check "the realm's discovery document is still public" 200 \
    "$(curl -s -o /dev/null -w '%{http_code}' "$IAM/realms/$REALM/.well-known/openid-configuration")"
  check "the login page is still public" 200 \
    "$(curl -s -o /dev/null -w '%{http_code}' "$IAM/realms/$REALM/account/")"
}

step_refresh_rotation() {
  # PT-3, last and alone: every refresh grant returns a new token and destroys the one it was
  # bought with, and a second use of a destroyed token ends the whole session.
  #
  # That last rule is why this is not part of edge-identity. A client that can run two refresh
  # grants at once signs itself out under it, and the fix for that ships in the app:
  # AuthService.refresh serialises them (delivery_core, auth_refresh_rotation_test.dart). Run this
  # only once the portal build being served and the APK people have installed both contain it.
  # An older build is not broken by rotation, but it can lose a session to a race it used to win.
  local before code
  kc_login
  kc "$ADMIN" > "$WORK/realm.json"
  jq -e '.realm' "$WORK/realm.json" >/dev/null 2>&1 || die "could not read realm $REALM from the admin API"
  before=$(jq -r '"\(.revokeRefreshToken) \(.refreshTokenMaxReuse)"' "$WORK/realm.json")
  if [ "$before" = "true 0" ]; then
    ok "refresh tokens already rotate and cannot be reused; nothing written"
  else
    jq '.revokeRefreshToken = true | .refreshTokenMaxReuse = 0' "$WORK/realm.json" > "$WORK/realm-new.json"
    code=$(kc -o /dev/null -w '%{http_code}' -X PUT -H 'Content-Type: application/json' --data-binary @"$WORK/realm-new.json" "$ADMIN")
    check "the realm accepted refresh-token rotation (was: $before)" 204 "$code"
  fi
  kc_fresh
  check "revokeRefreshToken" true "$(kc "$ADMIN" | jq -r '.revokeRefreshToken')"
  kc_fresh
  check "refreshTokenMaxReuse" 0 "$(kc "$ADMIN" | jq -r '.refreshTokenMaxReuse')"

  # One real round trip: a grant, the token it returns, and then the same token again. The second
  # one must be refused — that is rotation working, and a 200 here would mean it is not on.
  if secret_has demo-logins customer; then
    secret_key_to demo-logins customer "$WORK/cust-pass"
    curl -s -X POST "$TOKEN_URL" -d grant_type=password -d client_id=mobile-app -d username=customer \
      --data-urlencode "password@$WORK/cust-pass" | jq -j '.refresh_token // empty' > "$WORK/rt1"
    rm -f "$WORK/cust-pass"
    if [ -s "$WORK/rt1" ]; then
      curl -s -X POST "$TOKEN_URL" -d grant_type=refresh_token -d client_id=mobile-app \
        --data-urlencode "refresh_token@$WORK/rt1" | jq -j '.refresh_token // empty' > "$WORK/rt2"
      [ -s "$WORK/rt2" ] && ok "a refresh returned a token" || bad "the first refresh returned nothing"
      check "the spent token is refused" 400 "$(curl -s -o /dev/null -w '%{http_code}' -X POST "$TOKEN_URL" \
        -d grant_type=refresh_token -d client_id=mobile-app --data-urlencode "refresh_token@$WORK/rt1")"
      check "the rotated token still works" 200 "$(curl -s -o /dev/null -w '%{http_code}' -X POST "$TOKEN_URL" \
        -d grant_type=refresh_token -d client_id=mobile-app --data-urlencode "refresh_token@$WORK/rt2")"
      rm -f "$WORK/rt1" "$WORK/rt2"
    else
      skip "the demo customer did not sign in, so rotation is not proved end to end"
    fi
  else
    skip "no demo-logins/customer in $NS, so rotation is not proved end to end"
  fi
}

step_test_accounts() {
  local id n
  kc_login
  kc "$ADMIN/users?max=2000&briefRepresentation=true" > "$WORK/users.json"
  python3 - "$WORK/users.json" > "$WORK/test-ids" <<'PY'
import json, sys
domains = ("@youdrop.test", "@example.invalid", "@example.test")
for u in json.load(open(sys.argv[1])):
    who = ((u.get("email") or "") + " " + (u.get("username") or "")).lower()
    if u.get("enabled") and any(d in who for d in domains):
        print(u["id"])
PY
  n=$(wc -l < "$WORK/test-ids" | tr -d ' ')
  echo "enabled accounts made by the repository's test scripts in $NS: $n"
  [ "${1:-}" = --disable ] || { echo "(counted only; add --disable to disable them — reversible in the admin console)"; return 0; }
  while read -r id; do
    kc_fresh
    kc "$ADMIN/users/$id" | jq -c '.enabled = false' > "$WORK/user.json"
    check "a test account disabled" 204 "$(kc -o /dev/null -w '%{http_code}' -X PUT -H 'Content-Type: application/json' --data-binary @"$WORK/user.json" "$ADMIN/users/$id")"
    check "...and its sessions signed out" 204 "$(kc -o /dev/null -w '%{http_code}' -X POST "$ADMIN/users/$id/logout")"
  done < "$WORK/test-ids"
}

step_verify() {
  local c key u client p notready r
  echo "== $NS"
  notready=$(k get deploy,sts -o json | jq -r '.items[] | select((.status.readyReplicas // 0) < (.spec.replicas // 1)) | .metadata.name' | tr '\n' ' ')
  check "every Deployment and StatefulSet is ready" none "${notready:-none}"
  check "Argo CD application $NS" Synced/Healthy "$(kubectl -n argocd get applications.argoproj.io "$NS" -o jsonpath='{.status.sync.status}/{.status.health.status}' 2>/dev/null)"
  check "the API refuses an anonymous call" 401 "$(curl -s -o /dev/null -w '%{http_code}' "$API/api/banners")"
  secret_key_to demo-logins customer "$WORK/cust"
  curl -s -X POST "$TOKEN_URL" -d grant_type=password -d client_id=mobile-app -d username=customer --data-urlencode "password@$WORK/cust" \
    | jq -j '.access_token // empty' > "$WORK/cust-token"
  { printf 'Authorization: Bearer '; cat "$WORK/cust-token"; echo; } > "$WORK/cust-auth"
  check "the API answers the demo customer" 200 "$(curl -s -o /dev/null -w '%{http_code}' -H @"$WORK/cust-auth" "$API/api/banners")"

  echo "== service-account clients"
  kc_login
  for c in $CLIENTS; do
    kc_fresh
    key=$(client_key "$c")
    client_secret_to "$c" "$WORK/kc-$c"
    check "$c: Keycloak holds keycloak-clients' value" same "$(same "$(file_sha "$WORK/kc-$c")" "$(secret_sha keycloak-clients "$key")")"
    check "$c: the running pod holds it too" same "$(same "$(env_sha "$c" KEYCLOAK_CLIENT_SECRET)" "$(secret_sha keycloak-clients "$key")")"
    check "$c: it gets a token" 200 "$(cc_code "$c" "$WORK/kc-$c")"
    if old_value client "$c" "$WORK/old-$c"; then check "$c: the repository's secret is refused" 401 "$(cc_code "$c" "$WORK/old-$c")"; else skip "$c: no $OLD_TAR"; fi
  done
  for p in accounting-service notifications-manager; do
    check "Vault's secret/$p carries no client secret" absent "$(vault_keys "$p" | grep -q client-secret && echo present || echo absent)"
  done
  check "platform-secrets holds no ONBOARDING_CLIENT_SECRET" absent "$(secret_has platform-secrets ONBOARDING_CLIENT_SECRET && echo present || echo absent)"

  echo "== demo logins"
  for u in $DEMO_USERS; do
    client=$(demo_client "$u")
    secret_key_to demo-logins "$u" "$WORK/demo-$u"
    check "$u: demo-logins' password signs in" 200 "$(pw_code "$client" "$u" "$WORK/demo-$u")"
    if old_value user "$u" "$WORK/old-$u"; then check "$u: the repository's password is refused" 401 "$(pw_code "$client" "$u" "$WORK/old-$u")"; else skip "$u: no $OLD_TAR"; fi
  done

  echo "== webhooks"
  for p in WHATSAPP_APP_SECRET WHATSAPP_VERIFY_TOKEN; do
    check "whatsapp-service holds whatsapp-webhook's $p" same "$(same "$(env_sha whatsapp-service "$p")" "$(secret_sha whatsapp-webhook "$p")")"
  done
  secret_key_to whatsapp-webhook WHATSAPP_APP_SECRET "$WORK/wa-new"
  check "WhatsApp webhook accepts the new secret's signature" 200 "$(wa_code "$WORK/wa-new")"
  if old_value whatsapp WHATSAPP_APP_SECRET "$WORK/wa-old"; then check "WhatsApp webhook refuses the repository's signature" 401 "$(wa_code "$WORK/wa-old")"; else skip "WhatsApp: no $OLD_TAR"; fi
  if old_value whatsapp WHATSAPP_VERIFY_TOKEN "$WORK/vt-old"; then check "WhatsApp verify refuses the repository's token" 403 "$(verify_token_code "$WORK/vt-old")"; fi
  check "sms-connector holds sms-dlr's secret" same "$(same "$(env_sha sms-connector SMS_DEV_DLR_SECRET)" "$(secret_sha sms-dlr SMS_DEV_DLR_SECRET)")"
  secret_key_to sms-dlr SMS_DEV_DLR_SECRET "$WORK/dlr-new"
  check "DLR webhook accepts the new secret's signature" 204 "$(dlr_code "$WORK/dlr-new")"
  if old_value dlr - "$WORK/dlr-old"; then check "DLR webhook refuses the repository's signature" 401 "$(dlr_code "$WORK/dlr-old")"; else skip "DLR: no $OLD_TAR"; fi

  echo "== ops basic auth"
  check "monitoring refuses no password" 401 "$(ops_code)"
  if [ -s "$OPS_PASSWORD_FILE" ]; then
    r=$(ops_code "$OPS_PASSWORD_FILE")
    check "monitoring opens with $OPS_PASSWORD_FILE" accepted "$([ "$r" != 401 ] && [ "$r" != 000 ] && echo accepted || echo "$r")"
  else bad "$OPS_PASSWORD_FILE is missing"; fi
  if old_value opsline - "$WORK/ops-old"; then
    check "ops-auth-users no longer holds the repository's hash" 0 "$(k get secret ops-auth-users -o jsonpath='{.data.users}' | base64 -d | grep -c -F -f "$WORK/ops-old")"
  fi

  echo "== database roles nothing logs in as"
  for r in $UNUSED_ROLES; do check "$r cannot log in" f "$(psqlq "select rolcanlogin from pg_roles where rolname = '$r'")"; done

  echo
  if [ "$FAILS" = 0 ]; then echo "verify $NS: all checks passed"; else echo "verify $NS: $FAILS check(s) FAILED"; exit 1; fi
}

case "$STEP" in
  check-old) step_check_old "$@" ;;
  backup) step_backup ;;
  adopt) step_adopt ;;
  demo-logins) step_demo_logins ;;
  webhooks) step_webhooks "$@" ;;
  ops-auth) step_ops_auth ;;
  vault-reseed) step_vault_reseed ;;
  client) step_client "$@" ;;
  drop-stale-keys) step_drop_stale_keys ;;
  lock-unused-db-roles) step_lock_unused_db_roles ;;
  test-accounts) step_test_accounts "$@" ;;
  user-profile-stamp) step_user_profile_stamp ;;
  edge-identity) step_edge_identity ;;
  refresh-rotation) step_refresh_rotation ;;
  verify) step_verify ;;
  *) die "unknown step '$STEP' (see the header of this script)" ;;
esac
[ "$FAILS" = 0 ] || { echo "$STEP: $FAILS check(s) FAILED"; exit 1; }
