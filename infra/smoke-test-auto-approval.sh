#!/bin/sh
# Auto-approval, proved by what the applicant can DO — not by a status field.
#
# "APPROVED" in the database means nothing on its own. The thing that matters is whether the role
# actually landed in Keycloak and whether the committing act the platform gates on now succeeds:
# a rider who can see the board but not claim from it is exactly the state auto-approval is meant
# to skip, and it looks identical to success from the application row.
set -eu
apk add --no-cache curl jq postgresql-client >/dev/null 2>&1
export PGPASSWORD="$POSTGRES_PASSWORD"

GW=https://api-dev.youdrop.shop
KC=https://iam-dev.youdrop.shop/realms/delivery-platform/protocol/openid-connect/token
PASS=0; FAIL=0
check() { if [ "$2" = "$3" ]; then printf '  \033[32mPASS\033[0m  %-50s %s\n' "$1" "$3"; PASS=$((PASS+1)); else printf '  \033[31mFAIL\033[0m  %-50s expected %s, got %s\n' "$1" "$2" "$3"; FAIL=$((FAIL+1)); fi; }

roles() {
  echo "$1" | cut -d. -f2 | tr '_-' '/+' | sed 's/$/==/' | base64 -d 2>/dev/null \
    | jq -r '[.realm_access.roles[]|select(.=="DELIVERY" or .=="MERCHANT" or .=="APPLICANT")]|sort|join(",")'
}

apply() { # apply <kind> <email> <passcode>  -> prints the reference
  curl -s -o /dev/null -X POST "$GW/api/onboarding/verifications" -H 'Content-Type: application/json' \
    -d "{\"channel\":\"EMAIL\",\"destination\":\"$2\"}"
  sleep 7
  CODE=$(psql -h postgres -U delivery -d delivery -At \
    -c "select body from notification.notification_log where recipient='$2' order by created_at desc limit 1;" \
    | grep -oE '[0-9]{6}' | head -1)
  T=$(curl -s -X POST "$GW/api/onboarding/verifications/confirm" -H 'Content-Type: application/json' \
    -d "{\"channel\":\"EMAIL\",\"destination\":\"$2\",\"code\":\"$CODE\"}" | jq -r .token)
  curl -s -X POST "$GW/api/onboarding/applications" -H 'Content-Type: application/json' \
    -d "{\"kind\":\"$1\",\"businessName\":\"Auto $1\",\"contactName\":\"Auto Tester\",\"contactEmail\":\"$2\",\"emailVerificationToken\":\"$T\"}" \
    | jq -r .reference
}

echo '=== 1. A rider, with nobody reviewing ==========================================='
RE="qa.autorider$(date +%s)@example.invalid"
RREF=$(apply RIDER "$RE" 246810)
check 'application submitted' 'yes' "$([ -n "$RREF" ] && [ "$RREF" != null ] && echo yes || echo no)"
# Still queued until the applicant has a sign-in. Approving before that produced an account with
# a password nobody knew, and blocked the passcode they went on to choose.
check 'queued until a sign-in exists' 'SUBMITTED' \
  "$(psql -h postgres -U delivery -d delivery -At -c "select status from onboarding.onboarding_applications where reference='$RREF';")"

curl -s -o /dev/null -X POST "$GW/api/onboarding/applications/$RREF/account" \
  -H 'Content-Type: application/json' -d '{"password":"246810"}'
sleep 8
check 'decided without a reviewer' 'PROVISIONED' \
  "$(psql -h postgres -U delivery -d delivery -At -c "select status from onboarding.onboarding_applications where reference='$RREF';")"
check 'and the record says who decided' 'system:auto-approval' \
  "$(psql -h postgres -U delivery -d delivery -At -c "select decided_by from onboarding.onboarding_applications where reference='$RREF';")"
RT=$(curl -s -X POST "$KC" -d client_id=mobile-app -d grant_type=password \
  --data-urlencode "username=$RE" -d password=246810 | jq -r .access_token)
check 'signs in' 'yes' "$([ "$RT" != null ] && echo yes || echo no)"
# The whole point: DELIVERY granted and APPLICANT gone, in one step, with no reviewer.
check 'holds DELIVERY, not APPLICANT' 'DELIVERY' "$(roles "$RT")"

echo '=== 2. And can actually take work ==============================================='
CUST=$(curl -s -X POST "$KC" -d client_id=mobile-app -d username=customer -d password=100001 -d grant_type=password | jq -r .access_token)
MERCH=$(curl -s -X POST "$KC" -d client_id=delivery-portal -d username=merchant -d password=200002 -d grant_type=password | jq -r .access_token)
P=$(curl -s "$GW/api/products/mine?size=50" -H "Authorization: Bearer $MERCH" | jq -r '[(.content // .)[]|select(.status=="ACTIVE")][0].id')
O=$(curl -s -X POST "$GW/api/orders" -H "Authorization: Bearer $CUST" -H 'Content-Type: application/json' \
  -d "{\"items\":[{\"productId\":\"$P\",\"qty\":1}],\"deliveryAddress\":\"Auto St\",\"paymentMethod\":\"CASH\"}" | jq -r .id)
for s in accept prepare ready; do curl -s -o /dev/null -X POST "$GW/api/orders/$O/$s" -H "Authorization: Bearer $MERCH"; done
# Previously this was 403 until a human approved. That refusal is what auto-approval removes.
check 'claims a job immediately' '200' \
  "$(curl -s -o /dev/null -w '%{http_code}' -X POST "$GW/api/orders/$O/claim" -H "Authorization: Bearer $RT")"

echo '=== 3. A merchant, same ========================================================='
ME="qa.automerch$(date +%s)@example.invalid"
MREF=$(apply MERCHANT "$ME" 135791)
curl -s -o /dev/null -X POST "$GW/api/onboarding/applications/$MREF/account" \
  -H 'Content-Type: application/json' -d '{"password":"135791"}'
sleep 8
check 'decided without a reviewer' 'PROVISIONED' \
  "$(psql -h postgres -U delivery -d delivery -At -c "select status from onboarding.onboarding_applications where reference='$MREF';")"
MT=$(curl -s -X POST "$KC" -d client_id=mobile-app -d grant_type=password \
  --data-urlencode "username=$ME" -d password=135791 | jq -r .access_token)
check 'holds MERCHANT, not APPLICANT' 'MERCHANT' "$(roles "$MT")"
NEW=$(curl -s -X POST "$GW/api/products" -H "Authorization: Bearer $MT" -H 'Content-Type: application/json' \
  -d '{"name":"Auto Approved Item","description":"placed with no reviewer","price":4.50}' | jq -r .id)
# Publishing is the act the platform gates on. It was 403 for a pending merchant.
check 'may publish (needs an image, so 422 not 403)' '422' \
  "$(curl -s -o /dev/null -w '%{http_code}' -X POST "$GW/api/products/$NEW/publish" -H "Authorization: Bearer $MT")"

echo '=== 4. A carrier is still reviewed =============================================='
CE="qa.autocarrier$(date +%s)@example.invalid"
CREF=$(apply CARRIER "$CE" 975312)
# Carriers were deliberately left manual: a company signs for a fleet and a payout account.
check 'carrier still waits for a human' 'SUBMITTED' \
  "$(psql -h postgres -U delivery -d delivery -At -c "select status from onboarding.onboarding_applications where reference='$CREF';")"

echo
echo "passed: $PASS   failed: $FAIL"
