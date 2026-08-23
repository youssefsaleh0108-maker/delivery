#!/usr/bin/env bash
# Registers Google as an identity provider on a RUNNING Keycloak.
#
#   cd /opt/delivery/infra
#   GOOGLE_CLIENT_ID=... GOOGLE_CLIENT_SECRET=... ./keycloak/configure-google-idp.sh
#
# WHY A SCRIPT AND NOT JUST THE REALM FILE. The realm import runs once, against an empty Keycloak
# database. Every environment that is already up — which is all of them — imported its realm before
# this provider existed, so editing realm-delivery-platform.json changes nothing there. That file
# is for the next fresh install; this is for the one that is running.
#
# The credentials are read from the environment and never written to the repo. Put them in
# infra/.env beside the rest and this picks them up:
#
#   GOOGLE_CLIENT_ID=...apps.googleusercontent.com
#   GOOGLE_CLIENT_SECRET=...
#
# Idempotent: re-running updates the existing provider rather than failing on a duplicate alias.
set -euo pipefail

ALIAS="google"
REALM="delivery-platform"
NETWORK="${DOCKER_NETWORK:-delivery}"
KC="http://keycloak:8080"

# Sourced if present so the usual `cd infra && ./keycloak/configure-google-idp.sh` works with no
# extra arguments.
if [ -f .env ]; then
    set -a
    # shellcheck disable=SC1091
    . ./.env
    set +a
fi

: "${GOOGLE_CLIENT_ID:?Set GOOGLE_CLIENT_ID (in infra/.env or the environment)}"
: "${GOOGLE_CLIENT_SECRET:?Set GOOGLE_CLIENT_SECRET (in infra/.env or the environment)}"
: "${KEYCLOAK_ADMIN:?Set KEYCLOAK_ADMIN}"
: "${KEYCLOAK_ADMIN_PASSWORD:?Set KEYCLOAK_ADMIN_PASSWORD}"

curl_in() { docker run --rm --network "$NETWORK" curlimages/curl:latest -s "$@"; }

echo "==> Getting an admin token"
TOKEN=$(curl_in -X POST "$KC/realms/master/protocol/openid-connect/token" \
    -d "client_id=admin-cli" -d "grant_type=password" \
    -d "username=$KEYCLOAK_ADMIN" -d "password=$KEYCLOAK_ADMIN_PASSWORD" \
    | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p')
[ -n "$TOKEN" ] || { echo "Could not authenticate to Keycloak." >&2; exit 1; }

# trustEmail: Google has already verified the address, so requiring the user to confirm it again
# would send a second verification mail for an address that is provably theirs — and on a first
# broker login that extra step is where people give up.
BODY=$(cat <<JSON
{
  "alias": "$ALIAS",
  "displayName": "Google",
  "providerId": "google",
  "enabled": true,
  "trustEmail": true,
  "storeToken": false,
  "linkOnly": false,
  "firstBrokerLoginFlowAlias": "first broker login",
  "config": {
    "clientId": "$GOOGLE_CLIENT_ID",
    "clientSecret": "$GOOGLE_CLIENT_SECRET",
    "defaultScope": "openid profile email",
    "syncMode": "IMPORT",
    "useJwksUrl": "true"
  }
}
JSON
)

TMP=$(mktemp)
printf '%s' "$BODY" > "$TMP"
trap 'rm -f "$TMP"' EXIT

if curl_in -o /dev/null -w '%{http_code}' "$KC/admin/realms/$REALM/identity-provider/instances/$ALIAS" \
        -H "Authorization: Bearer $TOKEN" | grep -q '^200$'; then
    echo "==> Updating the existing '$ALIAS' provider"
    CODE=$(docker run --rm --network "$NETWORK" -v "$TMP:/idp.json:ro" curlimages/curl:latest \
        -s -o /dev/null -w '%{http_code}' -X PUT \
        "$KC/admin/realms/$REALM/identity-provider/instances/$ALIAS" \
        -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d @/idp.json)
else
    echo "==> Creating the '$ALIAS' provider"
    CODE=$(docker run --rm --network "$NETWORK" -v "$TMP:/idp.json:ro" curlimages/curl:latest \
        -s -o /dev/null -w '%{http_code}' -X POST \
        "$KC/admin/realms/$REALM/identity-provider/instances" \
        -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d @/idp.json)
fi

case "$CODE" in
    20*) echo "==> Done ($CODE)" ;;
    *)   echo "Keycloak refused the provider: HTTP $CODE" >&2; exit 1 ;;
esac

cat <<'NOTE'

The redirect URI to register on the Google OAuth client — it must match EXACTLY, including the
scheme and port, or Google refuses the sign-in with redirect_uri_mismatch:

  http://94.72.112.156:8180/realms/delivery-platform/broker/google/endpoint

Google will not accept a plain-HTTP redirect for a public IP on a new OAuth client. If it refuses,
that is the domain-and-TLS work, not a mistake here.
NOTE
