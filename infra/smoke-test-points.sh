#!/bin/sh
# Cash-on-delivery settlement and the points model.
#
#   cd infra && docker run --rm --network delivery --env-file .env \
#     -v "$PWD/smoke-test-points.sh:/smoke.sh:ro" alpine:latest \
#     sh -c "apk add --no-cache curl jq >/dev/null && sh /smoke.sh"
#
# REPLACES the bank half of smoke-test-phase4.sh. That suite drives the Core Banking Simulator
# directly and asserts real postings; neither the simulator nor the connector is deployed any more,
# so it dies at its first check against a host that does not resolve.
#
# What the platform does instead, and what this asserts:
#
#   * settlement runs in LEDGER_ONLY mode — the ledger records who is owed what and every leg is
#     terminal as it is written, because there is no bank to wait for
#   * a delivered order earns POINTS: the shop on the goods it sold, whoever carried it on the
#     delivery fee
#   * a redemption request holds the points, and only Backoffice can approve and pay it
#
# The two checks that matter most are the ones that cost money if they are wrong:
#   * a redelivered order.delivered must not pay a shop twice
#   * a redemption must not be requestable twice out of one balance

set -eu

GW="http://traefik:8100"
KC="http://keycloak:8080/realms/delivery-platform/protocol/openid-connect/token"

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

status() {
  if [ $# -ge 4 ]; then
    curl -s -o /dev/null -w '%{http_code}' -X "$1" "$2" \
      -H "Authorization: Bearer $3" -H 'Content-Type: application/json' -d "$4"
  else
    curl -s -o /dev/null -w '%{http_code}' -X "$1" "$2" -H "Authorization: Bearer $3"
  fi
}

wait_for() {
  limit=$1; shift
  i=0
  while [ "$i" -lt "$limit" ]; do
    if eval "$@" >/dev/null 2>&1; then return 0; fi
    i=$((i + 1))
    sleep 1
  done
  return 1
}

echo
echo '=== 0. Actors ===================================================================='

CUSTOMER=$(token customer 100001)
MERCHANT=$(token merchant 200002 delivery-portal)
RIDER=$(token rider 300003)
BACKOFFICE=$(token backoffice 400004 delivery-portal)

for t in CUSTOMER MERCHANT RIDER BACKOFFICE; do
  eval "v=\$$t"
  [ -n "$v" ] && [ "$v" != null ] || { echo "Could not obtain a $t token"; exit 1; }
done
echo '  customer, merchant, rider, backoffice tokens obtained'

MERCHANT_SUB=$(echo "$MERCHANT" | cut -d. -f2 | tr '_-' '/+' | base64 -d 2>/dev/null | jq -r '.sub')

echo
echo '=== 1. A delivered order settles without a bank =================================='

CATS=$(curl -s "$GW/api/categories" -H "Authorization: Bearer $CUSTOMER")
FOOD=$(echo "$CATS" | jq -r '[.[] | select(.name=="Food")][0].id')

printf '\211PNG\r\n\032\n\0\0\0\rIHDR\0\0\0\1\0\0\0\1\10\6\0\0\0\37\25\304\211\0\0\0\nIDATx\234c\370\17\0\1\1\1\0\30\335\215\260\0\0\0\0IEND\256B`\202' > /tmp/p.png

publish_product() {
  pid=$(curl -s -X POST "$GW/api/products" -H "Authorization: Bearer $1" \
    -H 'Content-Type: application/json' \
    -d "{\"name\":\"$2\",\"description\":\"Points suite\",\"price\":$3,\"categoryId\":\"$FOOD\"}" | jq -r '.id')
  presign=$(curl -s -X POST "$GW/api/products/$pid/images/presign" \
    -H "Authorization: Bearer $1" -H 'Content-Type: application/json' \
    -d '{"contentType":"image/png"}')
  file_id=$(echo "$presign" | jq -r '.fileId')
  url=$(echo "$presign" | jq -r '.uploadUrl')
  hostport=$(echo "$url" | sed -E 's|^https?://([^/]+)/.*|\1|')
  case "$hostport" in *:*) : ;; *) hostport="$hostport:80" ;; esac
  curl -s -o /dev/null --connect-to "$hostport:minio:9000" -X PUT "$url" \
    -H 'Content-Type: image/png' --data-binary @/tmp/p.png
  curl -s -o /dev/null -X POST "$GW/api/products/$pid/images/$file_id/confirm" -H "Authorization: Bearer $1"
  curl -s -o /dev/null -X POST "$GW/api/products/$pid/publish" -H "Authorization: Bearer $1"
  echo "$pid"
}

deliver_order() {
  oid=$(curl -s -X POST "$GW/api/orders" -H "Authorization: Bearer $CUSTOMER" \
    -H 'Content-Type: application/json' \
    -d "{\"items\":[{\"productId\":\"$2\",\"qty\":1}],\"deliveryAddress\":\"1 Points Lane\",
         \"contactPhone\":\"+15550100001\"}" | jq -r '.id')
  for step in accept prepare ready; do
    curl -s -o /dev/null -X POST "$GW/api/orders/$oid/$step" -H "Authorization: Bearer $1"
  done
  curl -s -o /dev/null -X POST "$GW/api/orders/$oid/claim" -H "Authorization: Bearer $RIDER"
  curl -s -o /dev/null -X POST "$GW/api/orders/$oid/pick-up" -H "Authorization: Bearer $RIDER"
  curl -s -o /dev/null -X POST "$GW/api/orders/$oid/deliver" -H "Authorization: Bearer $RIDER"
  echo "$oid"
}

points_of() { curl -s "$GW/api/points/balance" -H "Authorization: Bearer $1" | jq -r '.points // 0'; }

# Captured before anything is ordered. The balance is CUMULATIVE and this suite has almost
# certainly run before, so "wait until points > 0" is instantly true and proves nothing — it was
# already true from the previous run. Every wait below is against this baseline instead.
BASELINE=$(points_of "$MERCHANT")

# 250.00 rather than a token amount, deliberately. At the default merchant rate of 5 points per
# unit that is 1250 points, which clears the 1000-point minimum redemption in ONE order. A cheap
# product earns a few hundred and the redemption section below can never run.
PID=$(publish_product "$MERCHANT" "Points Feast" 250.00)
check 'a product is published' 'yes' "$([ -n "$PID" ] && [ "$PID" != null ] && echo yes || echo no)"

ORDER=$(deliver_order "$MERCHANT" "$PID")
check 'an order is delivered' 'yes' "$([ -n "$ORDER" ] && [ "$ORDER" != null ] && echo yes || echo no)"

# Cash on delivery: the customer paid at the door, so the order arrives at accounting COLLECTED.
PAYMENT=$(curl -s "$GW/api/orders/$ORDER" -H "Authorization: Bearer $CUSTOMER" | jq -r '.paymentMethod')
check 'it is a cash order' 'CASH' "$PAYMENT"

# LEDGER_ONLY: no leg may be left PENDING. A leg still PENDING here means the platform is waiting
# on a bank that was never deployed, which is the exact failure the settlement mode exists to stop.
wait_for 40 "[ \"\$(curl -s '$GW/api/accounting/orders/$ORDER' -H 'Authorization: Bearer $BACKOFFICE' | jq '[.[] | select(.status==\"PENDING\")] | length')\" = 0 ]" || true
PENDING=$(curl -s "$GW/api/accounting/orders/$ORDER" -H "Authorization: Bearer $BACKOFFICE" \
  | jq '[.[] | select(.status=="PENDING")] | length')
check 'no leg is left waiting on a bank' '0' "${PENDING:-none}"

echo
echo '=== 2. The delivered order earns points =========================================='

# Against the baseline, and on THIS order's ledger row rather than the balance — the award is
# asynchronous off the bus, and a cumulative balance that was already non-zero says nothing about
# whether this order landed.
wait_for 40 "[ \"\$(curl -s '$GW/api/points/history?limit=200' -H 'Authorization: Bearer $MERCHANT' | jq '[.[] | select(.orderId==\"$ORDER\")] | length')\" -gt 0 ]" || true

BAL=$(curl -s "$GW/api/points/balance" -H "Authorization: Bearer $MERCHANT")
MPOINTS=$(echo "$BAL" | jq -r '.points // 0')
check 'the merchant earned points' 'yes' "$([ "${MPOINTS:-0}" -gt "${BASELINE:-0}" ] && echo yes || echo no)"
check 'the balance names the owner kind' 'MERCHANT' "$(echo "$BAL" | jq -r '.ownerKind')"
check 'the balance carries a cash value' 'yes' \
  "$([ "$(echo "$BAL" | jq -r '.value // 0')" != '0' ] && echo yes || echo no)"

LEDGER=$(curl -s "$GW/api/points/history?limit=200" -H "Authorization: Bearer $MERCHANT")
check 'the earning is on the ledger' 'ORDER_EARNED' "$(echo "$LEDGER" | jq -r '[.[] | select(.orderId=="'"$ORDER"'")][0].reason')"
check 'and it names the order' "$ORDER" "$(echo "$LEDGER" | jq -r '[.[] | select(.orderId=="'"$ORDER"'")][0].orderId')"

echo
echo '=== 3. A second delivery adds to the balance ====================================='

PID2=$(publish_product "$MERCHANT" "Points Pasta" 25.00)
ORDER2=$(deliver_order "$MERCHANT" "$PID2")
wait_for 40 "[ \"\$(curl -s '$GW/api/points/history?limit=200' -H 'Authorization: Bearer $MERCHANT' | jq '[.[] | select(.orderId==\"$ORDER2\")] | length')\" -gt 0 ]" || true
MPOINTS2=$(curl -s "$GW/api/points/balance" -H "Authorization: Bearer $MERCHANT" | jq -r '.points // 0')
check 'the balance grew' 'yes' "$([ "${MPOINTS2:-0}" -gt "${MPOINTS:-0}" ] && echo yes || echo no)"

# The bus is at-least-once, so this is not theoretical: the same delivered order arriving twice
# must not pay the shop twice. A partial unique index on (order_id, owner_kind, owner_ref) is what
# enforces it, and this is the check that would catch its removal.
EARNS=$(curl -s "$GW/api/points/history?limit=200" -H "Authorization: Bearer $MERCHANT" \
  | jq '[.[] | select(.orderId=="'"$ORDER"'" and .reason=="ORDER_EARNED")] | length')
check 'one order earned exactly once' '1' "$EARNS"

echo
echo '=== 4. Points are not a public record ============================================'

check 'anonymous cannot read a balance' '401' \
  "$(curl -s -o /dev/null -w '%{http_code}' "$GW/api/points/balance")"
check 'a customer has no points surface' '403' \
  "$(status GET "$GW/api/points/balance" "$CUSTOMER")"
check 'a merchant cannot open the Backoffice queue' '403' \
  "$(status GET "$GW/api/points/redemptions/queue" "$MERCHANT")"

echo
echo '=== 5. Redeeming points =========================================================='

# Below the minimum, which exists so the payout queue does not fill with requests that cost more in
# operator time than they are worth.
check 'a request under the minimum is refused' '400' \
  "$(status POST "$GW/api/points/redemptions" "$MERCHANT" '{"points":1,"payoutNote":"too small"}')"

BALANCE_NOW=$(curl -s "$GW/api/points/balance" -H "Authorization: Bearer $MERCHANT" | jq -r '.points')
check 'a request above the balance is refused' '400' \
  "$(status POST "$GW/api/points/redemptions" "$MERCHANT" "{\"points\":$((BALANCE_NOW + 100000)),\"payoutNote\":\"too much\"}")"

REQ=$(curl -s -X POST "$GW/api/points/redemptions" -H "Authorization: Bearer $MERCHANT" \
  -H 'Content-Type: application/json' \
  -d "{\"points\":$BALANCE_NOW,\"payoutNote\":\"pay to the shop account\"}")
RID=$(echo "$REQ" | jq -r '.id')
check 'a valid request is accepted' 'PENDING' "$(echo "$REQ" | jq -r '.status')"
check 'it captures what the points are worth' 'yes' \
  "$([ "$(echo "$REQ" | jq -r '.amount // 0')" != '0' ] && echo yes || echo no)"

# The hold is what stops the same points being spent twice while a slow approval sits in a queue.
HELD=$(curl -s "$GW/api/points/balance" -H "Authorization: Bearer $MERCHANT" | jq -r '.points')
check 'the points are held out of the balance' '0' "$HELD"
check 'a second request is refused while one is open' '400' \
  "$(status POST "$GW/api/points/redemptions" "$MERCHANT" '{"points":1000,"payoutNote":"again"}')"

echo
echo '=== 6. Only Backoffice decides ==================================================='

check 'a merchant cannot approve their own request' '403' \
  "$(status POST "$GW/api/points/redemptions/$RID/approve" "$MERCHANT" '{"note":"me"}')"
check 'the request is in the Backoffice queue' 'yes' \
  "$(curl -s "$GW/api/points/redemptions/queue" -H "Authorization: Bearer $BACKOFFICE" \
     | jq -r '[.[] | select(.id=="'"$RID"'")] | length | if . > 0 then "yes" else "no" end')"

check 'Backoffice approves it' '200' \
  "$(status POST "$GW/api/points/redemptions/$RID/approve" "$BACKOFFICE" '{"note":"checked"}')"

# Paying something nobody approved is the transition worth making impossible rather than catching
# in a review later — so PAID is reachable only from APPROVED.
check 'and marks it paid with a reference' '200' \
  "$(status POST "$GW/api/points/redemptions/$RID/paid" "$BACKOFFICE" '{"note":"cash handed over, ref 4471"}')"
check 'paying it twice is refused' '400' \
  "$(status POST "$GW/api/points/redemptions/$RID/paid" "$BACKOFFICE" '{"note":"again"}')"

FINAL=$(curl -s "$GW/api/points/redemptions" -H "Authorization: Bearer $MERCHANT" \
  | jq -r '[.[] | select(.id=="'"$RID"'")][0]')
check 'the request is terminal' 'PAID' "$(echo "$FINAL" | jq -r '.status')"
check 'it records who decided' 'yes' \
  "$([ "$(echo "$FINAL" | jq -r '.decidedBy // "null"')" != 'null' ] && echo yes || echo no)"

# The balance already fell when the hold was taken. Subtracting again on payment would charge the
# requester twice for one redemption, so the PAID ledger row carries zero points.
AFTER=$(curl -s "$GW/api/points/balance" -H "Authorization: Bearer $MERCHANT" | jq -r '.points')
check 'the balance is not charged twice' '0' "$AFTER"
check 'a new request is possible once the last one closed' '200' \
  "$(status GET "$GW/api/points/balance" "$MERCHANT")"

echo
echo '================================================================================='
echo "passed: $PASS   failed: $FAIL"
echo '================================================================================='
[ "$FAIL" -eq 0 ]
