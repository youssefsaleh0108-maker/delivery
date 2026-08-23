#!/bin/sh
# Phase 2 end-to-end smoke test: the full order lifecycle through the API Gateway.
#
#   cd infra && docker run --rm --network delivery -v "$PWD/smoke-test-phase2.sh:/smoke.sh:ro" \
#     alpine:latest sh -c "apk add --no-cache curl jq >/dev/null && sh /smoke.sh"
#
# Exercises the state machine, cross-role authorisation, the outbox -> RabbitMQ -> tracking
# projection path, and the Redis-backed live position read.

set -eu

GW="http://traefik:8100"
KC="http://keycloak:8080/realms/delivery-platform/protocol/openid-connect/token"
KC_ADMIN="http://keycloak:8080"

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
  curl -s -X POST "$KC" -d "client_id=${3:-mobile-app}" \
    -d "username=$1" -d "password=$2" -d "grant_type=password" | jq -r '.access_token'
}

claim_of() {
  p=$(echo "$1" | cut -d. -f2 | tr '_-' '/+')
  case $(( ${#p} % 4 )) in 2) p="$p==" ;; 3) p="$p=" ;; esac
  echo "$p" | base64 -d 2>/dev/null | jq -r "$2"
}

status() { # status <method> <path> <token> [body]
  if [ $# -ge 4 ]; then
    curl -s -o /dev/null -w '%{http_code}' -X "$1" "$GW$2" \
      -H "Authorization: Bearer $3" -H 'Content-Type: application/json' -d "$4"
  else
    curl -s -o /dev/null -w '%{http_code}' -X "$1" "$GW$2" -H "Authorization: Bearer $3"
  fi
}

echo
echo '=== 0. Actors ==================================================================='

CUSTOMER=$(token customer customer mobile-app)
RIDER=$(token rider rider mobile-app)
MERCHANT=$(token merchant merchant delivery-portal)
BACKOFFICE=$(token backoffice backoffice delivery-portal)

MERCHANT_SUB=$(claim_of "$MERCHANT" '.sub')
RIDER_SUB=$(claim_of "$RIDER" '.sub')

for t in CUSTOMER RIDER MERCHANT BACKOFFICE; do
  eval "v=\$$t"
  [ -n "$v" ] && [ "$v" != null ] || { echo "Could not obtain a $t token"; exit 1; }
done
echo "  customer, rider, merchant, backoffice tokens obtained"

# A second rider, to prove one rider cannot touch another's delivery.
ADMIN=$(curl -s -X POST "$KC_ADMIN/realms/master/protocol/openid-connect/token" \
  -d 'client_id=admin-cli' -d 'grant_type=password' -d "username=${KEYCLOAK_ADMIN:-admin}" -d "password=${KEYCLOAK_ADMIN_PASSWORD:-admin}"
  | jq -r '.access_token')
curl -s -o /dev/null -X POST "$KC_ADMIN/admin/realms/delivery-platform/users" \
  -H "Authorization: Bearer $ADMIN" -H 'Content-Type: application/json' \
  -d '{"username":"rider2","email":"rider2@dev.local","firstName":"Robin","lastName":"Rider",
       "enabled":true,"emailVerified":true}' || true
R2_ID=$(curl -s "$KC_ADMIN/admin/realms/delivery-platform/users?username=rider2&exact=true" \
  -H "Authorization: Bearer $ADMIN" | jq -r '.[0].id')
curl -s -o /dev/null -X PUT \
  "$KC_ADMIN/admin/realms/delivery-platform/users/$R2_ID/reset-password" \
  -H "Authorization: Bearer $ADMIN" -H 'Content-Type: application/json' \
  -d '{"type":"password","value":"rider2","temporary":false}'
ROLE=$(curl -s "$KC_ADMIN/admin/realms/delivery-platform/roles/DELIVERY" \
  -H "Authorization: Bearer $ADMIN" | jq -c '{id,name}')
curl -s -o /dev/null -X POST \
  "$KC_ADMIN/admin/realms/delivery-platform/users/$R2_ID/role-mappings/realm" \
  -H "Authorization: Bearer $ADMIN" -H 'Content-Type: application/json' -d "[$ROLE]"
RIDER2=$(token rider2 rider2 mobile-app)
check 'second rider provisioned' 'DELIVERY' \
  "$(claim_of "$RIDER2" '.realm_access.roles[]' | grep -x DELIVERY || echo none)"

echo
echo '=== 1. A published product to order =============================================='

CATS=$(curl -s "$GW/api/categories" -H "Authorization: Bearer $CUSTOMER")
FOOD=$(echo "$CATS" | jq -r '[.[] | select(.name=="Food")][0].id')

PRODUCT=$(curl -s -X POST "$GW/api/products" -H "Authorization: Bearer $MERCHANT" \
  -H 'Content-Type: application/json' \
  -d "{\"name\":\"Phase2 Burger\",\"description\":\"For the lifecycle test\",\"price\":9.75,\"categoryId\":\"$FOOD\"}" \
  | jq -r '.id')

PRESIGN=$(curl -s -X POST "$GW/api/products/$PRODUCT/images/presign" \
  -H "Authorization: Bearer $MERCHANT" -H 'Content-Type: application/json' \
  -d '{"contentType":"image/png"}')
FILE_ID=$(echo "$PRESIGN" | jq -r '.fileId')
UPLOAD_URL=$(echo "$PRESIGN" | jq -r '.uploadUrl')

printf '\211PNG\r\n\032\n\0\0\0\rIHDR\0\0\0\1\0\0\0\1\10\6\0\0\0\37\25\304\211\0\0\0\nIDATx\234c\370\17\0\1\1\1\0\30\335\215\260\0\0\0\0IEND\256B`\202' > /tmp/p.png

# Used EXACTLY as issued: --connect-to redirects the TCP connection to minio:9000 while leaving the
# Host header intact, because SigV4 signs the host (X-Amz-SignedHeaders=host). See the longer note
# in smoke-test.sh — rewriting the URL gives 403 SignatureDoesNotMatch.
UPLOAD_HOSTPORT=$(echo "$UPLOAD_URL" | sed -E 's|^https?://([^/]+)/.*|\1|')
case "$UPLOAD_HOSTPORT" in *:*) : ;; *) UPLOAD_HOSTPORT="$UPLOAD_HOSTPORT:80" ;; esac

check 'presigned PUT accepted' '200' "$(curl -s -o /dev/null -w '%{http_code}' \
  --connect-to "$UPLOAD_HOSTPORT:minio:9000" \
  -X PUT "$UPLOAD_URL" -H 'Content-Type: image/png' --data-binary @/tmp/p.png)"
check 'upload confirmed' '204' "$(status POST "/api/products/$PRODUCT/images/$FILE_ID/confirm" "$MERCHANT")"
check 'product published' '200' "$(status POST "/api/products/$PRODUCT/publish" "$MERCHANT")"

echo
echo '=== 2. Placing an order =========================================================='

ORDER_BODY="{\"items\":[{\"productId\":\"$PRODUCT\",\"qty\":2}],
             \"deliveryAddress\":\"12 Test Street\",\"contactPhone\":\"+100000000\"}"

check 'merchant cannot place an order'  '403' "$(status POST /api/orders "$MERCHANT" "$ORDER_BODY")"
check 'rider cannot place an order'     '403' "$(status POST /api/orders "$RIDER" "$ORDER_BODY")"
check 'empty basket rejected'           '400' "$(status POST /api/orders "$CUSTOMER" '{"items":[],"deliveryAddress":"x"}')"
check 'unknown product rejected'        '422' "$(status POST /api/orders "$CUSTOMER" \
  '{"items":[{"productId":"00000000-0000-4000-8000-000000000000","qty":1}],"deliveryAddress":"x"}')"

CREATED=$(curl -s -X POST "$GW/api/orders" -H "Authorization: Bearer $CUSTOMER" \
  -H 'Content-Type: application/json' -d "$ORDER_BODY")
ORDER=$(echo "$CREATED" | jq -r '.id')

check 'order created in PLACED'         'PLACED'  "$(echo "$CREATED" | jq -r '.status')"
# 2 x 9.75 - proves the price came from the catalog, not the request.
#
# Asserted on `subtotal`, not `totalAmount`. Since the delivery fee became real money the total is
# goods + fee, and the fee is whatever this merchant's shop happens to charge - so the goods figure
# is the one that pins "prices come from the catalog". The relationship between the two is checked
# on the next line, and in infra/smoke-test-fees.js.
check 'subtotal computed from catalog'  '19.50'   "$(echo "$CREATED" | jq -r '.subtotal')"
check 'total is subtotal plus the fee'  'true'    "$(echo "$CREATED" | jq -r '.totalAmount == (.subtotal + .deliveryFee)')"
check 'merchant derived from product'   "$MERCHANT_SUB" "$(echo "$CREATED" | jq -r '.merchantId')"
check 'line snapshots the name'         'Phase2 Burger' "$(echo "$CREATED" | jq -r '.items[0].productName')"

echo
echo '=== 3. Visibility ================================================================'

check 'customer sees own order'         '200' "$(status GET "/api/orders/$ORDER" "$CUSTOMER")"
check 'merchant sees the order'         '200' "$(status GET "/api/orders/$ORDER" "$MERCHANT")"
check 'backoffice sees the order'       '200' "$(status GET "/api/orders/$ORDER" "$BACKOFFICE")"
check 'unrelated rider cannot see it'   '404' "$(status GET "/api/orders/$ORDER" "$RIDER")"
check 'not yet on the rider job board'  '0'   "$(curl -s "$GW/api/orders/available" -H "Authorization: Bearer $RIDER" | jq '[.content[] | select(.id=="'"$ORDER"'")] | length')"

echo
echo '=== 4. State machine ============================================================='

check 'rider cannot accept'             '403' "$(status POST "/api/orders/$ORDER/accept" "$RIDER")"
check 'cannot go straight to ready'     '422' "$(status POST "/api/orders/$ORDER/ready" "$MERCHANT")"
check 'merchant accepts'                '200' "$(status POST "/api/orders/$ORDER/accept" "$MERCHANT")"
check 'cannot accept twice'             '422' "$(status POST "/api/orders/$ORDER/accept" "$MERCHANT")"
check 'customer cannot cancel now'      '422' "$(status POST "/api/orders/$ORDER/cancel" "$CUSTOMER" '{"reason":"changed my mind"}')"
check 'merchant starts preparing'       '200' "$(status POST "/api/orders/$ORDER/prepare" "$MERCHANT")"
check 'merchant marks ready'            '200' "$(status POST "/api/orders/$ORDER/ready" "$MERCHANT")"

echo
echo '=== 5. Rider claim ==============================================================='

check 'now on the rider job board'      '1'   "$(curl -s "$GW/api/orders/available" -H "Authorization: Bearer $RIDER" | jq '[.content[] | select(.id=="'"$ORDER"'")] | length')"
check 'customer cannot claim'           '403' "$(status POST "/api/orders/$ORDER/claim" "$CUSTOMER")"
check 'rider claims it'                 '200' "$(status POST "/api/orders/$ORDER/claim" "$RIDER")"
check 'second rider cannot re-claim'    '422' "$(status POST "/api/orders/$ORDER/claim" "$RIDER2")"
check 'off the job board once claimed'  '0'   "$(curl -s "$GW/api/orders/available" -H "Authorization: Bearer $RIDER2" | jq '[.content[] | select(.id=="'"$ORDER"'")] | length')"
check 'assigned rider now sees it'      '200' "$(status GET "/api/orders/$ORDER" "$RIDER")"
check 'other rider still cannot'        '404' "$(status GET "/api/orders/$ORDER" "$RIDER2")"

echo
echo '=== 6. Tracking (outbox -> bus -> projection) ===================================='

# The projection is built from order.* events off RabbitMQ, so it is eventually consistent.
# Poll rather than sleep-and-hope, and fail loudly if the bus never delivers.
PROJECTED=no
i=0
while [ $i -lt 30 ]; do
  code=$(status POST "/api/tracking/orders/$ORDER/ping" "$RIDER" '{"lat":51.5074,"lng":-0.1278}')
  if [ "$code" = "202" ]; then PROJECTED=yes; break; fi
  i=$((i + 1)); sleep 1
done
check 'order event reached tracking'    'yes' "$PROJECTED"
check 'unassigned rider cannot ping'    '404' "$(status POST "/api/tracking/orders/$ORDER/ping" "$RIDER2" '{"lat":51.5,"lng":-0.1}')"
check 'customer can read position'      '200' "$(status GET "/api/tracking/orders/$ORDER" "$CUSTOMER")"
check 'unrelated rider cannot read it'  '404' "$(status GET "/api/tracking/orders/$ORDER" "$RIDER2")"

POS=$(curl -s "$GW/api/tracking/orders/$ORDER" -H "Authorization: Bearer $CUSTOMER")
check 'position matches the ping'       '51.5074' "$(echo "$POS" | jq -r '.lat')"
check 'position attributed to rider'    "$RIDER_SUB" "$(echo "$POS" | jq -r '.riderId')"

curl -s -o /dev/null -X POST "$GW/api/tracking/orders/$ORDER/ping" -H "Authorization: Bearer $RIDER" \
  -H 'Content-Type: application/json' -d '{"lat":51.5085,"lng":-0.1290}'
check 'history accumulates pings'       '2' "$(curl -s "$GW/api/tracking/orders/$ORDER/history" -H "Authorization: Bearer $CUSTOMER" | jq 'length')"

echo
echo '=== 7. Delivery =================================================================='

check 'other rider cannot pick up'      '404' "$(status POST "/api/orders/$ORDER/pick-up" "$RIDER2")"
check 'rider picks up'                  '200' "$(status POST "/api/orders/$ORDER/pick-up" "$RIDER")"
check 'merchant cannot cancel now'      '422' "$(status POST "/api/orders/$ORDER/cancel" "$MERCHANT" '{"reason":"too late"}')"
check 'rider delivers'                  '200' "$(status POST "/api/orders/$ORDER/deliver" "$RIDER")"

FINAL=$(curl -s "$GW/api/orders/$ORDER" -H "Authorization: Bearer $CUSTOMER")
check 'order is DELIVERED'              'DELIVERED' "$(echo "$FINAL" | jq -r '.status')"
check 'no actions left'                 '0' "$(echo "$FINAL" | jq '.availableActions | length')"
check 'terminal state is terminal'      '422' "$(status POST "/api/orders/$ORDER/deliver" "$RIDER")"
check 'audit trail recorded'            'yes' "$(curl -s "$GW/api/orders/$ORDER/history" -H "Authorization: Bearer $CUSTOMER" | jq 'length >= 6' | sed 's/true/yes/;s/false/no/')"

echo
echo '=== 8. Backoffice ================================================================'

check 'merchant cannot list all orders' '403' "$(status GET /api/orders "$MERCHANT")"
check 'backoffice lists all orders'     '200' "$(status GET /api/orders "$BACKOFFICE")"
STATS=$(curl -s "$GW/api/orders/stats" -H "Authorization: Bearer $BACKOFFICE")
check 'stats count the delivery'        'yes' "$(echo "$STATS" | jq '.countByStatus.DELIVERED >= 1' | sed 's/true/yes/;s/false/no/')"

echo
echo '=== 9. Cancellation path ========================================================='

CANCELLABLE=$(curl -s -X POST "$GW/api/orders" -H "Authorization: Bearer $CUSTOMER" \
  -H 'Content-Type: application/json' -d "$ORDER_BODY" | jq -r '.id')
check 'customer cancels while PLACED'   '200' "$(status POST "/api/orders/$CANCELLABLE/cancel" "$CUSTOMER" '{"reason":"ordered by mistake"}')"
check 'cancelled order is terminal'     '422' "$(status POST "/api/orders/$CANCELLABLE/accept" "$MERCHANT")"

echo
echo '================================================================================='
printf 'passed: %s   failed: %s\n' "$PASS" "$FAIL"
echo '================================================================================='
[ "$FAIL" -eq 0 ] || exit 1
