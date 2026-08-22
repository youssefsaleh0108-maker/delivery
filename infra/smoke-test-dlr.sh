#!/bin/sh
# Carrier delivery receipts (DLRs) — proving the platform can tell "accepted" from "arrived".
#
#   cd infra && docker run --rm --network delivery -v "$PWD/smoke-test-dlr.sh:/smoke.sh:ro" \
#     alpine:latest sh -c "apk add --no-cache curl jq openssl >/dev/null && sh /smoke.sh"
#
# NOTE: needs `openssl` as well as curl/jq — the signature is the whole point, so the script has to
# be able to produce a real one.
#
# This is not a seventh roadmap phase; Section 11 ends at Phase 6. It closes the honest limit that
# Phase 6 recorded in the README: delivery rates measured ACCEPTANCE, because nothing ingested vendor
# receipts. "100% success" meant "100% accepted", and that was the number a vendor decision was
# meant to rest on.
#
# Most of what follows asserts what the endpoint REFUSES. It is the one public path in the platform,
# and the numbers it writes decide which vendor gets the contract — so an unsigned receipt being
# accepted would be worse than no receipts at all.

set -eu

GW="http://traefik:8100"
KC="http://keycloak:8080/realms/delivery-platform/protocol/openid-connect/token"
PG="postgres"
export PGPASSWORD="${POSTGRES_PASSWORD:-delivery}"

# Dev-only, and only ever signs receipts for a provider that sends nothing real.
DEV_SECRET="${SMS_DEV_DLR_SECRET:-dev-dlr-secret}"

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

sign() { # sign <body>
  printf '%s' "$1" | openssl dgst -sha256 -hmac "$DEV_SECRET" -hex | sed 's/.*= *//'
}

post_dlr() { # post_dlr <provider> <body> <signature>
  curl -s -o /dev/null -w '%{http_code}' -X POST "$GW/webhooks/dlr/$1" \
    -H "x-delivery-signature: $3" -d "$2"
}

psql_one() {
  psql -h "$PG" -U delivery -d delivery -t -A -c "$1" 2>/dev/null | head -1
}

BACKOFFICE=$(token backoffice backoffice backoffice-web)
[ -n "$BACKOFFICE" ] && [ "$BACKOFFICE" != null ] || { echo 'No backoffice token'; exit 1; }

echo
echo '=== 1. The webhook refuses anything it cannot verify ============================='

# An unauthenticated caller can reach this path by design — that is what makes the signature check
# the only thing standing between a stranger and the delivery numbers.
check 'an unsigned receipt is refused' '401' \
  "$(curl -s -o /dev/null -w '%{http_code}' -X POST "$GW/webhooks/dlr/DEV_PASSTHROUGH" \
     -d 'messageId=forged&status=delivered')"

check 'a wrongly-signed receipt is refused' '401' \
  "$(post_dlr DEV_PASSTHROUGH 'messageId=forged&status=delivered' 'deadbeef')"

# The signature covers the content, so a genuine signature cannot be lifted onto a different outcome.
GENUINE=$(sign 'messageId=abc&status=delivered')
check 'a valid signature replayed on other content is refused' '401' \
  "$(post_dlr DEV_PASSTHROUGH 'messageId=abc&status=undelivered' "$GENUINE")"

check 'an unknown provider is refused' '404' \
  "$(post_dlr NOSUCH 'messageId=abc&status=delivered' "$GENUINE")"

echo
echo '=== 2. Opening this path did not open the connector =============================='

# The reason the webhook lives on its own prefix. /api/connector/** must stay unroutable, or the
# Gateway would be handing out "send an arbitrary SMS" to anyone with any valid token.
check 'the connector send path is still unrouted' '404' \
  "$(curl -s -o /dev/null -w '%{http_code}' -X POST "$GW/api/connector/send" \
     -H "Authorization: Bearer $BACKOFFICE" -H 'Content-Type: application/json' -d '{}')"
check 'the connector status path is still unrouted' '404' \
  "$(curl -s -o /dev/null -w '%{http_code}' -X GET "$GW/api/connector/status" \
     -H "Authorization: Bearer $BACKOFFICE")"

echo
echo '=== 3. A verified receipt reaches the log ========================================'

MSG=$(psql_one "select provider_message_id from notification.notification_log
                 where provider = 'DEV_PASSTHROUGH' and provider_message_id is not null
                   and delivery_status is null and status = 'SENT'
                 order by created_at desc limit 1")

if [ -z "$MSG" ]; then
  echo '  SKIP  no un-receipted SMS in the log to acknowledge'
else
  BODY="messageId=${MSG}&status=delivered"
  check 'a signed receipt is accepted' '204' "$(post_dlr DEV_PASSTHROUGH "$BODY" "$(sign "$BODY")")"

  i=0
  while [ "$i" -lt 15 ]; do
    APPLIED=$(psql_one "select delivery_status from notification.notification_log
                         where provider_message_id = '$MSG'")
    [ "$APPLIED" = 'DELIVERED' ] && break
    i=$((i + 1)); sleep 1
  done
  check 'the carrier outcome is recorded' 'DELIVERED' "$APPLIED"

  # The point of the whole feature: acceptance and delivery are different facts, stored separately,
  # and the first is not overwritten by the second.
  check 'acceptance is NOT overwritten by delivery' 'SENT' \
    "$(psql_one "select status from notification.notification_log
                  where provider_message_id = '$MSG'")"
  check 'the delivery timestamp is set' 't' \
    "$(psql_one "select delivered_at is not null from notification.notification_log
                  where provider_message_id = '$MSG'")"

  echo
  echo '=== 4. Receipts are idempotent and order-independent =============================='

  # The bus is at-least-once and unordered, so "last write wins" would make the stored outcome
  # depend on the order two redeliveries happened to arrive in.
  CONTRA="messageId=${MSG}&status=undelivered"
  check 'a contradicting later receipt is accepted at the edge' '204' \
    "$(post_dlr DEV_PASSTHROUGH "$CONTRA" "$(sign "$CONTRA")")"
  sleep 3
  check 'but the first terminal outcome still stands' 'DELIVERED' \
    "$(psql_one "select delivery_status from notification.notification_log
                  where provider_message_id = '$MSG'")"
fi

echo
echo '=== 5. An intermediate state is not an outcome ==================================='

# "sending" means the carrier has not decided yet. Recording it as an answer would resolve a
# message's fate before anyone knows it.
INTERMEDIATE='messageId=whatever&status=sending'
check 'an in-flight status is accepted but records nothing' '204' \
  "$(post_dlr DEV_PASSTHROUGH "$INTERMEDIATE" "$(sign "$INTERMEDIATE")")"

echo
echo '=== 6. The rate report separates accepted from delivered ========================='

RATES=$(curl -s -H "Authorization: Bearer $BACKOFFICE" "$GW/api/notification-rates")

check 'the report exposes a delivery rate' 'yes' \
  "$(echo "$RATES" | jq -r 'if any(.[]; has("deliveryRate")) then "yes" else "no" end')"
check 'and counts awaiting receipts separately' 'yes' \
  "$(echo "$RATES" | jq -r 'if any(.[]; has("awaitingReceipt")) then "yes" else "no" end')"

# The null-vs-zero rule, applied to the new axis. A channel nobody has ever sent a receipt for must
# read as unknown, not as a total delivery failure — EMAIL has no carrier receipts by nature.
check 'a channel with no receipts reports null, not 0' 'null' \
  "$(echo "$RATES" | jq -r '[.[] | select(.channel=="EMAIL")][0].deliveryRate // "null"')"

# Delivered + undelivered is the denominator; awaiting is excluded rather than counted as failure.
check 'the delivery rate is over confirmed outcomes only' 'yes' \
  "$(echo "$RATES" | jq -r '
      [.[] | select(.deliveryRate != null)
           | select((.delivered + .undelivered) > 0)] | if length > 0 then "yes" else "no" end')"

echo
echo '================================================================================='
printf 'passed: %s   failed: %s\n' "$PASS" "$FAIL"
echo '================================================================================='
[ "$FAIL" -eq 0 ]
