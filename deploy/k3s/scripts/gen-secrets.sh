#!/bin/sh
# Creates (or leaves alone) the Secrets one environment's namespace needs.
#
# Run ON THE SERVER, once per environment:   sh gen-secrets.sh delivery-dev
#
# Idempotent by refusal: a Secret that already exists is never touched. Regenerating passwords
# under a stateful environment would strand Postgres, RabbitMQ and MinIO data behind credentials
# nothing knows any more, and would split Keycloak's clients from the services that present their
# secrets. Delete the Secrets AND the namespace's PVCs to start over; to replace a value in a
# running environment, use scripts/rotate-secrets.sh.
#
# What it creates, and who reads it:
#   platform-secrets  infrastructure credentials (Postgres, Redis, RabbitMQ, MinIO, the Keycloak
#                     bootstrap admin, the Config Server, Vault). Every Spring service imports it
#                     whole, so nothing that only one service needs belongs in it.
#   keycloak-clients  the four service-account client secrets (onboarding-service,
#                     accounting-service, notifications-manager, order-manager). The realm file
#                     names them as `${...}` placeholders that Keycloak fills from this Secret at
#                     its first-boot import, and each service presents its own from the same Secret.
#   demo-logins       the five demo logins' passwords, one key per username
#                     (customer/rider/merchant/backoffice/carrier): the realm import sets them and
#                     scripts/e2e-smoke.sh signs in with them. Six-digit passcodes, as the app
#                     requires, except backoffice's (see below).
#   whatsapp-webhook  the WhatsApp webhook's HMAC secret and verify token (whatsapp-service).
#   sms-dlr           the dev-passthrough delivery-receipt signing secret (sms-connector).
#   ops-auth-users    the basic-auth login in front of the monitoring-<env> consoles. Only its hash
#                     is in the Secret; the password goes, for the operator, to
#                     /root/ops-auth-password-<env>.txt (mode 600). It is never printed.
#
# Until 2026-09 the client secrets, the demo passwords, the WhatsApp values and the ops hash were
# literals in the repository. None of them is any more; this script and the box are their only
# source.
#
# keycloak-clients and demo-logins are minted only for a NEW environment, i.e. while
# platform-secrets does not exist yet: their values must be what Keycloak holds, and Keycloak takes
# them only at its first-boot import. In an existing environment a missing one is reported, not
# invented — scripts/rotate-secrets.sh creates it from Keycloak's live state.
#
# One slot is created EMPTY, for the owner to fill: SMTP_PASSWORD (the mail relay).
#
# The Claude API key (Merchant Blitz's photo reader) is deliberately NOT a slot here. Every service
# Deployment imports platform-secrets whole, so a key in it would reach every pod on the platform;
# it lives in its own Secret, anthropic-api, which only product-service references and which the
# owner creates by hand — see deploy/k3s/README.md.
#
# No value is ever put on a command line — any user on the box can read any process's arguments —
# or printed. Each one goes through a file in a private directory in RAM, removed on exit.
set -eu

NS="${1:?usage: gen-secrets.sh <namespace>}"
ENV_NAME="${NS#delivery-}"
OPS_PASSWORD_FILE="${OPS_PASSWORD_FILE:-/root/ops-auth-password-$ENV_NAME.txt}"

umask 077
SHM=/dev/shm
[ -d "$SHM" ] || SHM="${TMPDIR:-/tmp}"
WORK=$(mktemp -d "$SHM/gen-secrets.XXXXXX")
trap 'rm -rf "$WORK"' EXIT INT TERM

# Present, absent, or stop: a failed lookup must never read as "absent", or an existing
# environment would be taken for a new one and handed client secrets its Keycloak does not hold.
exists() {
  if out=$(kubectl -n "$NS" get secret "$1" -o name 2>&1); then return 0; fi
  case "$out" in *NotFound*) return 1 ;; esac
  echo "cannot tell whether $1 exists in $NS: $out" >&2
  exit 1
}

# 32 characters of [A-Za-z0-9], about 190 bits. Letters and digits only, so a value survives every
# place it travels: a form body, a JSON string, a Keycloak placeholder, a shell word.
rand() { head -c 48 /dev/urandom | base64 | tr -d '/+=\n' | head -c 32; }

# Six random digits, uniformly: the app's sign-in accepts a passcode of exactly six digits and
# nothing else (sign_in_screen.dart: digitsOnly, length 6), so that is what a demo login that is
# used on a phone must have. Draws above the last whole million of 2^32 are redrawn, so no digit
# string is likelier than another.
passcode() {
  while :; do
    n=$(od -An -N4 -tu4 /dev/urandom | tr -d ' \n')
    [ "$n" -lt 4294000000 ] && { printf '%06d' $((n % 1000000)); return 0; }
  done
}

# mint <secret> <key>[=<fixed value>|:passcode]...: creates the Secret, one fresh random value per
# bare key (a six-digit passcode for key:passcode, or the fixed, non-secret value given), in a
# single call, unless it already exists.
mint() {
  name=$1
  shift
  if exists "$name"; then
    echo "$name already exists in $NS — leaving it alone."
    return 0
  fi
  dir="$WORK/$name"
  mkdir "$dir"
  for spec in "$@"; do
    case "$spec" in
      *=*) printf '%s' "${spec#*=}" > "$dir/${spec%%=*}" ;;
      *:passcode) passcode > "$dir/${spec%:passcode}" ;;
      *) rand > "$dir/$spec" ;;
    esac
  done
  # A directory: one key per file. `create` rather than `apply`, because apply would copy every
  # value into a last-applied-configuration annotation that `kubectl describe` prints.
  kubectl -n "$NS" create secret generic "$name" --from-file="$dir" >/dev/null
  rm -rf "$dir"
  echo "$name created in $NS."
}

# A new environment is one without platform-secrets: nothing has started in it yet, so nothing
# holds a credential that a fresh value could contradict.
if exists platform-secrets; then NEW_ENV=no; else NEW_ENV=yes; fi

# Read only by the service that verifies with them, so a fresh value is consistent at any time.
mint whatsapp-webhook WHATSAPP_APP_SECRET WHATSAPP_VERIFY_TOKEN
mint sms-dlr SMS_DEV_DLR_SECRET

if [ "$NEW_ENV" = yes ]; then
  mint keycloak-clients ONBOARDING_CLIENT_SECRET ACCOUNTING_CLIENT_SECRET NOTIFICATIONS_CLIENT_SECRET \
    ORDER_MANAGER_CLIENT_SECRET
  # The four logins used on the phone get passcodes; backoffice signs in only through the portal's
  # Keycloak page, which takes any password, and holds the widest role — so it gets a long one.
  mint demo-logins customer:passcode rider:passcode merchant:passcode backoffice carrier:passcode
  # Last, on purpose: its existence is what marks the environment as no longer new, so a run that
  # failed above is simply run again.
  mint platform-secrets \
    POSTGRES_PASSWORD \
    CONFIG_DB_USER=config_server \
    CONFIG_DB_PASSWORD \
    REDIS_PASSWORD \
    RABBITMQ_USER=delivery \
    RABBITMQ_PASSWORD \
    MINIO_ROOT_USER=delivery \
    MINIO_ROOT_PASSWORD \
    KEYCLOAK_ADMIN=admin \
    KEYCLOAK_ADMIN_PASSWORD \
    CONFIG_SERVER_USER=config \
    CONFIG_SERVER_PASSWORD \
    VAULT_ROOT_TOKEN \
    VAULT_ROLE_ID \
    VAULT_SECRET_ID \
    SMTP_PASSWORD=
else
  echo "platform-secrets already exists in $NS — leaving it alone."
  for s in keycloak-clients demo-logins; do
    exists "$s" || echo "MISSING: $s in $NS. This environment's Keycloak already holds these values," \
      "so they are not invented here: run 'bash rotate-secrets.sh $NS adopt' (keycloak-clients)" \
      "or 'bash rotate-secrets.sh $NS demo-logins'."
  done
fi

# The ops basic-auth login for monitoring-<env>: a random password, hashed here with apr1 — the one
# scheme openssl makes that Traefik's basicAuth accepts. Only the hash goes into the Secret. The
# password cannot be recovered from the hash, so it goes to a root-only file for the operator.
if exists ops-auth-users; then
  echo "ops-auth-users already exists in $NS — leaving it alone."
else
  rand > "$OPS_PASSWORD_FILE"
  echo >> "$OPS_PASSWORD_FILE"
  chmod 600 "$OPS_PASSWORD_FILE"
  mkdir "$WORK/ops-auth-users"
  printf 'ops:%s\n' "$(openssl passwd -apr1 -stdin < "$OPS_PASSWORD_FILE" | tr -d '\r')" > "$WORK/ops-auth-users/users"
  kubectl -n "$NS" create secret generic ops-auth-users --from-file="$WORK/ops-auth-users" >/dev/null
  echo "ops-auth-users created in $NS: user ops, password in $OPS_PASSWORD_FILE (mode 600)."
fi
