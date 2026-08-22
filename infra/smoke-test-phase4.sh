#!/bin/sh
# Phase 4 end-to-end smoke test: accounting and Core Banking.
#
#   cd infra && docker run --rm --network delivery -v "$PWD/smoke-test-phase4.sh:/smoke.sh:ro" \
#     alpine:latest sh -c "apk add --no-cache curl jq >/dev/null && sh /smoke.sh"
#
# Runs inside the compose network: the simulator, the connector and the bank's own API are
# deliberately not routed by the Gateway.
#
# The three tests that matter most are the ones about money going missing:
#   * a delivered order settles exactly, and the legs sum to the total
#   * a refused customer debit pays NOBODY (the naive bug: crediting a merchant for money that
#     was never collected)
#   * a refused merchant credit AFTER a successful debit refunds the customer, rather than leaving
#     the platform holding money it cannot distribute
#
# The rest — idempotency, outage recovery, reconciliation reporting — are the supporting cast.

set -eu

GW="http://traefik:8100"
KC="http://keycloak:8080/realms/delivery-platform/protocol/openid-connect/token"
KC_ADMIN="http://keycloak:8080"
BANK="http://corebanking-simulator:8114"
CONNECTOR="http://corebanking-connector:8113"
SETTINGS="http://connector-settings:8109"
BANK_KEY="simulator-dev-key"

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

status() { # status <method> <url> <token> [body]
  if [ $# -ge 4 ]; then
    curl -s -o /dev/null -w '%{http_code}' -X "$1" "$2" \
      -H "Authorization: Bearer $3" -H 'Content-Type: application/json' -d "$4"
  else
    curl -s -o /dev/null -w '%{http_code}' -X "$1" "$2" -H "Authorization: Bearer $3"
  fi
}

bank() { curl -s -H "X-Bank-Api-Key: $BANK_KEY" "$@"; }

balance() {
  bank "$BANK/api/core-banking/accounts/$1" | jq -r '.balanceMinor'
}

wait_for() { # wait_for <seconds> <shell-condition>
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
echo '=== 0. Actors and accounts ======================================================='

CUSTOMER=$(token customer customer mobile-app)
RIDER=$(token rider rider mobile-app)
MERCHANT=$(token merchant merchant merchant-portal)
BACKOFFICE=$(token backoffice backoffice backoffice-web)

for t in CUSTOMER RIDER MERCHANT BACKOFFICE; do
  eval "v=\$$t"
  [ -n "$v" ] && [ "$v" != null ] || { echo "Could not obtain a $t token"; exit 1; }
done
echo "  customer, rider, merchant, backoffice tokens obtained"

ADMIN=$(curl -s -X POST "$KC_ADMIN/realms/master/protocol/openid-connect/token" \
  -d 'client_id=admin-cli' -d 'username=admin' -d 'password=admin' -d 'grant_type=password' \
  | jq -r '.access_token')

# A second merchant whose payout account is FROZEN, so the compensation path can be reached
# without breaking the working merchant for every other test in this file.
provision_merchant() { # provision_merchant <username> <accountRef>
  curl -s -o /dev/null -X POST "$KC_ADMIN/admin/realms/delivery-platform/users" \
    -H "Authorization: Bearer $ADMIN" -H 'Content-Type: application/json' \
    -d "{\"username\":\"$1\",\"email\":\"$1@dev.local\",\"firstName\":\"Test\",\"lastName\":\"Merchant\",
         \"enabled\":true,\"emailVerified\":true,\"attributes\":{\"bankAccountRef\":[\"$2\"]}}" || true
  uid=$(curl -s "$KC_ADMIN/admin/realms/delivery-platform/users?username=$1&exact=true" \
    -H "Authorization: Bearer $ADMIN" | jq -r '.[0].id')
  curl -s -o /dev/null -X PUT "$KC_ADMIN/admin/realms/delivery-platform/users/$uid/reset-password" \
    -H "Authorization: Bearer $ADMIN" -H 'Content-Type: application/json' \
    -d "{\"type\":\"password\",\"value\":\"$1\",\"temporary\":false}"
  # Re-asserted after creation, because on a re-run the create above is a 409 no-op.
  #
  # The FULL representation, not just the attributes. A Keycloak PUT replaces the fields it is
  # given and nulls the ones it is not, and the realm's user profile declares email, firstName and
  # lastName as required — so a partial update leaves the account failing direct grants with
  # "Account is not fully set up", which does not name the missing field.
  curl -s -o /dev/null -X PUT "$KC_ADMIN/admin/realms/delivery-platform/users/$uid" \
    -H "Authorization: Bearer $ADMIN" -H 'Content-Type: application/json' \
    -d "{\"username\":\"$1\",\"email\":\"$1@dev.local\",\"firstName\":\"Test\",\"lastName\":\"Merchant\",
         \"enabled\":true,\"emailVerified\":true,\"attributes\":{\"bankAccountRef\":[\"$2\"]}}"
  role=$(curl -s "$KC_ADMIN/admin/realms/delivery-platform/roles/MERCHANT" \
    -H "Authorization: Bearer $ADMIN" | jq -c '{id,name}')
  curl -s -o /dev/null -X POST \
    "$KC_ADMIN/admin/realms/delivery-platform/users/$uid/role-mappings/realm" \
    -H "Authorization: Bearer $ADMIN" -H 'Content-Type: application/json' -d "[$role]"
}

provision_merchant frozenmerchant ACC-FROZEN
FROZEN_MERCHANT=$(token frozenmerchant frozenmerchant merchant-portal)
check 'frozen-account merchant provisioned' 'yes' \
  "$([ -n "$FROZEN_MERCHANT" ] && [ "$FROZEN_MERCHANT" != null ] && echo yes || echo no)"

echo
echo '=== 1. The bank behaves like a bank =============================================='

check 'accounts are seeded'              '6'   "$(bank "$BANK/api/core-banking/accounts" | jq 'length')"
# Not Keycloak: a real bank will not validate our realm's tokens, and modelling that means the
# connector's auth path is exercised in dev rather than discovered in staging.
check 'no API key is rejected'           '401' \
  "$(curl -s -o /dev/null -w '%{http_code}' "$BANK/api/core-banking/accounts")"
check 'a wrong API key is rejected'      '401' \
  "$(curl -s -o /dev/null -w '%{http_code}' -H 'X-Bank-Api-Key: wrong' "$BANK/api/core-banking/accounts")"
check 'a platform token is not a bank key' '401' \
  "$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $BACKOFFICE" "$BANK/api/core-banking/accounts")"

REF="smoke-$(date +%s)-$$"
FIRST=$(bank -X POST "$BANK/api/core-banking/postings" -H 'Content-Type: application/json' \
  -d "{\"clientReference\":\"$REF\",\"accountRef\":\"ACC-CUSTOMER\",\"direction\":\"DEBIT\",
       \"amountMinor\":1000,\"currency\":\"USD\",\"narrative\":\"smoke\"}")
check 'a posting is accepted'            'POSTED'  "$(echo "$FIRST" | jq -r '.status')"
check 'and is not flagged as a replay'   'false'   "$(echo "$FIRST" | jq -r '.replayed')"

BALANCE_AFTER_FIRST=$(balance ACC-CUSTOMER)

# The single most important behaviour in the simulator, and the reason it is a real service with a
# real unique constraint rather than a mock.
SECOND=$(bank -X POST "$BANK/api/core-banking/postings" -H 'Content-Type: application/json' \
  -d "{\"clientReference\":\"$REF\",\"accountRef\":\"ACC-CUSTOMER\",\"direction\":\"DEBIT\",
       \"amountMinor\":1000,\"currency\":\"USD\",\"narrative\":\"smoke\"}")
check 'the same reference replays'       'true'    "$(echo "$SECOND" | jq -r '.replayed')"
check 'and returns the same posting'     "$(echo "$FIRST" | jq -r '.postingId')" \
  "$(echo "$SECOND" | jq -r '.postingId')"
check 'money moved exactly once'         "$BALANCE_AFTER_FIRST" "$(balance ACC-CUSTOMER)"

# 422 rather than 400: well-formed request, bank says no. The connector reads that as permanent
# and does not burn its retry budget on it.
FROZEN=$(curl -s -o /dev/null -w '%{http_code}' -H "X-Bank-Api-Key: $BANK_KEY" \
  -X POST "$BANK/api/core-banking/postings" -H 'Content-Type: application/json' \
  -d "{\"clientReference\":\"frozen-$REF\",\"accountRef\":\"ACC-FROZEN\",\"direction\":\"CREDIT\",
       \"amountMinor\":100,\"currency\":\"USD\",\"narrative\":\"smoke\"}")
check 'a frozen account is refused 422'  '422' "$FROZEN"

POOR=$(curl -s -o /dev/null -w '%{http_code}' -H "X-Bank-Api-Key: $BANK_KEY" \
  -X POST "$BANK/api/core-banking/postings" -H 'Content-Type: application/json' \
  -d "{\"clientReference\":\"poor-$REF\",\"accountRef\":\"ACC-EMPTY\",\"direction\":\"DEBIT\",
       \"amountMinor\":100,\"currency\":\"USD\",\"narrative\":\"smoke\"}")
check 'insufficient funds refused 422'   '422' "$POOR"

check 'an unknown account is refused'    '422' \
  "$(curl -s -o /dev/null -w '%{http_code}' -H "X-Bank-Api-Key: $BANK_KEY" \
     -X POST "$BANK/api/core-banking/postings" -H 'Content-Type: application/json' \
     -d "{\"clientReference\":\"nobody-$REF\",\"accountRef\":\"ACC-NOPE\",\"direction\":\"CREDIT\",
          \"amountMinor\":100,\"currency\":\"USD\"}")"
# Rejections are recorded, not discarded: "we sent it, they say they never got it" has to be
# answerable from both sides of the wire.
check 'a rejection is still recorded'    'REJECTED' \
  "$(bank "$BANK/api/core-banking/postings/frozen-$REF" | jq -r '.status')"

echo
echo '=== 2. The connector ============================================================='

check 'connector is on the simulator'    'SIMULATOR' \
  "$(curl -s "$CONNECTOR/api/connector/status" | jq -r '.activeProvider')"
check 'both bank clients are deployed'   '2' \
  "$(curl -s "$CONNECTOR/api/connector/status" | jq '.availableProviders | length')"
check 'its breaker starts closed'        'CLOSED' \
  "$(curl -s "$CONNECTOR/api/connector/status" | jq -r '.circuitState')"
check 'settings agree it is SIMULATOR'   'SIMULATOR' \
  "$(curl -s "$SETTINGS/internal/connectors/CORE_BANKING" | jq -r '.provider')"

# Moving money must not be reachable from outside the cluster, and neither must breaking the bank.
check 'no gateway route to the connector' '404' "$(status GET "$GW/api/connector/status" "$BACKOFFICE")"
check 'no gateway route to the bank'      '404' "$(status GET "$GW/api/core-banking/accounts" "$BACKOFFICE")"
check 'no gateway route to fault injection' '404' "$(status GET "$GW/test/faults" "$BACKOFFICE")"

echo
echo '=== 3. A delivered order settles ================================================='

CATS=$(curl -s "$GW/api/categories" -H "Authorization: Bearer $CUSTOMER")
FOOD=$(echo "$CATS" | jq -r '[.[] | select(.name=="Food")][0].id')

# Phase 1 will not publish a product without an image. The presigned URL must be used exactly as
# issued - SigV4 signs the Host - so --connect-to redirects the TCP connection and leaves it intact.
publish_product() { # publish_product <merchant-token> <name> <price>
  pid=$(curl -s -X POST "$GW/api/products" -H "Authorization: Bearer $1" \
    -H 'Content-Type: application/json' \
    -d "{\"name\":\"$2\",\"description\":\"Phase 4\",\"price\":$3,\"categoryId\":\"$FOOD\"}" | jq -r '.id')
  presign=$(curl -s -X POST "$GW/api/products/$pid/images/presign" \
    -H "Authorization: Bearer $1" -H 'Content-Type: application/json' \
    -d '{"contentType":"image/png"}')
  file_id=$(echo "$presign" | jq -r '.fileId')
  url=$(echo "$presign" | jq -r '.uploadUrl')
  hostport=$(echo "$url" | sed -E 's|^https?://([^/]+)/.*|\1|')
  case "$hostport" in *:*) : ;; *) hostport="$hostport:80" ;; esac
  curl -s -o /dev/null --connect-to "$hostport:minio:9000" -X PUT "$url" \
    -H 'Content-Type: image/png' --data-binary @/tmp/p.png
  curl -s -o /dev/null -X POST "$GW/api/products/$pid/images/$file_id/confirm" \
    -H "Authorization: Bearer $1"
  curl -s -o /dev/null -X POST "$GW/api/products/$pid/publish" -H "Authorization: Bearer $1"
  echo "$pid"
}

printf '\211PNG\r\n\032\n\0\0\0\rIHDR\0\0\0\1\0\0\0\1\10\6\0\0\0\37\25\304\211\0\0\0\nIDATx\234c\370\17\0\1\1\1\0\30\335\215\260\0\0\0\0IEND\256B`\202' > /tmp/p.png

deliver_order() { # deliver_order <merchant-token> <product-id> -> order id
  oid=$(curl -s -X POST "$GW/api/orders" -H "Authorization: Bearer $CUSTOMER" \
    -H 'Content-Type: application/json' \
    -d "{\"items\":[{\"productId\":\"$2\",\"qty\":1}],\"deliveryAddress\":\"1 Ledger Lane\",
         \"contactPhone\":\"+15550100001\"}" | jq -r '.id')
  for step in accept prepare ready; do
    curl -s -o /dev/null -X POST "$GW/api/orders/$oid/$step" -H "Authorization: Bearer $1"
  done
  curl -s -o /dev/null -X POST "$GW/api/orders/$oid/claim" -H "Authorization: Bearer $RIDER"
  curl -s -o /dev/null -X POST "$GW/api/orders/$oid/pick-up" -H "Authorization: Bearer $RIDER"
  curl -s -o /dev/null -X POST "$GW/api/orders/$oid/deliver" -H "Authorization: Bearer $RIDER"
  echo "$oid"
}

CUSTOMER_BEFORE=$(balance ACC-CUSTOMER)
MERCHANT_BEFORE=$(balance ACC-MERCHANT)
PLATFORM_BEFORE=$(balance ACC-PLATFORM)

PRODUCT=$(publish_product "$MERCHANT" "Phase4 Ledger Lunch" 40.00)
ORDER=$(deliver_order "$MERCHANT" "$PRODUCT")
check 'order delivered'                  'yes' \
  "$([ -n "$ORDER" ] && [ "$ORDER" != null ] && echo yes || echo no)"

LEGS_URL="$GW/api/accounting/orders/$ORDER"
wait_for 60 "[ \"\$(curl -s '$LEGS_URL' -H 'Authorization: Bearer $BACKOFFICE' | jq '[.[]|select(.status==\"POSTED\")]|length')\" = 3 ]" || true
LEGS=$(curl -s "$LEGS_URL" -H "Authorization: Bearer $BACKOFFICE")

check 'three settlement legs created'    '3' "$(echo "$LEGS" | jq 'length')"
check 'all three posted'                 '3' "$(echo "$LEGS" | jq '[.[]|select(.status=="POSTED")]|length')"
# The delivery fee is real money now, so the figures are derived from the order rather than
# hardcoded — they depend on what this merchant's shop charges to deliver.
ORDER_JSON=$(curl -s "$GW/api/orders/$ORDER" -H "Authorization: Bearer $BACKOFFICE")
SUBTOTAL=$(echo "$ORDER_JSON" | jq -r '.subtotal')
FEE=$(echo "$ORDER_JSON" | jq -r '.deliveryFee')
TOTAL=$(echo "$ORDER_JSON" | jq -r '.totalAmount')

check 'goods are the catalog price'      '40.00' "$SUBTOTAL"
check 'customer was debited the total'   "$TOTAL" \
  "$(echo "$LEGS" | jq -r '[.[]|select(.leg=="CUSTOMER_DEBIT")][0].amount')"
# Commission is 12.5% of the GOODS, not of the total. The delivery fee is not the shop's revenue,
# so no commission is taken on it and the shop is not credited it.
check 'merchant is paid goods less commission' '35.00' \
  "$(echo "$LEGS" | jq -r '[.[]|select(.leg=="MERCHANT_CREDIT")][0].amount')"
# The platform leg is everything the customer paid that the shop does not get: commission + fee.
check 'platform keeps commission plus fee' 'yes' \
  "$(echo "$LEGS" | jq -r --argjson fee "$FEE" \
     '(([.[]|select(.leg=="PLATFORM_COMMISSION")][0].amount|tonumber) - $fee - 5.00 | fabs) < 0.005' \
     | sed 's/true/yes/;s/false/no/')"
check 'the credits sum to the debit'     'yes' \
  "$(echo "$LEGS" | jq '([.[]|select(.direction=="CREDIT")|.amount|tonumber]|add)
                        == ([.[]|select(.direction=="DEBIT")|.amount|tonumber]|add)' \
     | sed 's/true/yes/;s/false/no/')"
check 'every leg has a bank reference'   '0' \
  "$(echo "$LEGS" | jq '[.[]|select(.coreBankingRef==null)]|length')"

echo
echo '=== 4. The money actually moved =================================================='

# Balances are in minor units. The customer pays the total, the merchant gets goods less
# commission, and the platform keeps the difference — so the fee shows up on the platform side.
TOTAL_MINOR=$(echo "$TOTAL" | awk '{printf "%d", ($1*100)+0.5}')
FEE_MINOR=$(echo "$FEE" | awk '{printf "%d", ($1*100)+0.5}')
check 'customer balance fell by the total' "$((CUSTOMER_BEFORE - TOTAL_MINOR))" "$(balance ACC-CUSTOMER)"
check 'merchant balance rose by 3500'      "$((MERCHANT_BEFORE + 3500))" "$(balance ACC-MERCHANT)"
check 'platform balance rose by 500 + fee' "$((PLATFORM_BEFORE + 500 + FEE_MINOR))" "$(balance ACC-PLATFORM)"

echo
echo '=== 5. Settling twice is not possible ============================================'

# order.delivered can be redelivered by the bus. Settling twice would really move money twice, so
# this is guarded by a unique constraint on (order_id, leg), not just by a check in code.
CUSTOMER_MID=$(balance ACC-CUSTOMER)
RMQ="-u ${RABBITMQ_USER:-delivery}:${RABBITMQ_PASSWORD:-delivery}"
SNAPSHOT=$(curl -s "$GW/api/orders/$ORDER" -H "Authorization: Bearer $BACKOFFICE")
REPLAY=$(jq -n --arg rk 'order.delivered' --arg p "$SNAPSHOT" \
  '{properties:{content_type:"application/json",headers:{eventType:"order.delivered"}},
    routing_key:$rk,payload:$p,payload_encoding:"string"}')

# shellcheck disable=SC2086
check 'a duplicate event is accepted by the broker' 'true' \
  "$(curl -s $RMQ -H 'Content-Type: application/json' \
     -X POST "http://rabbitmq:15672/api/exchanges/%2F/delivery.events/publish" -d "$REPLAY" \
     | jq -r '.routed')"
sleep 10
check 'still exactly three legs'         '3' \
  "$(curl -s "$LEGS_URL" -H "Authorization: Bearer $BACKOFFICE" | jq 'length')"
check 'and no extra money moved'         "$CUSTOMER_MID" "$(balance ACC-CUSTOMER)"

echo
echo '=== 6. A refused credit refunds the customer ====================================='

# The compensation path. A merchant whose payout account is frozen: the customer debit succeeds,
# the merchant credit is permanently refused, and the platform is left holding money it cannot
# distribute. Leaving it there silently is the worst outcome available, so it must refund.
FROZEN_PRODUCT=$(publish_product "$FROZEN_MERCHANT" "Phase4 Frozen Feast" 20.00)
CUSTOMER_BEFORE_FROZEN=$(balance ACC-CUSTOMER)
FROZEN_ORDER=$(deliver_order "$FROZEN_MERCHANT" "$FROZEN_PRODUCT")

FROZEN_LEGS_URL="$GW/api/accounting/orders/$FROZEN_ORDER"
wait_for 90 "curl -s '$FROZEN_LEGS_URL' -H 'Authorization: Bearer $BACKOFFICE' | jq -e '[.[]|select(.leg==\"CUSTOMER_REFUND\" and .status==\"POSTED\")]|length>0'" || true
FROZEN_LEGS=$(curl -s "$FROZEN_LEGS_URL" -H "Authorization: Bearer $BACKOFFICE")

check 'the customer debit posted'        'COMPENSATED' \
  "$(echo "$FROZEN_LEGS" | jq -r '[.[]|select(.leg=="CUSTOMER_DEBIT")][0].status')"
check 'the merchant credit failed'       'FAILED' \
  "$(echo "$FROZEN_LEGS" | jq -r '[.[]|select(.leg=="MERCHANT_CREDIT")][0].status')"
check 'and names why'                    'yes' \
  "$(echo "$FROZEN_LEGS" | jq '[.[]|select(.leg=="MERCHANT_CREDIT" and (.failureReason|test("FROZEN")))]|length>0' \
     | sed 's/true/yes/;s/false/no/')"
# One refund, not one per failed credit.
check 'exactly one refund was raised'    '1' \
  "$(echo "$FROZEN_LEGS" | jq '[.[]|select(.leg=="CUSTOMER_REFUND")]|length')"
check 'the refund posted'                'POSTED' \
  "$(echo "$FROZEN_LEGS" | jq -r '[.[]|select(.leg=="CUSTOMER_REFUND")][0].status')"
check 'the commission was abandoned'     'ABANDONED' \
  "$(echo "$FROZEN_LEGS" | jq -r '[.[]|select(.leg=="PLATFORM_COMMISSION")][0].status')"
# The whole point: the customer is square again.
check 'the customer is made whole'       "$CUSTOMER_BEFORE_FROZEN" "$(balance ACC-CUSTOMER)"

echo
echo '=== 7. A bank outage delays, it does not lose ===================================='

# The connector is still retrying, so the leg must stay PENDING. Treating a slow bank as a failed
# one would compensate a settlement that was about to succeed.
curl -s -o /dev/null -X POST "$BANK/test/faults" -H 'Content-Type: application/json' \
  -d '{"mode":"UNAVAILABLE","latencyMs":0,"callCount":3}'
check 'the bank is now unavailable'      'UNAVAILABLE' "$(curl -s "$BANK/test/faults" | jq -r '.mode')"

OUTAGE_PRODUCT=$(publish_product "$MERCHANT" "Phase4 Outage Order" 10.00)
OUTAGE_ORDER=$(deliver_order "$MERCHANT" "$OUTAGE_PRODUCT")

OUTAGE_URL="$GW/api/accounting/orders/$OUTAGE_ORDER"
# The fault expires after 3 calls, so the connector's own retry should carry it through.
wait_for 90 "[ \"\$(curl -s '$OUTAGE_URL' -H 'Authorization: Bearer $BACKOFFICE' | jq '[.[]|select(.status==\"POSTED\")]|length')\" = 3 ]" || true
OUTAGE_LEGS=$(curl -s "$OUTAGE_URL" -H "Authorization: Bearer $BACKOFFICE")

check 'the settlement survived the outage' '3' \
  "$(echo "$OUTAGE_LEGS" | jq '[.[]|select(.status=="POSTED")]|length')"
check 'nothing was abandoned'            '0' \
  "$(echo "$OUTAGE_LEGS" | jq '[.[]|select(.status=="ABANDONED" or .status=="FAILED")]|length')"
# The outage really happened: the injected fault was consumed by real calls and expired itself.
# Note the retries are NOT visible in the transaction's attempt count - the connector absorbs them
# inside one dispatch and reports a single outcome, so the saga only ever sees the final answer.
check 'the injected fault was consumed'  'HEALTHY' "$(curl -s "$BANK/test/faults" | jq -r '.mode')"

curl -s -o /dev/null -X POST "$BANK/test/faults" -H 'Content-Type: application/json' \
  -d '{"mode":"HEALTHY","latencyMs":0,"callCount":0}'
check 'the bank is healthy again'        'HEALTHY' "$(curl -s "$BANK/test/faults" | jq -r '.mode')"

echo
echo '=== 8. Reconciliation ============================================================'

check 'customer cannot read the ledger'  '403' "$(status GET "$GW/api/accounting/summary" "$CUSTOMER")"
check 'merchant cannot read the ledger'  '403' "$(status GET "$GW/api/accounting/summary" "$MERCHANT")"
check 'anonymous cannot read the ledger' '401' \
  "$(curl -s -o /dev/null -w '%{http_code}' "$GW/api/accounting/summary")"
check 'backoffice can'                   '200' "$(status GET "$GW/api/accounting/summary" "$BACKOFFICE")"

SUMMARY=$(curl -s "$GW/api/accounting/summary" -H "Authorization: Bearer $BACKOFFICE")
check 'the summary counts posted legs'   'yes' \
  "$(echo "$SUMMARY" | jq '.byStatus.POSTED.count >= 7' | sed 's/true/yes/;s/false/no/')"
check 'it reports amount at risk'        'yes' \
  "$(echo "$SUMMARY" | jq 'has("amountAtRisk")' | sed 's/true/yes/;s/false/no/')"
# Asserted for internal consistency rather than against a fixed number: this file deliberately
# creates failures, and rows from a previous run persist, so any absolute count would be wrong the
# second time it runs.
check 'unsettled = pending + failed'     'yes' \
  "$(echo "$SUMMARY" | jq '.unsettledCount ==
        ((.byStatus.PENDING.count // 0) + (.byStatus.FAILED.count // 0))' \
     | sed 's/true/yes/;s/false/no/')"
check 'amount at risk is non-negative'   'yes' \
  "$(echo "$SUMMARY" | jq '.amountAtRisk >= 0' | sed 's/true/yes/;s/false/no/')"

check 'the failed credit is findable'    'yes' \
  "$(curl -s "$GW/api/accounting/transactions?status=FAILED" -H "Authorization: Bearer $BACKOFFICE" \
     | jq '[.[]|select(.leg=="MERCHANT_CREDIT")]|length>0' | sed 's/true/yes/;s/false/no/')"

# The end of the trail: after "it says FAILED", this is the only thing that answers why.
FAILED_ID=$(echo "$FROZEN_LEGS" | jq -r '[.[]|select(.leg=="MERCHANT_CREDIT")][0].id')
SYNC=$(curl -s "$GW/api/accounting/transactions/$FAILED_ID/sync-log" -H "Authorization: Bearer $BACKOFFICE")
check 'the sync log recorded the attempt' 'yes' \
  "$(echo "$SYNC" | jq 'length>0' | sed 's/true/yes/;s/false/no/')"
check 'it kept what we sent'             'yes' \
  "$(echo "$SYNC" | jq '[.[]|select(.requestPayload|tostring|contains("ACC-FROZEN"))]|length>0' \
     | sed 's/true/yes/;s/false/no/')"
check 'and what came back'               'yes' \
  "$(echo "$SYNC" | jq '[.[]|select(.responsePayload != null)]|length>0' | sed 's/true/yes/;s/false/no/')"
check 'the outcome is a rejection'       'REJECTED' "$(echo "$SYNC" | jq -r '.[0].outcome')"

echo
echo '=== 9. Switching the bank is a Backoffice change ================================='

check 'CORE_BANKING offers both modes'   '2' \
  "$(curl -s "$GW/api/settings/connectors/CORE_BANKING" -H "Authorization: Bearer $BACKOFFICE" \
     | jq '.availableProviders | length')"
check 'backoffice switches to REAL'      '200' \
  "$(status PUT "$GW/api/settings/connectors/CORE_BANKING" "$BACKOFFICE" \
     '{"provider":"REAL","config":{"baseUrl":"https://bank.example.test"}}')"
wait_for 20 "[ \"\$(curl -s $CONNECTOR/api/connector/status | jq -r '.activeProvider')\" = REAL ]" || true
check 'the connector switched live'      'REAL' \
  "$(curl -s "$CONNECTOR/api/connector/status" | jq -r '.activeProvider')"

# RealBankClient refuses rather than guessing at a contract that does not exist yet. A settlement
# attempted now must fail loudly and be visible, not vanish.
REAL_PRODUCT=$(publish_product "$MERCHANT" "Phase4 Real Bank" 15.00)
REAL_ORDER=$(deliver_order "$MERCHANT" "$REAL_PRODUCT")
REAL_URL="$GW/api/accounting/orders/$REAL_ORDER"
wait_for 60 "curl -s '$REAL_URL' -H 'Authorization: Bearer $BACKOFFICE' | jq -e '[.[]|select(.status==\"FAILED\")]|length>0'" || true

check 'the unimplemented bank refuses'   'yes' \
  "$(curl -s "$REAL_URL" -H "Authorization: Bearer $BACKOFFICE" \
     | jq '[.[]|select(.leg=="CUSTOMER_DEBIT" and .status=="FAILED")]|length>0' \
     | sed 's/true/yes/;s/false/no/')"
check 'and says what is missing'         'yes' \
  "$(curl -s "$REAL_URL" -H "Authorization: Bearer $BACKOFFICE" \
     | jq '[.[]|select(.failureReason != null and (.failureReason|test("not implemented")))]|length>0' \
     | sed 's/true/yes/;s/false/no/')"
# The bug this guards against: crediting a merchant for money that was never collected.
check 'nobody was paid for it'           '0' \
  "$(curl -s "$REAL_URL" -H "Authorization: Bearer $BACKOFFICE" \
     | jq '[.[]|select(.direction=="CREDIT" and .status=="POSTED")]|length')"
check 'the credits were abandoned'       'yes' \
  "$(curl -s "$REAL_URL" -H "Authorization: Bearer $BACKOFFICE" \
     | jq '[.[]|select(.direction=="CREDIT" and .status=="ABANDONED")]|length >= 1' \
     | sed 's/true/yes/;s/false/no/')"

curl -s -o /dev/null -X PUT "$GW/api/settings/connectors/CORE_BANKING" \
  -H "Authorization: Bearer $BACKOFFICE" -H 'Content-Type: application/json' \
  -d '{"provider":"SIMULATOR","config":{"baseUrl":"http://corebanking-simulator:8114"}}'
wait_for 20 "[ \"\$(curl -s $CONNECTOR/api/connector/status | jq -r '.activeProvider')\" = SIMULATOR ]" || true
check 'switched back to the simulator'   'SIMULATOR' \
  "$(curl -s "$CONNECTOR/api/connector/status" | jq -r '.activeProvider')"
check 'the switch is audited'            'yes' \
  "$(curl -s "$GW/api/settings/connectors/CORE_BANKING/history" -H "Authorization: Bearer $BACKOFFICE" \
     | jq 'length >= 2' | sed 's/true/yes/;s/false/no/')"

echo
echo '=== 10. Queues and dead letters =================================================='

for q in accounting.order-events accounting.posting-results accounting.posting.requested accounting.dlq; do
  # shellcheck disable=SC2086
  check "queue $q declared" '200' \
    "$(curl -s -o /dev/null -w '%{http_code}' $RMQ "http://rabbitmq:15672/api/queues/%2F/$q")"
done
# Separate from notification.dlq: a stuck settlement and a stuck SMS need different people.
# shellcheck disable=SC2086
check 'the notification DLQ is separate' '200' \
  "$(curl -s -o /dev/null -w '%{http_code}' $RMQ "http://rabbitmq:15672/api/queues/%2F/notification.dlq")"

echo
echo '================================================================================='
printf 'passed: %s   failed: %s\n' "$PASS" "$FAIL"
echo '================================================================================='
[ "$FAIL" -eq 0 ] || exit 1
