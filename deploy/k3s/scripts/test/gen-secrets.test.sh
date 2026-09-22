#!/bin/sh
# Offline test of gen-secrets.sh against a fake kubectl that keeps Secrets as directories.
#   sh deploy/k3s/scripts/test/gen-secrets.test.sh
# Pins what the script must do now that no credential lives in the repository: mint every Secret a
# NEW environment needs (including the ones the realm import and the services read), never invent
# Keycloak-bound values for an EXISTING environment, never mistake a failed lookup for "absent",
# and never print a value. It compares values itself and prints only ok/FAIL.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
GEN="$HERE/../gen-secrets.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fails=0
ok()   { echo "  ok  $*"; }
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }

mkdir -p "$T/bin"
cat > "$T/bin/kubectl" <<'EOF'
#!/bin/sh
# Fake: kubectl -n NS get secret NAME -o name | kubectl -n NS create secret generic NAME --from-file=DIR
[ "$1" = -n ] && shift 2
case "$1 $2" in
  "get secret")
    [ -n "${FAKE_KUBECTL_ERROR:-}" ] && { echo "Unable to connect to the server" >&2; exit 1; }
    [ -d "$STATE/$3" ] && { echo "secret/$3"; exit 0; }
    echo "Error from server (NotFound): secrets \"$3\" not found" >&2; exit 1 ;;
  "create secret")
    name=$4; dir=${5#--from-file=}
    [ -d "$STATE/$name" ] && { echo "AlreadyExists" >&2; exit 1; }
    mkdir -p "$STATE/$name" && cp "$dir"/* "$STATE/$name/" && echo "secret/$name created" ;;
  *) echo "fake kubectl: unexpected $*" >&2; exit 2 ;;
esac
EOF
chmod +x "$T/bin/kubectl"

run() { # run <state-dir> -> output in $T/out
  STATE="$1" PATH="$T/bin:$PATH" OPS_PASSWORD_FILE="$1.ops-password" TMPDIR="$T" \
    sh "$GEN" delivery-test > "$T/out" 2>&1
}
keys() { ls "$1" 2>/dev/null | tr '\n' ' ' | sed 's/ $//'; }
leaks() { # every minted value (and the ops password) looked for in the output; prints only a count
  n=0
  for f in "$1"/*/* "$1.ops-password"; do
    [ -f "$f" ] || continue
    v=$(head -n1 "$f")
    printf '%s' "$v" | grep -qE '^([A-Za-z0-9]{32}|[0-9]{6})$' || continue   # fixed usernames are not secrets
    grep -qF -- "$v" "$T/out" && n=$((n + 1))
  done
  echo "$n"
}

echo "== a new environment gets every Secret, random where it should be =="
S="$T/new"; mkdir "$S"
run "$S" && ok "exits 0" || fail "exit status $? on a new environment"
[ "$(keys "$S/keycloak-clients")" = "ACCOUNTING_CLIENT_SECRET NOTIFICATIONS_CLIENT_SECRET ONBOARDING_CLIENT_SECRET ORDER_MANAGER_CLIENT_SECRET" ] \
  && ok "keycloak-clients has the four client secrets" || fail "keycloak-clients keys: $(keys "$S/keycloak-clients")"
[ "$(keys "$S/demo-logins")" = "backoffice carrier customer merchant rider" ] \
  && ok "demo-logins has the five demo users" || fail "demo-logins keys: $(keys "$S/demo-logins")"
[ "$(keys "$S/whatsapp-webhook")" = "WHATSAPP_APP_SECRET WHATSAPP_VERIFY_TOKEN" ] \
  && ok "whatsapp-webhook has both values" || fail "whatsapp-webhook keys: $(keys "$S/whatsapp-webhook")"
[ "$(keys "$S/sms-dlr")" = "SMS_DEV_DLR_SECRET" ] && ok "sms-dlr has its secret" || fail "sms-dlr keys"
[ -f "$S/platform-secrets/POSTGRES_PASSWORD" ] && [ ! -e "$S/platform-secrets/ONBOARDING_CLIENT_SECRET" ] \
  && ok "platform-secrets no longer carries the onboarding client secret" || fail "platform-secrets keys: $(keys "$S/platform-secrets")"
[ "$(cat "$S/platform-secrets/KEYCLOAK_ADMIN")" = admin ] && [ "$(cat "$S/platform-secrets/RABBITMQ_USER")" = delivery ] \
  && [ ! -s "$S/platform-secrets/SMTP_PASSWORD" ] && ok "fixed usernames kept, SMTP_PASSWORD left empty" || fail "fixed values"
bad=0
for f in "$S"/keycloak-clients/* "$S"/demo-logins/backoffice "$S"/whatsapp-webhook/* "$S"/sms-dlr/* "$S"/platform-secrets/*_PASSWORD "$S"/platform-secrets/VAULT_*; do
  case "$f" in */SMTP_PASSWORD) continue ;; esac
  v=$(cat "$f"); printf '%s' "$v" | grep -qE '^[A-Za-z0-9]{32}$' || bad=$((bad + 1))
done
[ "$bad" = 0 ] && ok "every minted secret is 32 letters or digits" || fail "$bad minted value(s) are not 32 alphanumerics"
bad=0
for u in customer rider merchant carrier; do
  printf '%s' "$(cat "$S/demo-logins/$u")" | grep -qE '^[0-9]{6}$' || bad=$((bad + 1))
done
[ "$bad" = 0 ] && ok "the four phone logins get six-digit passcodes (the app accepts nothing else)" \
  || fail "$bad phone demo login(s) without a six-digit passcode"
[ "$(sort -u "$S"/keycloak-clients/* "$S"/demo-logins/* | wc -l | tr -d ' ')" = 9 ] \
  && ok "no two minted values are equal" || fail "duplicate minted values"
line=$(cat "$S/ops-auth-users/users")
salt=$(printf '%s' "$line" | cut -d'$' -f3)
again=$(openssl passwd -apr1 -salt "$salt" -stdin < "$S.ops-password" | tr -d '\r')
[ "$line" = "ops:$again" ] && ok "ops-auth-users holds the apr1 hash of the password in the ops file" \
  || fail "ops-auth-users does not match the ops password file"
[ "$(leaks "$S")" = 0 ] && ok "no value appears in the output" || fail "$(leaks "$S") value(s) printed"

echo "== running it again changes nothing =="
before=$(cat "$S"/*/* | cksum)
run "$S" && [ "$(cat "$S"/*/* | cksum)" = "$before" ] && ok "second run leaves every Secret alone" || fail "second run changed a Secret"

echo "== an existing environment is never handed Keycloak values it does not hold =="
E="$T/existing"; mkdir -p "$E/platform-secrets" "$E/ops-auth-users"
echo x > "$E/platform-secrets/POSTGRES_PASSWORD"; echo 'ops:the-existing-entry' > "$E/ops-auth-users/users"
run "$E" && ok "exits 0" || fail "exit status on an existing environment"
[ ! -e "$E/keycloak-clients" ] && [ ! -e "$E/demo-logins" ] && ok "keycloak-clients and demo-logins not invented" \
  || fail "minted Keycloak-bound Secrets for an existing environment"
grep -q "MISSING: keycloak-clients" "$T/out" && grep -q "MISSING: demo-logins" "$T/out" \
  && ok "says which ones are missing and how to create them" || fail "no MISSING notice"
[ -d "$E/whatsapp-webhook" ] && [ -d "$E/sms-dlr" ] && ok "webhook Secrets created (consistent at any time)" || fail "webhook Secrets missing"
[ "$(cat "$E/ops-auth-users/users")" = 'ops:the-existing-entry' ] && [ ! -e "$E.ops-password" ] \
  && ok "existing ops-auth-users untouched" || fail "ops-auth-users was replaced"

echo "== a failed lookup stops the script instead of reading as absent =="
F="$T/failing"; mkdir "$F"
FAKE_KUBECTL_ERROR=1 run "$F" && fail "exited 0 although kubectl could not answer" || ok "exits non-zero"
[ -z "$(ls "$F")" ] && ok "created nothing" || fail "created $(keys "$F") without knowing what existed"

echo
[ "$fails" = 0 ] && echo "gen-secrets: all checks passed" || { echo "gen-secrets: $fails check(s) failed"; exit 1; }
