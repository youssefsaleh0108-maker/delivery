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

# WHICH FIRST-BROKER-LOGIN FLOW THIS PROVIDER GETS.
#
# This is a whole-representation PUT, so whatever is named here WINS — omitting the field would not
# preserve the current value, it would reset it to the built-in. That matters because
# apply-identity-updates.sh installs a hardened copy of the built-in flow (the one that refuses to
# link an incoming Google login to an existing local account on the strength of an emailed link),
# and running this script afterwards must not quietly hand account linking back to the weaker flow.
#
# So: look for the hardened flow, and use it if this realm has it.
echo "==> Checking which first-broker-login flow this realm has"
FLOWS=$(curl_in "$KC/admin/realms/$REALM/authentication/flows?briefRepresentation=true" \
    -H "Authorization: Bearer $TOKEN")
if printf '%s' "$FLOWS" | grep -q 'youdrop-first-broker-login'; then
    BROKER_FLOW="youdrop-first-broker-login"
    echo "    hardened flow found"
else
    BROKER_FLOW="first broker login"
    echo "    hardened flow NOT found — falling back to the built-in."
    echo "    Apply keycloak/apply-identity-updates.sh and then re-run this, or account linking"
    echo "    is left on the mail-link route. See SOCIAL-SIGN-IN-SETUP.md."
fi

# trustEmail: Google has already verified the address, so requiring the user to confirm it again
# would send a second verification mail for an address that is provably theirs — and on a first
# broker login that extra step is where people give up. It is only safe in combination with the
# hardened flow above; see the long note in apply-identity-updates.sh for the attack it closes.
#
# prompt=select_account: without it Google silently reuses whichever account the browser is already
# signed in to, which on a shared or family device signs somebody into the wrong YouDrop account
# with no screen in between saying so.
BODY=$(cat <<JSON
{
  "alias": "$ALIAS",
  "displayName": "Google",
  "providerId": "google",
  "enabled": true,
  "trustEmail": true,
  "storeToken": false,
  "addReadTokenRoleOnCreate": false,
  "linkOnly": false,
  "hideOnLoginPage": false,
  "firstBrokerLoginFlowAlias": "$BROKER_FLOW",
  "config": {
    "clientId": "$GOOGLE_CLIENT_ID",
    "clientSecret": "$GOOGLE_CLIENT_SECRET",
    "defaultScope": "openid profile email",
    "prompt": "select_account",
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

echo "==> Now re-apply the mappers and the hardened flow binding:"
echo "    docker compose cp keycloak/apply-identity-updates.sh keycloak:/tmp/identity-updates.sh \\"
echo "      && docker compose exec -T keycloak sh /tmp/identity-updates.sh"

cat <<'NOTE'

The redirect URI to register on the Google OAuth client — it must match EXACTLY, including the
scheme and the absence of a port, or Google refuses the sign-in with redirect_uri_mismatch:

  https://iam-dev.youdrop.shop/realms/delivery-platform/broker/google/endpoint

That is Keycloak's own address, NOT the app's and NOT the API's. The app's redirect
(com.delivery.app://oauth2redirect) is between the app and Keycloak and Google never sees it.

Google will not accept http, and will not accept a bare IP or a port on a public host. So
KEYCLOAK_PUBLIC_URL must be https://iam-dev.youdrop.shop before any of this can work — an
http://<ip>:8180 issuer cannot be registered with Google at all. See SOCIAL-SIGN-IN-SETUP.md.
NOTE
