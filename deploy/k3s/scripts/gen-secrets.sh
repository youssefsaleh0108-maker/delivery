#!/bin/sh
# Creates (or leaves alone) the platform-secrets Secret for one environment's namespace.
#
# Run ON THE SERVER, once per environment:   sh gen-secrets.sh delivery-dev
#
# Idempotent by refusal: if the Secret already exists, nothing is touched — regenerating
# passwords under a stateful environment would strand Postgres, RabbitMQ and MinIO data behind
# credentials nothing knows any more. Delete the Secret AND the namespace's PVCs to start over.
#
# Two values are not generated:
#   - ONBOARDING_CLIENT_SECRET must match what the Keycloak realm import creates, so it is read
#     out of the realm file itself.
#   - The demo logins (customer/rider/merchant/backoffice/carrier) live in the realm file too and
#     are untouched here.
set -eu

NS="${1:?usage: gen-secrets.sh <namespace> [realm.json]}"
REALM="${2:-/opt/delivery/k3s/base/assets/keycloak/realm-delivery-platform.json}"

if kubectl -n "$NS" get secret platform-secrets >/dev/null 2>&1; then
  echo "platform-secrets already exists in $NS — leaving it alone."
  exit 0
fi

rand() { head -c 24 /dev/urandom | base64 | tr -d '/+=' | head -c 24; }

# The secret belongs to whichever clientId was seen last before it — the realm lists each
# client's fields together, whatever the whitespace style.
ONBOARDING_CLIENT_SECRET=$(awk '
  /"clientId"/ { c = $0 }
  /"secret"/ && c ~ /onboarding-service/ {
    sub(/.*"secret"[^"]*"/, ""); sub(/".*/, ""); print; exit
  }' "$REALM")
[ -n "$ONBOARDING_CLIENT_SECRET" ] || { echo "could not read onboarding client secret from $REALM"; exit 1; }

kubectl -n "$NS" create secret generic platform-secrets \
  --from-literal=POSTGRES_PASSWORD="$(rand)" \
  --from-literal=CONFIG_DB_USER=config_server \
  --from-literal=CONFIG_DB_PASSWORD="$(rand)" \
  --from-literal=REDIS_PASSWORD="$(rand)" \
  --from-literal=RABBITMQ_USER=delivery \
  --from-literal=RABBITMQ_PASSWORD="$(rand)" \
  --from-literal=MINIO_ROOT_USER=delivery \
  --from-literal=MINIO_ROOT_PASSWORD="$(rand)" \
  --from-literal=KEYCLOAK_ADMIN=admin \
  --from-literal=KEYCLOAK_ADMIN_PASSWORD="$(rand)" \
  --from-literal=CONFIG_SERVER_USER=config \
  --from-literal=CONFIG_SERVER_PASSWORD="$(rand)" \
  --from-literal=VAULT_ROOT_TOKEN="$(rand)" \
  --from-literal=VAULT_ROLE_ID="$(rand)" \
  --from-literal=VAULT_SECRET_ID="$(rand)" \
  --from-literal=SMTP_PASSWORD="" \
  --from-literal=ONBOARDING_CLIENT_SECRET="$ONBOARDING_CLIENT_SECRET"

echo "platform-secrets created in $NS."

# The ops basic-auth login for the monitoring hostname — the same hash the compose Traefik
# carried, so the password the operator knows keeps working.
kubectl -n "$NS" create secret generic ops-auth-users \
  --from-literal=users='ops:$2y$05$jZ..JpeOHQUdnP1p5AzPBuNp8CaAPY0WDkWiQ5mBdtZKiJtKH3caG' \
  2>/dev/null || echo "ops-auth-users already exists in $NS."
