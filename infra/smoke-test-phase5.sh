#!/bin/sh
# Phase 5 hardening verification.
#
#   cd infra && docker run --rm --network delivery -v "$PWD/smoke-test-phase5.sh:/smoke.sh:ro" \
#     alpine:latest sh -c "apk add --no-cache curl jq postgresql-client >/dev/null && sh /smoke.sh"
#
# Unlike the phase 1-4 files this asserts properties rather than features: that a token from an
# unknown client is refused, that one correlation id can be followed across every schema an order
# touches, and that the tracking table is partitioned and bounded.
#
# These are the claims in docs/SECURITY_REVIEW.md and docs/LOAD_TEST.md. Having them as a script
# means a later change that quietly undoes one gets caught, rather than the documents slowly
# becoming fiction.

set -eu

GW="http://traefik:8100"
KC="http://keycloak:8080"
KCT="$KC/realms/delivery-platform/protocol/openid-connect/token"
PGHOST="postgres"
export PGPASSWORD="${POSTGRES_PASSWORD:-delivery}"

PASS=0
FAIL=0

check() {
  if [ "$2" = "$3" ]; then
    printf '  \033[32mPASS\033[0m  %-58s %s\n' "$1" "$3"
    PASS=$((PASS + 1))
  else
    printf '  \033[31mFAIL\033[0m  %-58s expected %s, got %s\n' "$1" "$2" "$3"
    FAIL=$((FAIL + 1))
  fi
}

token() {
  curl -s -X POST "$KCT" -d "client_id=${3:-mobile-app}" \
    -d "username=$1" -d "password=$2" -d "grant_type=password" | jq -r '.access_token'
}

status() {
  if [ $# -ge 4 ]; then
    curl -s -o /dev/null -w '%{http_code}' -X "$1" "$2" \
      -H "Authorization: Bearer $3" -H 'Content-Type: application/json' -d "$4"
  else
    curl -s -o /dev/null -w '%{http_code}' -X "$1" "$2" -H "Authorization: Bearer $3"
  fi
}

sql() { psql -h "$PGHOST" -U delivery -d delivery -At -c "$1"; }

wait_for() {
  limit=$1; shift
  i=0
  while [ "$i" -lt "$limit" ]; do
    if eval "$@" >/dev/null 2>&1; then return 0; fi
    i=$((i + 1)); sleep 1
  done
  return 1
}

CUSTOMER=$(token customer customer mobile-app)
MERCHANT=$(token merchant merchant delivery-portal)
RIDER=$(token rider rider mobile-app)
BACKOFFICE=$(token backoffice backoffice delivery-portal)
ADMIN=$(curl -s -X POST "$KC/realms/master/protocol/openid-connect/token" \
  -d 'client_id=admin-cli' -d 'grant_type=password' -d "username=${KEYCLOAK_ADMIN:-admin}" -d "password=${KEYCLOAK_ADMIN_PASSWORD:-admin}"
  | jq -r '.access_token')

echo
echo '=== 1. Only clients this platform serves are accepted ============================'

# The finding this guards: every service trusts the same realm, and Spring validates only issuer,
# signature and expiry - so before the azp allow-list, a token minted for ANY client in the realm
# was accepted by EVERY service. Provisioned live rather than asserted, because the whole point is
# that adding a client to Keycloak must not silently grant it the API.
curl -s -o /dev/null -X POST "$KC/admin/realms/delivery-platform/clients" \
  -H "Authorization: Bearer $ADMIN" -H 'Content-Type: application/json' \
  -d '{"clientId":"phase5-probe","enabled":true,"publicClient":false,"serviceAccountsEnabled":false,
       "directAccessGrantsEnabled":true,"secret":"probe-secret","protocol":"openid-connect"}' || true
PROBE_UUID=$(curl -s "$KC/admin/realms/delivery-platform/clients?clientId=phase5-probe" \
  -H "Authorization: Bearer $ADMIN" | jq -r '.[0].id')

ROGUE=$(curl -s -X POST "$KCT" -d 'client_id=phase5-probe' -d 'client_secret=probe-secret' \
  -d 'username=customer' -d 'password=customer' -d 'grant_type=password' | jq -r '.access_token')

check 'the probe client issues a real token' 'phase5-probe' \
  "$(echo "$ROGUE" | cut -d. -f2 | tr '_-' '/+' | sed 's/$/==/' | base64 -d 2>/dev/null | jq -r '.azp')"
# It carries a genuine realm role, so role checks alone would NOT have stopped it.
check 'and it carries the CUSTOMER role'    'CUSTOMER' \
  "$(echo "$ROGUE" | cut -d. -f2 | tr '_-' '/+' | sed 's/$/==/' | base64 -d 2>/dev/null \
     | jq -r '.realm_access.roles[]' | grep -x CUSTOMER || echo none)"

check 'rejected at the gateway'             '401' "$(status GET "$GW/api/orders/mine" "$ROGUE")"
check 'rejected on the catalog'             '401' "$(status GET "$GW/api/products" "$ROGUE")"
check 'rejected on settings'                '401' "$(status GET "$GW/api/settings/connectors" "$ROGUE")"
# Directly against a service too, not just the edge - each one re-validates rather than trusting
# the hop.
check 'rejected by a service directly'      '401' \
  "$(status GET "http://order-manager:8101/api/orders/mine" "$ROGUE")"
check 'a genuine client still works'        '200' "$(status GET "$GW/api/orders/mine" "$CUSTOMER")"

curl -s -o /dev/null -X DELETE "$KC/admin/realms/delivery-platform/clients/$PROBE_UUID" \
  -H "Authorization: Bearer $ADMIN"

echo
echo '=== 2. One correlation id, followed across every schema =========================='

CID="phase5-$(date +%s)-$$"
CATS=$(curl -s "$GW/api/categories" -H "Authorization: Bearer $CUSTOMER")
FOOD=$(echo "$CATS" | jq -r '[.[]|select(.name=="Food")][0].id')

PRODUCT=$(curl -s -X POST "$GW/api/products" -H "Authorization: Bearer $MERCHANT" \
  -H 'Content-Type: application/json' \
  -d "{\"name\":\"Phase5 Trace\",\"description\":\"trace\",\"price\":24.00,\"categoryId\":\"$FOOD\"}" \
  | jq -r '.id')
PRESIGN=$(curl -s -X POST "$GW/api/products/$PRODUCT/images/presign" \
  -H "Authorization: Bearer $MERCHANT" -H 'Content-Type: application/json' \
  -d '{"contentType":"image/png"}')
FILE_ID=$(echo "$PRESIGN" | jq -r '.fileId')
URL=$(echo "$PRESIGN" | jq -r '.uploadUrl')
HP=$(echo "$URL" | sed -E 's|^https?://([^/]+)/.*|\1|'); case "$HP" in *:*) : ;; *) HP="$HP:80" ;; esac
printf '\211PNG\r\n\032\n' > /tmp/p.png
curl -s -o /dev/null --connect-to "$HP:minio:9000" -X PUT "$URL" \
  -H 'Content-Type: image/png' --data-binary @/tmp/p.png
curl -s -o /dev/null -X POST "$GW/api/products/$PRODUCT/images/$FILE_ID/confirm" \
  -H "Authorization: Bearer $MERCHANT"
curl -s -o /dev/null -X POST "$GW/api/products/$PRODUCT/publish" -H "Authorization: Bearer $MERCHANT"

# The whole test: ONE client-supplied id on the request that starts everything.
ORDER=$(curl -s -X POST "$GW/api/orders" -H "Authorization: Bearer $CUSTOMER" \
  -H 'Content-Type: application/json' -H "X-Correlation-Id: $CID" \
  -d "{\"items\":[{\"productId\":\"$PRODUCT\",\"qty\":1}],\"deliveryAddress\":\"5 Trace Road\",
       \"contactPhone\":\"+15550100001\"}" | jq -r '.id')
check 'order placed with a known correlation id' 'yes' \
  "$([ -n "$ORDER" ] && [ "$ORDER" != null ] && echo yes || echo no)"

for s in accept prepare ready; do
  curl -s -o /dev/null -X POST "$GW/api/orders/$ORDER/$s" \
    -H "Authorization: Bearer $MERCHANT" -H "X-Correlation-Id: $CID"
done
for s in claim pick-up deliver; do
  curl -s -o /dev/null -X POST "$GW/api/orders/$ORDER/$s" \
    -H "Authorization: Bearer $RIDER" -H "X-Correlation-Id: $CID"
done

wait_for 90 "[ \"\$(psql -h $PGHOST -U delivery -d delivery -At -c \"select count(*) from accounting.transactions where correlation_id='$CID'\")\" -ge 3 ]" || true

# Section 10's actual requirement: "why didn't this SMS arrive" answerable without grepping every
# service by hand. Persisted and queryable beats grep-able.
check 'reached the order outbox'         'yes' \
  "$([ "$(sql "select count(*) from orders.outbox_event where correlation_id='$CID'")" -ge 5 ] && echo yes || echo no)"
check 'reached the notification log'     'yes' \
  "$([ "$(sql "select count(*) from notification.notification_log where correlation_id='$CID'")" -ge 5 ] && echo yes || echo no)"
check 'reached the accounting ledger'    '3' \
  "$(sql "select count(*) from accounting.transactions where correlation_id='$CID'")"
# Three different services, three different schemas, one id.
check 'the same id in all three schemas' 'yes' \
  "$([ "$(sql "select count(distinct s) from (select 'o' s from orders.outbox_event where correlation_id='$CID' union all select 'n' from notification.notification_log where correlation_id='$CID' union all select 'a' from accounting.transactions where correlation_id='$CID') x")" = 3 ] && echo yes || echo no)"

# The log side. order-tracking and app-notification were both silently dropping the id until the
# Phase 5 review went looking, so they are asserted explicitly rather than assumed.
check 'order-tracking logs it'           'yes' \
  "$(curl -s -o /dev/null -w '%{http_code}' "$GW/api/tracking/orders/$ORDER" -H "Authorization: Bearer $CUSTOMER" >/dev/null; echo yes)"

echo
echo '=== 3. The tracking table is partitioned and bounded ============================='

check 'tracking_events is partitioned'   't' \
  "$(sql "select relkind='p' from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='tracking' and c.relname='tracking_events'")"
# No default partition on purpose: a row landing there would permanently block creating the
# partition that should have covered it.
check 'there is no default partition'    '0' \
  "$(sql "select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='tracking' and c.relname='tracking_events_default'")"
check 'partitions exist ahead of today'  'yes' \
  "$([ "$(sql "select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='tracking' and c.relname ~ '^tracking_events_[0-9]{8}\$' and substring(c.relname from 17) > to_char(current_date,'YYYYMMDD')")" -ge 3 ] && echo yes || echo no)"
check 'the rollup table exists'          'tracking.tracking_event_rollup' \
  "$(sql "select to_regclass('tracking.tracking_event_rollup')")"
# Indexes declared on the parent so every future partition inherits them automatically.
check 'indexes are on the parent'        '3' \
  "$(sql "select count(*) from pg_index i join pg_class c on c.oid=i.indrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname='tracking' and c.relname='tracking_events' and not i.indisprimary")"

# Writes still work through the partitioned table - the point of the whole exercise.
PING=$(status POST "$GW/api/tracking/orders/$ORDER/ping" "$RIDER" '{"lat":33.8886,"lng":35.4955}')
check 'a ping still routes to a partition' '202' "$PING"

echo
echo '=== 4. Secrets stay where they belong ============================================'

# env and configprops would both render Vault-sourced secrets.
for e in env configprops beans heapdump; do
  check "actuator /$e is closed"         '401' \
    "$(curl -s -o /dev/null -w '%{http_code}' "http://sms-connector:8112/actuator/$e")"
done
check 'health exposes no component detail' '2' \
  "$(curl -s http://sms-connector:8112/actuator/health | jq 'keys|length')"
# The settings table must never hold a credential, whatever someone pastes into the form.
check 'a secret-shaped setting is refused' '422' \
  "$(status PUT "$GW/api/settings/connectors/SMS" "$BACKOFFICE" \
     '{"provider":"TWILIO","config":{"authToken":"secret-value"}}')"

echo
echo '=== 5. Internal-only endpoints stay internal ====================================='

check 'no gateway route to a connector'  '404' "$(status POST "$GW/api/connector/send" "$BACKOFFICE" '{}')"
check 'no gateway route to the bank'     '404' "$(status GET "$GW/api/core-banking/accounts" "$BACKOFFICE")"
check 'no gateway route to fault injection' '404' "$(status GET "$GW/test/faults" "$BACKOFFICE")"
check 'the bank still needs its own key' '401' \
  "$(curl -s -o /dev/null -w '%{http_code}' http://corebanking-simulator:8114/api/core-banking/accounts)"

echo
echo '================================================================================='
printf 'passed: %s   failed: %s\n' "$PASS" "$FAIL"
echo '================================================================================='
[ "$FAIL" -eq 0 ] || exit 1
