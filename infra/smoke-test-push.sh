#!/bin/sh
# Every push the platform sends, driven through one real order.
#
# The other suites check that an order can be placed and delivered. This one checks that each step
# of doing so reaches the right person: five templates, five audiences, one lifecycle.
#
# It asserts on the notification log rather than on a handset, and that is a real limit worth
# stating plainly: the log records what the provider ACCEPTED, not what a phone displayed. With the
# dev provider that is all there is. With Firebase configured, a row reaching SENT means Google took
# the message. Neither proves a notification appeared on a screen.
set -eu

GW="http://traefik:8100"
KC="http://keycloak:8080/realms/delivery-platform/protocol/openid-connect/token"
PUSH_CONNECTOR="http://push-connector:8111"
# Per order, which is how Notifications Manager exposes it.
LOG_URL="$GW/api/notification-log/orders"

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
    curl -s -o /dev/null -w '%{http_code}' -X "$1" "$GW$2" \
      -H "Authorization: Bearer $3" -H 'Content-Type: application/json' -d "$4"
  else
    curl -s -o /dev/null -w '%{http_code}' -X "$1" "$GW$2" -H "Authorization: Bearer $3"
  fi
}

wait_for() { # wait_for <seconds> <shell test>
  n=0
  while [ "$n" -lt "$1" ]; do
    if eval "$2" >/dev/null 2>&1; then return 0; fi
    n=$((n + 1))
    sleep 1
  done
  return 1
}

# How many pushes one order produced for one template.
pushes_for() { # pushes_for <orderId> <eventType>
  curl -s "$LOG_URL/$1" -H "Authorization: Bearer $BACKOFFICE" \
    | jq --arg e "$2" '[.[] | select(.channel=="PUSH" and .eventType==$e)] | length'
}

# Every push row for one order, whatever the template.
pushes_of() { # pushes_of <orderId>
  curl -s "$LOG_URL/$1" -H "Authorization: Bearer $BACKOFFICE" \
    | jq '[.[] | select(.channel=="PUSH")]'
}

echo
echo '=== 0. Actors ==================================================================='

CUSTOMER=$(token customer 100001)
MERCHANT=$(token merchant 200002 delivery-portal)
RIDER=$(token rider 300003)
BACKOFFICE=$(token backoffice 400004 delivery-portal)

check 'customer signed in'   'yes' "$([ -n "$CUSTOMER" ]   && [ "$CUSTOMER" != null ]   && echo yes || echo no)"
check 'merchant signed in'   'yes' "$([ -n "$MERCHANT" ]   && [ "$MERCHANT" != null ]   && echo yes || echo no)"
check 'rider signed in'      'yes' "$([ -n "$RIDER" ]      && [ "$RIDER" != null ]      && echo yes || echo no)"
check 'backoffice signed in' 'yes' "$([ -n "$BACKOFFICE" ] && [ "$BACKOFFICE" != null ] && echo yes || echo no)"

echo
echo '=== 1. The push provider ========================================================'

CONNECTOR=$(curl -s "$PUSH_CONNECTOR/api/connector/status")
PROVIDER=$(echo "$CONNECTOR" | jq -r '.activeProvider')

check 'the connector answers'  'yes'    "$([ -n "$CONNECTOR" ] && echo yes || echo no)"
check 'a provider is active'   'yes'    "$([ "$PROVIDER" != null ] && [ -n "$PROVIDER" ] && echo yes || echo no)"
check 'its breaker is closed'  'CLOSED' "$(echo "$CONNECTOR" | jq -r '.circuitState')"

# Reported, not asserted. DEV_LOG means the chain runs and nothing leaves the box; FIREBASE means a
# real device is addressed. Both are valid, and which one is running changes what the rest of this
# suite actually proves — so it is printed rather than left to be inferred from a green run.
echo "  NOTE  active push provider is $PROVIDER"
if [ "$PROVIDER" != "FIREBASE" ]; then
  echo '        Not Firebase, so nothing below reaches a handset. The rows still prove the chain:'
  echo '        event, template, audience, receipt. Put the Firebase service-account JSON in Vault'
  echo '        at secret/push-connector to address real devices.'
fi

echo
echo '=== 2. One order, start to finish ==============================================='

# An ALREADY PUBLISHED product from the catalog, rather than a new one.
#
# A product created here would be a draft, and publishing one needs an image uploaded through a
# presigned URL first. That is the catalog suite's job; dragging it in here would mean this suite
# failing for reasons that have nothing to do with notifications.
PRODUCT=$(curl -s "$GW/api/products" -H "Authorization: Bearer $CUSTOMER" | jq -r '.content[0].id')
check 'a published product to order' 'yes' \
  "$([ "$PRODUCT" != null ] && [ -n "$PRODUCT" ] && echo yes || echo no)"

ORDER=$(curl -s -X POST "$GW/api/orders" -H "Authorization: Bearer $CUSTOMER" \
  -H 'Content-Type: application/json' \
  -d "{\"items\":[{\"productId\":\"$PRODUCT\",\"qty\":1}],\"deliveryAddress\":\"1 Push Street\",\"paymentMethod\":\"CASH\"}" \
  | jq -r '.id')
check 'order placed' 'yes' "$([ "$ORDER" != null ] && echo yes || echo no)"

# The merchant is told there is work. The only push that fires with no rider involved.
wait_for 45 "[ \"\$(pushes_for $ORDER order.placed.merchant)\" -ge 1 ]" || true
check 'merchant pushed: new order' '1' "$(pushes_for "$ORDER" order.placed.merchant)"

check 'merchant accepts'   '200' "$(status POST "/api/orders/$ORDER/accept" "$MERCHANT")"
check 'merchant prepares'  '200' "$(status POST "/api/orders/$ORDER/prepare" "$MERCHANT")"
check 'merchant marks ready' '200' "$(status POST "/api/orders/$ORDER/ready" "$MERCHANT")"
check 'rider claims it'    '200' "$(status POST "/api/orders/$ORDER/claim" "$RIDER")"

# One event, two audiences: the customer is told who is coming, the rider what they took on.
wait_for 45 "[ \"\$(pushes_for $ORDER order.rider_assigned)\" -ge 1 ]" || true
check 'customer pushed: rider assigned' '1' "$(pushes_for "$ORDER" order.rider_assigned)"
wait_for 30 "[ \"\$(pushes_for $ORDER order.rider_assigned.rider)\" -ge 1 ]" || true
check 'rider pushed: you took this one' '1' "$(pushes_for "$ORDER" order.rider_assigned.rider)"

check 'rider picks up' '200' "$(status POST "/api/orders/$ORDER/pick-up" "$RIDER")"
check 'rider delivers' '200' "$(status POST "/api/orders/$ORDER/deliver" "$RIDER")"

wait_for 45 "[ \"\$(pushes_for $ORDER order.delivered)\" -ge 1 ]" || true
check 'customer pushed: delivered' '1' "$(pushes_for "$ORDER" order.delivered)"

echo
echo '=== 3. The cancellation push ===================================================='

# Its own order. Cancelling is only allowed while PLACED, so it cannot be reached from the one
# above without unwinding a delivery that has already happened.
ORDER2=$(curl -s -X POST "$GW/api/orders" -H "Authorization: Bearer $CUSTOMER" \
  -H 'Content-Type: application/json' \
  -d "{\"items\":[{\"productId\":\"$PRODUCT\",\"qty\":1}],\"deliveryAddress\":\"2 Push Street\",\"paymentMethod\":\"CASH\"}" \
  | jq -r '.id')
check 'second order placed' 'yes' "$([ "$ORDER2" != null ] && echo yes || echo no)"

check 'customer cancels' '200' \
  "$(status POST "/api/orders/$ORDER2/cancel" "$CUSTOMER" '{"reason":"push suite"}')"

wait_for 45 "[ \"\$(pushes_for $ORDER2 order.cancelled.merchant)\" -ge 1 ]" || true
check 'merchant pushed: cancelled' '1' "$(pushes_for "$ORDER2" order.cancelled.merchant)"

echo
echo '=== 4. Every push was accepted by the provider =================================='

MINE=$(printf '%s\n%s\n' "$(pushes_of "$ORDER")" "$(pushes_of "$ORDER2")" | jq -s 'add')

# Six, not five. The five templates fire once each, and order.placed.merchant fires twice —
# once per order — because the second order is placed before it is cancelled.
check 'six pushes across the two orders' '6' "$(echo "$MINE" | jq 'length')"
check 'none left PENDING'  '0' "$(echo "$MINE" | jq '[.[]|select(.status=="PENDING")]|length')"
# Provider-aware, because "failed" means different things in the two modes.
#
# With the dev provider every row should reach SENT. With Firebase, the SEEDED accounts carry
# placeholder device tokens (dev-fcm-token-merchant-...) and Google rejects those as malformed —
# correctly. That is not a platform fault and must not read as one, so it is reported rather than
# failed. A REAL device token, from an account that has signed in on a phone, does reach SENT.
if [ "$PROVIDER" = "FIREBASE" ]; then
  REJECTED=$(echo "$MINE" | jq '[.[]|select(.status!="SENT")]|length')
  check 'every push reached the provider' '0' "$(echo "$MINE" | jq '[.[]|select(.provider==null)]|length')"
  if [ "$REJECTED" -gt 0 ]; then
    echo "  NOTE  $REJECTED of these were refused by Firebase. Expected here: the seeded demo"
    echo '        accounts hold placeholder device tokens, and only an account that has signed in'
    echo '        on a real phone has one Google will accept.'
  else
    check 'none failed' '0' "$REJECTED"
  fi
else
  check 'none failed' '0' "$(echo "$MINE" | jq '[.[]|select(.status!="SENT")]|length')"
fi
check 'each names its provider' '0' "$(echo "$MINE" | jq '[.[]|select(.provider==null)]|length')"
# The device token, resolved from the recipient's Keycloak profile rather than carried on the
# event. Null here would mean the lookup failed and the push was addressed to nobody — which is
# exactly what happens to an account that has never registered a device.
check 'each addressed a device' '0' \
  "$(echo "$MINE" | jq '[.[]|select(.recipient==null or .recipient=="")]|length')"
check 'each carries its body'   '0' "$(echo "$MINE" | jq '[.[]|select(.body==null or .body=="")]|length')"

echo
echo '=== 5. Nobody is pushed about their own action =================================='

# The customer is looking at the screen when they place and when they cancel. A notification for
# something you just did yourself is noise, and the templates deliberately have no such row.
check 'no push to the customer on place'  '0' "$(pushes_for "$ORDER" order.placed)"
check 'no push to the customer on cancel' '0' "$(pushes_for "$ORDER2" order.cancelled)"

echo
echo '================================================================================='
printf 'passed: %s   failed: %s\n' "$PASS" "$FAIL"
echo '================================================================================='
[ "$FAIL" -eq 0 ]
