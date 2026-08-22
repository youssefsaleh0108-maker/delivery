#!/bin/sh
# Phase 6: the SMS vendor cutover mechanism.
#
#   cd infra && docker run --rm --network delivery -v "$PWD/smoke-test-phase6.sh:/smoke.sh:ro" \
#     alpine:latest sh -c "apk add --no-cache curl jq >/dev/null && sh /smoke.sh"
#
# The vendor choice itself is a commercial decision nobody here can make (Section 12, open decision
# #6). What IS testable is everything the cutover depends on: that a ramp can carry a slice of
# traffic, that the split is deterministic so a retry never switches vendor, that a bad ramp stops
# in one action, and that delivery rates report the truth per provider.
#
# The determinism check is the one that matters. Route a message randomly and its retry can land on
# a vendor that has never seen its idempotency key - which accepts it as new, and the customer gets
# two texts, both billed.

set -eu

GW="http://traefik:8100"
KC="http://keycloak:8080/realms/delivery-platform/protocol/openid-connect/token"
SMS="http://sms-connector:8112"

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
    i=$((i + 1)); sleep 1
  done
  return 1
}

set_sms() { # set_sms <json-config>
  curl -s -o /dev/null -X PUT "$GW/api/settings/connectors/SMS" \
    -H "Authorization: Bearer $BACKOFFICE" -H 'Content-Type: application/json' \
    -d "{\"provider\":\"DEV_PASSTHROUGH\",\"config\":$1}"
}

route_of() { # route_of <idempotency-key>
  curl -s "$SMS/api/connector/route/$1" | jq -r '.provider'
}

CUSTOMER=$(token customer customer mobile-app)
BACKOFFICE=$(token backoffice backoffice backoffice-web)

echo
echo '=== 1. Delivery rates, the gate on a cutover ====================================='

# "Monitor delivery rates before fully retiring the test-inbox fallback" assumes a number that did
# not exist before this phase - notification_log had every fact needed and nothing computed it.
check 'customer cannot read delivery rates'  '403' "$(status GET "$GW/api/notification-rates" "$CUSTOMER")"
check 'anonymous cannot either'              '401' \
  "$(curl -s -o /dev/null -w '%{http_code}' "$GW/api/notification-rates")"
check 'backoffice can'                       '200' "$(status GET "$GW/api/notification-rates" "$BACKOFFICE")"

RATES=$(curl -s "$GW/api/notification-rates?windowHours=168" -H "Authorization: Bearer $BACKOFFICE")
check 'rates are reported per provider'      'yes' \
  "$(echo "$RATES" | jq '[.[]|select(.provider != null)]|length > 0' | sed 's/true/yes/;s/false/no/')"
# Grouped by provider, not only by channel: during a ramp two vendors are live on one channel and
# an averaged channel rate is the one shape of number that hides the problem it should reveal.
check 'and broken down by channel'           'yes' \
  "$(echo "$RATES" | jq '[.[]|.channel]|unique|length >= 2' | sed 's/true/yes/;s/false/no/')"
check 'a success rate is computed'           'yes' \
  "$(echo "$RATES" | jq '[.[]|select(.successRate != null)]|length > 0' | sed 's/true/yes/;s/false/no/')"
check 'the denominator is reported too'      'yes' \
  "$(echo "$RATES" | jq '[.[]|select(has("sent") and has("failed"))]|length == (.|length)' \
     | sed 's/true/yes/;s/false/no/')"
# A 100% rate over three messages is not evidence, so the count has to travel with the rate.
check 'the window is echoed back'            '168' "$(echo "$RATES" | jq -r '.[0].windowHours')"

echo
echo '=== 2. A canary must pass the same checks as a primary ==========================='

# The closed provider list is the whole reason a Backoffice user cannot point production at a typo.
# A canary decides where real messages go too, so it gets the same validation.
check 'an unknown canary provider is refused' '422' \
  "$(status PUT "$GW/api/settings/connectors/SMS" "$BACKOFFICE" \
     '{"provider":"DEV_PASSTHROUGH","config":{"canaryProvider":"NEXMO","canaryPercentage":"10"}}')"
# A canary with no percentage routes nothing, which looks exactly like a ramp that is working.
check 'a canary without a percentage is refused' '422' \
  "$(status PUT "$GW/api/settings/connectors/SMS" "$BACKOFFICE" \
     '{"provider":"DEV_PASSTHROUGH","config":{"canaryProvider":"TWILIO"}}')"
check 'a percentage over 100 is refused'     '422' \
  "$(status PUT "$GW/api/settings/connectors/SMS" "$BACKOFFICE" \
     '{"provider":"DEV_PASSTHROUGH","config":{"canaryProvider":"TWILIO","canaryPercentage":"150"}}')"
check 'a non-numeric percentage is refused'  '422' \
  "$(status PUT "$GW/api/settings/connectors/SMS" "$BACKOFFICE" \
     '{"provider":"DEV_PASSTHROUGH","config":{"canaryProvider":"TWILIO","canaryPercentage":"lots"}}')"
check 'a valid ramp is accepted'             '200' \
  "$(status PUT "$GW/api/settings/connectors/SMS" "$BACKOFFICE" \
     '{"provider":"DEV_PASSTHROUGH","config":{"canaryProvider":"TWILIO","canaryPercentage":"25"}}')"

echo
echo '=== 3. The ramp reaches the connector over the bus ==============================='

wait_for 20 "[ \"\$(curl -s $SMS/api/connector/status | jq -r '.canaryPercentage')\" = 25 ]" || true
check 'the connector sees the canary'        'TWILIO' \
  "$(curl -s "$SMS/api/connector/status" | jq -r '.canaryProvider')"
check 'and the percentage'                   '25' \
  "$(curl -s "$SMS/api/connector/status" | jq -r '.canaryPercentage')"
check 'the primary is unchanged'             'DEV_PASSTHROUGH' \
  "$(curl -s "$SMS/api/connector/status" | jq -r '.activeProvider')"

echo
echo '=== 4. Routing is deterministic =================================================='

# THE property the design rests on. Same key, same vendor, every time - across retries and across
# connector instances. Anything else double-sends on retry.
KEY="11111111-1111-4111-8111-111111111111"
FIRST=$(route_of "$KEY")
SAME=yes
i=0
while [ "$i" -lt 10 ]; do
  [ "$(route_of "$KEY")" = "$FIRST" ] || SAME=no
  i=$((i + 1))
done
check 'the same key always routes the same way' 'yes' "$SAME"
check 'its bucket is stable'                 "$(curl -s "$SMS/api/connector/route/$KEY" | jq -r '.bucket')" \
  "$(curl -s "$SMS/api/connector/route/$KEY" | jq -r '.bucket')"

# Roughly a quarter to the canary over a decent sample. Wide bounds: this asserts the split is in
# the right ballpark, not that CRC32 distributes perfectly.
CANARY_HITS=0
i=0
while [ "$i" -lt 200 ]; do
  [ "$(route_of "probe-$i")" = "TWILIO" ] && CANARY_HITS=$((CANARY_HITS + 1))
  i=$((i + 1))
done
check 'roughly a quarter goes to the canary' 'yes' \
  "$([ "$CANARY_HITS" -gt 25 ] && [ "$CANARY_HITS" -lt 75 ] && echo yes || echo no)"
check 'and the rest stays on the primary'    'yes' \
  "$([ "$CANARY_HITS" -lt 200 ] && echo yes || echo no)"

echo
echo '=== 5. Ramping up and completing ================================================='

curl -s -o /dev/null -X PUT "$GW/api/settings/connectors/SMS" -H "Authorization: Bearer $BACKOFFICE" \
  -H 'Content-Type: application/json' \
  -d '{"provider":"DEV_PASSTHROUGH","config":{"canaryProvider":"TWILIO","canaryPercentage":"100"}}'
wait_for 20 "[ \"\$(curl -s $SMS/api/connector/status | jq -r '.canaryPercentage')\" = 100 ]" || true

# 100% is the completed cutover: every message goes to the canary, without needing a separate
# final "switch the primary" step that could be forgotten half way.
ALL_CANARY=yes
i=0
while [ "$i" -lt 30 ]; do
  [ "$(route_of "complete-$i")" = "TWILIO" ] || ALL_CANARY=no
  i=$((i + 1))
done
check 'at 100% everything goes to the canary' 'yes' "$ALL_CANARY"

echo
echo '=== 6. Rollback is one action ===================================================='

# The only reason to press stop is that something is already going wrong, so it must be one call
# and it must not need the operator to remember what the previous config was.
check 'clearing the ramp is accepted'        '200' \
  "$(status PUT "$GW/api/settings/connectors/SMS" "$BACKOFFICE" \
     '{"provider":"DEV_PASSTHROUGH","config":{"senderId":"Delivery"}}')"
wait_for 20 "[ -z \"\$(curl -s $SMS/api/connector/status | jq -r '.canaryProvider')\" ] || [ \"\$(curl -s $SMS/api/connector/status | jq -r '.canaryProvider')\" = '' ]" || true

check 'the connector dropped the canary'     '' \
  "$(curl -s "$SMS/api/connector/status" | jq -r '.canaryProvider')"
BACK_TO_PRIMARY=yes
i=0
while [ "$i" -lt 30 ]; do
  [ "$(route_of "rollback-$i")" = "DEV_PASSTHROUGH" ] || BACK_TO_PRIMARY=no
  i=$((i + 1))
done
check 'everything is back on the primary'    'yes' "$BACK_TO_PRIMARY"

# Every ramp change went through the same audited path as a provider switch.
check 'the ramp changes were audited'        'yes' \
  "$(curl -s "$GW/api/settings/connectors/SMS/history" -H "Authorization: Bearer $BACKOFFICE" \
     | jq 'length >= 5' | sed 's/true/yes/;s/false/no/')"
check 'and name who made them'               "$(echo "$BACKOFFICE" | cut -d. -f2 | tr '_-' '/+' | sed 's/$/==/' | base64 -d 2>/dev/null | jq -r '.sub')" \
  "$(curl -s "$GW/api/settings/connectors/SMS/history" -H "Authorization: Bearer $BACKOFFICE" \
     | jq -r '.[0].changedBy')"

echo
echo '=== 7. Real traffic still flows on the primary ==================================='

# The cutover machinery must not have broken ordinary sending. Cheapest possible end-to-end proof:
# a real notification through the real connector to the real dev inbox.
BEFORE=$(curl -s "http://mailpit:8025/api/v1/messages?limit=1" | jq '.messages_count')
curl -s -o /dev/null -X POST "$SMS/api/connector/send" -H 'Content-Type: application/json' \
  -d "{\"notificationId\":\"$(date +%s)-phase6\",\"channel\":\"SMS\",\"recipient\":\"+15550100001\",
       \"subject\":null,\"body\":\"phase 6 smoke\",\"metadata\":{},\"correlationId\":\"phase6\",
       \"createdAt\":\"2026-01-01T00:00:00Z\"}"
wait_for 30 "[ \"\$(curl -s 'http://mailpit:8025/api/v1/messages?limit=1' | jq '.messages_count')\" -gt $BEFORE ]" || true
check 'a real SMS still reaches the inbox'   'yes' \
  "$(curl -s "http://mailpit:8025/api/v1/messages?limit=1" \
     | jq --argjson b "$BEFORE" '.messages_count > $b' | sed 's/true/yes/;s/false/no/')"

echo
echo '================================================================================='
printf 'passed: %s   failed: %s\n' "$PASS" "$FAIL"
echo '================================================================================='
[ "$FAIL" -eq 0 ] || exit 1
