#!/bin/sh
# Makes the demo `carrier` account staff of a real delivery company.
#
# The realm seeds a user holding CARRIER, and nothing ever seeds provider_users — so on a fresh
# environment that account belongs to no company, and every carrier surface answers 404 "You are
# not a member of any delivery company". It reads as a broken feature; it is a missing fixture.
# The partner API keys endpoint is where this finally became obvious, because it is the first
# carrier feature whose failure is a hard 404 rather than an empty list.
#
# A runtime script rather than a migration, because Keycloak generates the user's `sub` at import
# time: no SQL file can name it. Resolve by username, attach through the platform's own API.
#
# Idempotent: attaching somebody already attached is a no-op, and the unique index on user_ref
# means a second company would be refused anyway.
set -eu
apk add --no-cache curl jq >/dev/null 2>&1

KC_INTERNAL=http://keycloak:8080
GW=http://traefik:8100
CARRIER_USER="${CARRIER_USERNAME:-carrier}"

ADMIN=$(curl -s -X POST "$KC_INTERNAL/realms/master/protocol/openid-connect/token" \
  -d client_id=admin-cli -d grant_type=password \
  -d "username=$KEYCLOAK_ADMIN" -d "password=$KEYCLOAK_ADMIN_PASSWORD" | jq -r .access_token)

SUB=$(curl -s -H "Authorization: Bearer $ADMIN" \
  "$KC_INTERNAL/admin/realms/delivery-platform/users?username=$CARRIER_USER&exact=true" \
  | jq -r '.[0].id // empty')
[ -n "$SUB" ] || { echo "no such user: $CARRIER_USER"; exit 1; }

BO=$(curl -s -X POST "$KC_INTERNAL/realms/delivery-platform/protocol/openid-connect/token" \
  -d client_id=delivery-portal -d grant_type=password \
  -d "username=${BACKOFFICE_USERNAME:-backoffice}" -d "password=${BACKOFFICE_PASSWORD:-400004}" \
  | jq -r .access_token)

# A real company, not the platform's own in-house fleet: the in-house fleet is YouDrop's own riders,
# and giving a third-party login administrative rights over it would be exactly the claim the
# owner_ref check in V16 exists to prevent.
PROVIDER=$(curl -s "$GW/api/delivery-providers" -H "Authorization: Bearer $BO" \
  | jq -r '[(.content // .)[] | select(.kind != "PLATFORM")][0].id // empty')
if [ -z "$PROVIDER" ]; then
  echo "no non-platform delivery company exists to attach to; nothing done"
  exit 0
fi

CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$GW/api/delivery-providers/$PROVIDER/staff" \
  -H "Authorization: Bearer $BO" -H 'Content-Type: application/json' \
  -d "{\"riderRef\":\"$SUB\"}")
echo "attach $CARRIER_USER to $PROVIDER -> $CODE"

# Prove it from the carrier's own side, which is the thing that was broken.
CAR=$(curl -s -X POST "$KC_INTERNAL/realms/delivery-platform/protocol/openid-connect/token" \
  -d client_id=delivery-portal -d grant_type=password \
  -d "username=$CARRIER_USER" -d "password=${CARRIER_PASSWORD:-500005}" | jq -r .access_token)
echo "carrier can now read its own company -> $(curl -s -o /dev/null -w '%{http_code}' \
  "$GW/api/delivery-providers/my-company" -H "Authorization: Bearer $CAR")"
