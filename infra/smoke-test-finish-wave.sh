#!/bin/sh
# The finish wave: tiers, aggregates, activity, rider performance, password reset, partner API
# keys, duty hours and provider profiles — over the PUBLIC domain, the way a client reaches them.
#
# Every block asserts the refusal as well as the success. That is not thoroughness for its own
# sake: three real defects came out of these checks and none was visible from a happy path — two
# prefixes the gateway had never been told to route, and an unknown enum answering 500 as though
# the platform were broken rather than 400 as though the caller were.
set -eu
apk add --no-cache curl jq postgresql-client >/dev/null 2>&1
export PGPASSWORD="$POSTGRES_PASSWORD"

GW=https://api-dev.youdrop.shop
KC=https://iam-dev.youdrop.shop/realms/delivery-platform/protocol/openid-connect/token
PASS=0; FAIL=0
check() { if [ "$2" = "$3" ]; then printf '  \033[32mPASS\033[0m  %-56s %s\n' "$1" "$3"; PASS=$((PASS+1)); else printf '  \033[31mFAIL\033[0m  %-56s expected %s, got %s\n' "$1" "$2" "$3"; FAIL=$((FAIL+1)); fi; }
tok() { curl -s -X POST "$KC" -d client_id="${3:-mobile-app}" --data-urlencode "username=$1" -d "password=$2" -d grant_type=password | jq -r .access_token; }

CUST=$(tok customer 100001)
MERCH=$(tok merchant 200002 delivery-portal)
RIDER=$(tok rider 300003)
BO=$(tok backoffice 400004 delivery-portal)
CARRIER=$(tok carrier 500005 delivery-portal)

echo '=== 1. Delivery tiers ==========================================================='
P=$(curl -s "$GW/api/products/mine?size=50" -H "Authorization: Bearer $MERCH" | jq -r '[(.content // .)[]|select(.status=="ACTIVE")][0].id')
EXPRESS=$(curl -s -X POST "$GW/api/orders" -H "Authorization: Bearer $CUST" -H 'Content-Type: application/json' \
  -d "{\"items\":[{\"productId\":\"$P\",\"qty\":1}],\"deliveryAddress\":\"Tier St\",\"paymentMethod\":\"CASH\",\"deliveryTier\":\"EXPRESS\"}")
check 'EXPRESS order placed' 'EXPRESS' "$(echo "$EXPRESS" | jq -r .deliveryTier)"
check 'surcharge itemised, not folded' '2.00' "$(echo "$EXPRESS" | jq -r '.expressSurcharge|tostring')"
SUB=$(echo "$EXPRESS" | jq -r .subtotal); TOT=$(echo "$EXPRESS" | jq -r .totalAmount); FEE=$(echo "$EXPRESS" | jq -r .deliveryFeeCharged)
check 'total = subtotal + fee + surcharge' 'yes' "$(echo "$SUB $FEE $TOT" | awk '{print ($1+$2+2.00==$3)?"yes":"no"}')"
STD=$(curl -s -X POST "$GW/api/orders" -H "Authorization: Bearer $CUST" -H 'Content-Type: application/json' \
  -d "{\"items\":[{\"productId\":\"$P\",\"qty\":1}],\"deliveryAddress\":\"Tier St\",\"paymentMethod\":\"CASH\"}")
check 'default is STANDARD at 0' 'STANDARD 0' "$(echo "$STD" | jq -r '"\(.deliveryTier) \(.expressSurcharge|floor)"')"
check 'unknown tier refused' '400' "$(curl -s -o /dev/null -w '%{http_code}' -X POST "$GW/api/orders" -H "Authorization: Bearer $CUST" -H 'Content-Type: application/json' \
  -d "{\"items\":[{\"productId\":\"$P\",\"qty\":1}],\"deliveryAddress\":\"x\",\"paymentMethod\":\"CASH\",\"deliveryTier\":\"WARP\"}")"

echo '=== 2. Aggregates + activity ===================================================='
AGG=$(curl -s "$GW/api/orders/daily?days=7" -H "Authorization: Bearer $BO")
check 'backoffice series answers' '7' "$(echo "$AGG" | jq '.days|length')"
check 'series carries tier split' 'yes' "$(echo "$AGG" | jq -r '.days[0]|has("standard") and has("express")|tostring' | sed 's/true/yes/;s/false/no/')"
check 'merchant scope answers' '200' "$(curl -s -o /dev/null -w '%{http_code}' "$GW/api/orders/merchant/daily?days=7" -H "Authorization: Bearer $MERCH")"
check 'customer scope refused' '403' "$(curl -s -o /dev/null -w '%{http_code}' "$GW/api/orders/daily?days=7" -H "Authorization: Bearer $CUST")"
ACT=$(curl -s "$GW/api/orders/activity?size=5" -H "Authorization: Bearer $BO")
check 'activity feed answers' 'yes' "$(echo "$ACT" | jq '(if type=="array" then length else (.content|length) end) > 0' | sed 's/true/yes/;s/false/no/')"
check 'activity refused to merchant' '403' "$(curl -s -o /dev/null -w '%{http_code}' "$GW/api/orders/activity?size=5" -H "Authorization: Bearer $MERCH")"

echo '=== 3. Rider performance + counts ==============================================='
check 'rider sees own stats' '200' "$(curl -s -o /dev/null -w '%{http_code}' "$GW/api/orders/riders/me/performance" -H "Authorization: Bearer $RIDER")"
PERF=$(curl -s "$GW/api/orders/riders/me/performance" -H "Authorization: Bearer $RIDER")
CLAIMED=$(echo "$PERF" | jq -r '.claimed // .claimedCount'); DELIV=$(echo "$PERF" | jq -r '.delivered // .deliveredCount')
check 'stats are numbers from real orders' 'yes' "$([ "$CLAIMED" -ge "$DELIV" ] 2>/dev/null && echo yes || echo no)"
check 'customer refused rider stats' '403' "$(curl -s -o /dev/null -w '%{http_code}' "$GW/api/orders/riders/me/performance" -H "Authorization: Bearer $CUST")"

echo '=== 4. Password reset ==========================================================='
E="qa.reset$(date +%s)@example.invalid"
curl -s -o /dev/null -X POST "$GW/api/onboarding/verifications" -H 'Content-Type: application/json' -d "{\"channel\":\"EMAIL\",\"destination\":\"$E\"}"
sleep 6
CODE=$(psql -h postgres -U delivery -d delivery -At -c "select body from notification.notification_log where recipient='$E' order by created_at desc limit 1;" | grep -oE '[0-9]{6}' | head -1)
T=$(curl -s -X POST "$GW/api/onboarding/verifications/confirm" -H 'Content-Type: application/json' -d "{\"channel\":\"EMAIL\",\"destination\":\"$E\",\"code\":\"$CODE\"}" | jq -r .token)
# Asserted, not fire-and-forget. This silently 400'd on a guessed payload shape, so no account
# existed — and the reset below then answered 422, which the contract defines as the CORRECT reply
# to a valid code for an address with no account. A skipped setup step reads as a product failure.
check 'account created for the reset test' '201' "$(curl -s -o /dev/null -w '%{http_code}' \
  -X POST "$GW/api/onboarding/signup" -H 'Content-Type: application/json' \
  -d "{\"email\":\"$E\",\"verificationToken\":\"$T\",\"firstName\":\"Reset\",\"lastName\":\"Tester\",\"password\":\"111222\"}")"
check 'unknown email still 202'  '202' "$(curl -s -o /dev/null -w '%{http_code}' -X POST "$GW/api/onboarding/password-reset" -H 'Content-Type: application/json' -d '{"email":"nobody@example.invalid"}')"
sleep 65   # the per-address cooldown is shared with the signup code sent above — by design
check 'reset requested' '202' "$(curl -s -o /dev/null -w '%{http_code}' -X POST "$GW/api/onboarding/password-reset" -H 'Content-Type: application/json' -d "{\"email\":\"$E\"}")"
sleep 6
RCODE=$(psql -h postgres -U delivery -d delivery -At -c "select body from notification.notification_log where recipient='$E' order by created_at desc limit 1;" | grep -oE '[0-9]{6}' | head -1)
check 'confirm sets new passcode' '204' "$(curl -s -o /dev/null -w '%{http_code}' -X POST "$GW/api/onboarding/password-reset/confirm" -H 'Content-Type: application/json' -d "{\"email\":\"$E\",\"code\":\"$RCODE\",\"newPassword\":\"333444\"}")"
check 'new passcode signs in' 'yes' "$([ "$(tok "$E" 333444)" != null ] && echo yes || echo no)"
check 'old passcode dead' 'null' "$(tok "$E" 111222)"
check 'code is single-use (422 per contract)' '422' "$(curl -s -o /dev/null -w '%{http_code}' -X POST "$GW/api/onboarding/password-reset/confirm" -H 'Content-Type: application/json' -d "{\"email\":\"$E\",\"code\":\"$RCODE\",\"newPassword\":\"555666\"}")"

echo '=== 5. Partner API keys ========================================================='
K=$(curl -s -X POST "$GW/api/partner-keys" -H "Authorization: Bearer $CARRIER" -H 'Content-Type: application/json' -d '{"label":"e2e"}')
SECRET=$(echo "$K" | jq -r '.secret // .apiKey // .key')
check 'key created, secret shown once' 'yes' "$([ -n "$SECRET" ] && [ "$SECRET" != null ] && echo yes || echo no)"
check 'list never re-shows secret' '0' "$(curl -s "$GW/api/partner-keys" -H "Authorization: Bearer $CARRIER" | grep -c "$SECRET" || true)"
check 'partner feed with key' '200' "$(curl -s -o /dev/null -w '%{http_code}' "$GW/api/partner/jobs" -H "X-API-Key: $SECRET")"
check 'partner feed w/o key' '401' "$(curl -s -o /dev/null -w '%{http_code}' "$GW/api/partner/jobs")"
check 'garbage key refused' '401' "$(curl -s -o /dev/null -w '%{http_code}' "$GW/api/partner/jobs" -H "X-API-Key: nope-$(date +%s)")"
KID=$(curl -s "$GW/api/partner-keys" -H "Authorization: Bearer $CARRIER" | jq -r '.[0].id')
check 'revoke' '204' "$(curl -s -o /dev/null -w '%{http_code}' -X DELETE "$GW/api/partner-keys/$KID" -H "Authorization: Bearer $CARRIER")"
check 'revoked key dead' '401' "$(curl -s -o /dev/null -w '%{http_code}' "$GW/api/partner/jobs" -H "X-API-Key: $SECRET")"

echo '=== 6. Duty hours + provider profile ============================================'
curl -s -o /dev/null -X POST "$GW/api/tracking/riders/me/duty" -H "Authorization: Bearer $RIDER" -H 'Content-Type: application/json' -d '{"state":"ON_DUTY"}'
sleep 2
curl -s -o /dev/null -X POST "$GW/api/tracking/riders/me/duty" -H "Authorization: Bearer $RIDER" -H 'Content-Type: application/json' -d '{"state":"OFF_DUTY"}'
HRS=$(curl -s "$GW/api/tracking/riders/me/duty/hours?days=7" -H "Authorization: Bearer $RIDER")
check 'duty hours answer' 'yes' "$(echo "$HRS" | jq '.days|type=="array"' | sed 's/true/yes/;s/false/no/')"
check 'today recorded a session' 'yes' "$(echo "$HRS" | jq '([.days[]?.secondsOnline]|add // 0) > 0' | sed 's/true/yes/;s/false/no/')"
PROVIDER_ID=$(curl -s "$GW/api/delivery-providers/my-company" -H "Authorization: Bearer $CARRIER" | jq -r .id)
# No fallback: guessing a company here tests somebody else's data and reads as a 403 bug.
[ -n "$PROVIDER_ID" ] && [ "$PROVIDER_ID" != null ] || { echo "  carrier is staff of no company — run seed-carrier-staff.sh"; exit 1; }
PROF=$(curl -s -o /dev/null -w '%{http_code}' -X PUT "$GW/api/onboarding/providers/$PROVIDER_ID/profile" -H "Authorization: Bearer $CARRIER" -H 'Content-Type: application/json' \
  -d '{"dispatchRegions":["Beirut-Hamra","Beirut-Achrafieh"],"operatingHours":{"MONDAY":{"open":"08:00","close":"22:00"}}}')
check 'provider profile saves' '200' "$PROF"
check 'foreign company refused' '403' "$(curl -s -o /dev/null -w '%{http_code}' -X PUT "$GW/api/onboarding/providers/00000000-0000-4000-8000-00000000d001/profile" -H "Authorization: Bearer $CARRIER" -H 'Content-Type: application/json' -d '{"dispatchRegions":["x"],"operatingHours":{"MONDAY":{"open":"08:00","close":"22:00"}}}')"
check 'bad hours refused' '400' "$(curl -s -o /dev/null -w '%{http_code}' -X PUT "$GW/api/onboarding/providers/$PROVIDER_ID/profile" -H "Authorization: Bearer $CARRIER" -H 'Content-Type: application/json' -d '{"operatingHours":{"MONDAY":{"open":"23:00","close":"08:00"}}}')"

echo
echo "passed: $PASS   failed: $FAIL"
