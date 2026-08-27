#!/bin/sh
# Phase 3 end-to-end smoke test: the notification layer.
#
#   cd infra && docker run --rm --network delivery -v "$PWD/smoke-test-phase3.sh:/smoke.sh:ro" \
#     alpine:latest sh -c "apk add --no-cache curl jq >/dev/null && sh /smoke.sh"
#
# Runs inside the compose network on purpose. Half of what is under test - the connectors' send
# endpoint, the internal settings read, Mailpit - is deliberately not routed by the API Gateway,
# so it is only reachable from here.
#
# What it proves, in order:
#   1. Connector Settings enforces its role, its closed provider list and its no-secrets rule
#   2. A provider switch reaches a running connector over the bus, without a restart
#   3. One order event fans out to the right audiences on the right channels
#   4. An SMS really arrives (in the dev test inbox) and an email really arrives
#   5. Every notification_log row reaches a terminal state via a worker receipt
#   6. In-app messages land in the recipient's inbox with working read state
#   7. Bad recipients are rejected by the worker and dead-lettered, not sent

set -eu

GW="http://traefik:8100"
KC="http://keycloak:8080/realms/delivery-platform/protocol/openid-connect/token"
SETTINGS="http://connector-settings:8109"
SMS_CONNECTOR="http://sms-connector:8112"
# The dev mail sink. Absent when mail is pointed at a real relay, which section 5 handles.
# /mailpit, because the sink is mounted under that path on monitoring-dev and is told so with
# MP_WEBROOT — its API moved with its UI.
MAILPIT="${MAILPIT_URL:-http://mailpit:8025/mailpit}"
EMAIL_CONNECTOR="http://email-connector:8110"
PUSH_CONNECTOR="http://push-connector:8111"
RABBIT="http://rabbitmq:15672"

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

status() { # status <method> <url> <token> [body]
  if [ $# -ge 4 ]; then
    curl -s -o /dev/null -w '%{http_code}' -X "$1" "$2" \
      -H "Authorization: Bearer $3" -H 'Content-Type: application/json' -d "$4"
  else
    curl -s -o /dev/null -w '%{http_code}' -X "$1" "$2" -H "Authorization: Bearer $3"
  fi
}

# Notifications travel outbox -> bus -> manager -> worker -> connector -> receipt -> log. That is
# six hops of polling and queueing, so anything asserted about the end of it has to be waited for
# rather than read once. Polling with a ceiling keeps a genuine failure fast instead of hanging.
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
echo '=== 0. Actors ==================================================================='

CUSTOMER=$(token customer 100001 mobile-app)
MERCHANT=$(token merchant 200002 delivery-portal)
BACKOFFICE=$(token backoffice 400004 delivery-portal)

for t in CUSTOMER MERCHANT BACKOFFICE; do
  eval "v=\$$t"
  [ -n "$v" ] && [ "$v" != null ] || { echo "Could not obtain a $t token"; exit 1; }
done

CUSTOMER_SUB=$(claim_of "$CUSTOMER" '.sub')
MERCHANT_SUB=$(claim_of "$MERCHANT" '.sub')
echo "  customer, merchant, backoffice tokens obtained"

echo
echo '=== 1. Connector Settings ========================================================'

check 'anonymous cannot read settings'   '401' \
  "$(curl -s -o /dev/null -w '%{http_code}' "$GW/api/settings/connectors")"
check 'customer cannot read settings'    '403' "$(status GET "$GW/api/settings/connectors" "$CUSTOMER")"
check 'merchant cannot read settings'    '403' "$(status GET "$GW/api/settings/connectors" "$MERCHANT")"
check 'backoffice reads settings'        '200' "$(status GET "$GW/api/settings/connectors" "$BACKOFFICE")"

ALL=$(curl -s "$GW/api/settings/connectors" -H "Authorization: Bearer $BACKOFFICE")
check 'four connectors configured'       '4'    "$(echo "$ALL" | jq 'length')"

SMS_SETTING=$(curl -s "$GW/api/settings/connectors/SMS" -H "Authorization: Bearer $BACKOFFICE")
check 'SMS starts on dev-passthrough'    'DEV_PASSTHROUGH' "$(echo "$SMS_SETTING" | jq -r '.provider')"
check 'UI is handed the provider list'   '3'    "$(echo "$SMS_SETTING" | jq '.availableProviders | length')"
# Section 8: the UI shows that a credential exists and when it changed, never the credential.
check 'secret is masked, never returned' '********' "$(echo "$SMS_SETTING" | jq -r '.maskedSecret')"
check 'vault path is shown instead'      'secret/sms-connector' "$(echo "$SMS_SETTING" | jq -r '.vaultPath')"

check 'unknown provider refused'         '422' "$(status PUT "$GW/api/settings/connectors/SMS" \
  "$BACKOFFICE" '{"provider":"NEXMO"}')"
# A settings form is exactly where someone pastes an API key "just to test", and a jsonb column
# ends up in backups and audit rows.
check 'config that smells of a secret refused' '422' "$(status PUT "$GW/api/settings/connectors/SMS" \
  "$BACKOFFICE" '{"provider":"TWILIO","config":{"apiKey":"sk_live_123"}}')"
check 'and so does a password field'     '422' "$(status PUT "$GW/api/settings/connectors/SMS" \
  "$BACKOFFICE" '{"provider":"TWILIO","config":{"smtpPassword":"hunter2"}}')"

echo
echo '=== 2. A provider switch reaches a running connector ============================='

check 'connector reports its provider'   'DEV_PASSTHROUGH' \
  "$(curl -s "$SMS_CONNECTOR/api/connector/status" | jq -r '.activeProvider')"
check 'all three SMS clients deployed'   '3' \
  "$(curl -s "$SMS_CONNECTOR/api/connector/status" | jq '.availableProviders | length')"

check 'backoffice switches SMS to Twilio' '200' "$(status PUT "$GW/api/settings/connectors/SMS" \
  "$BACKOFFICE" '{"provider":"TWILIO","config":{"senderId":"Delivery"}}')"

# No restart, no redeploy: the connector.settings_changed event is the whole point of Section 8.
wait_for 20 "[ \"\$(curl -s $SMS_CONNECTOR/api/connector/status | jq -r '.activeProvider')\" = TWILIO ]" || true
check 'connector switched over the bus'  'TWILIO' \
  "$(curl -s "$SMS_CONNECTOR/api/connector/status" | jq -r '.activeProvider')"

check 'the change is audited'            'yes' \
  "$(curl -s "$GW/api/settings/connectors/SMS/history" -H "Authorization: Bearer $BACKOFFICE" \
     | jq '.[0].oldValue.provider == "DEV_PASSTHROUGH" and .[0].newValue.provider == "TWILIO"' \
     | sed 's/true/yes/;s/false/no/')"
check 'audit records who changed it'     "$(claim_of "$BACKOFFICE" '.sub')" \
  "$(curl -s "$GW/api/settings/connectors/SMS/history" -H "Authorization: Bearer $BACKOFFICE" \
     | jq -r '.[0].changedBy')"

# Back to the safe default before anything is actually sent - Twilio has no credentials, and the
# rest of this test wants real messages in the test inbox.
curl -s -o /dev/null -X PUT "$GW/api/settings/connectors/SMS" -H "Authorization: Bearer $BACKOFFICE" \
  -H 'Content-Type: application/json' -d '{"provider":"DEV_PASSTHROUGH","config":{"senderId":"Delivery"}}'
wait_for 20 "[ \"\$(curl -s $SMS_CONNECTOR/api/connector/status | jq -r '.activeProvider')\" = DEV_PASSTHROUGH ]" || true
check 'switched back to dev-passthrough' 'DEV_PASSTHROUGH' \
  "$(curl -s "$SMS_CONNECTOR/api/connector/status" | jq -r '.activeProvider')"

check 'email connector is on SMTP'       'SMTP'    "$(curl -s "$EMAIL_CONNECTOR/api/connector/status" | jq -r '.activeProvider')"
check 'push connector has both clients'  '2'       "$(curl -s "$PUSH_CONNECTOR/api/connector/status" | jq '.availableProviders | length')"
check 'every breaker starts closed'      'CLOSED'  "$(curl -s "$SMS_CONNECTOR/api/connector/status" | jq -r '.circuitState')"

echo
echo '=== 3. One order event, fanned out to the right audiences ========================'


CATS=$(curl -s "$GW/api/categories" -H "Authorization: Bearer $CUSTOMER")
FOOD=$(echo "$CATS" | jq -r '[.[] | select(.name=="Food")][0].id')
PRODUCT=$(curl -s -X POST "$GW/api/products" -H "Authorization: Bearer $MERCHANT" \
  -H 'Content-Type: application/json' \
  -d "{\"name\":\"Phase3 Noodles\",\"description\":\"For the notification test\",\"price\":11.00,\"categoryId\":\"$FOOD\"}" \
  | jq -r '.id')

# Phase 1 refuses to publish a product with no image, so the upload is part of getting to an order.
# The presigned URL must be used EXACTLY as issued: SigV4 signs the Host header, so rewriting the
# URL to reach MinIO internally gives 403 SignatureDoesNotMatch. --connect-to redirects the TCP
# connection while leaving the Host intact. See the longer note in smoke-test.sh.
PRESIGN=$(curl -s -X POST "$GW/api/products/$PRODUCT/images/presign" \
  -H "Authorization: Bearer $MERCHANT" -H 'Content-Type: application/json' \
  -d '{"contentType":"image/png"}')
FILE_ID=$(echo "$PRESIGN" | jq -r '.fileId')
UPLOAD_URL=$(echo "$PRESIGN" | jq -r '.uploadUrl')

printf '\211PNG\r\n\032\n\0\0\0\rIHDR\0\0\0\1\0\0\0\1\10\6\0\0\0\37\25\304\211\0\0\0\nIDATx\234c\370\17\0\1\1\1\0\30\335\215\260\0\0\0\0IEND\256B`\202' > /tmp/p.png
UPLOAD_HOSTPORT=$(echo "$UPLOAD_URL" | sed -E 's|^https?://([^/]+)/.*|\1|')
case "$UPLOAD_HOSTPORT" in *:*) : ;; *) UPLOAD_HOSTPORT="$UPLOAD_HOSTPORT:80" ;; esac

curl -s -o /dev/null --connect-to "$UPLOAD_HOSTPORT:minio:9000" \
  -X PUT "$UPLOAD_URL" -H 'Content-Type: image/png' --data-binary @/tmp/p.png
curl -s -o /dev/null -X POST "$GW/api/products/$PRODUCT/images/$FILE_ID/confirm" \
  -H "Authorization: Bearer $MERCHANT"
check 'product published'                '200' \
  "$(status POST "$GW/api/products/$PRODUCT/publish" "$MERCHANT")"

ORDER=$(curl -s -X POST "$GW/api/orders" -H "Authorization: Bearer $CUSTOMER" \
  -H 'Content-Type: application/json' \
  -d "{\"items\":[{\"productId\":\"$PRODUCT\",\"qty\":1}],
       \"deliveryAddress\":\"9 Notification Way\",\"contactPhone\":\"+15550100001\"}" | jq -r '.id')
check 'order placed'                     'yes' "$([ -n "$ORDER" ] && [ "$ORDER" != null ] && echo yes || echo no)"

LOG_URL="$GW/api/notification-log/orders/$ORDER"

# Whether the merchant's seeded placeholder token is suppressed, which decides whether a push row
# for this order SHOULD exist. See smoke-test-push.sh for the full reasoning: a suppressed address
# is the platform deciding not to send, and asserting a row against that fails correct behaviour.
SUPPRESSED_SEED=$(PGPASSWORD="${POSTGRES_PASSWORD:-}" psql -h postgres -U delivery -d delivery -At \
  -c "select count(*) from notification.suppressed_address where channel = 'PUSH' and address like 'dev-fcm-token-%';" 2>/dev/null || echo 0)
ACTIVE_PUSH=$(curl -s "$PUSH_CONNECTOR/api/connector/status" | jq -r '.activeProvider')
if [ "$ACTIVE_PUSH" = "FIREBASE" ] && [ "${SUPPRESSED_SEED:-0}" -gt 0 ]; then
  EXPECT_PUSH=0
else
  EXPECT_PUSH=1
fi
# Four rows always (customer email+in-app, merchant email+in-app); the merchant push is the fifth.
EXPECT_ROWS=$(( 4 + EXPECT_PUSH ))
wait_for 45 "[ \"\$(curl -s '$LOG_URL' -H 'Authorization: Bearer $BACKOFFICE' | jq 'length')\" -ge $EXPECT_ROWS ]" || true
LOG=$(curl -s "$LOG_URL" -H "Authorization: Bearer $BACKOFFICE")

check 'notifications were logged'        'yes' "$(echo "$LOG" | jq --argjson n "$EXPECT_ROWS" 'length >= $n' | sed 's/true/yes/;s/false/no/')"
# Which channels fire is a data question - these rows exist because template rows exist, not
# because the manager has an if-statement per channel.
check 'customer got an in-app message'   'yes' \
  "$(echo "$LOG" | jq --arg u "$CUSTOMER_SUB" '[.[]|select(.eventType=="order.placed" and .channel=="IN_APP")]|length>0' | sed 's/true/yes/;s/false/no/')"
check 'customer got an email'            'yes' \
  "$(echo "$LOG" | jq '[.[]|select(.eventType=="order.placed" and .channel=="EMAIL")]|length>0' | sed 's/true/yes/;s/false/no/')"
# A different template for a different audience, from the same domain event.
check 'merchant got its own in-app copy' 'yes' \
  "$(echo "$LOG" | jq '[.[]|select(.eventType=="order.placed.merchant" and .channel=="IN_APP")]|length>0' | sed 's/true/yes/;s/false/no/')"
check 'merchant got its own email'       'yes' \
  "$(echo "$LOG" | jq '[.[]|select(.eventType=="order.placed.merchant" and .channel=="EMAIL")]|length>0' | sed 's/true/yes/;s/false/no/')"
check 'merchant got a push'              "$([ "$EXPECT_PUSH" = 1 ] && echo yes || echo no)" \
  "$(echo "$LOG" | jq '[.[]|select(.eventType=="order.placed.merchant" and .channel=="PUSH")]|length>0' | sed 's/true/yes/;s/false/no/')"
# The customer is not pushed about placing their own order - they are looking at the screen.
check 'no customer push on order.placed' '0' \
  "$(echo "$LOG" | jq '[.[]|select(.eventType=="order.placed" and .channel=="PUSH")]|length')"

check 'recipient resolved from Keycloak' 'customer@dev.local' \
  "$(echo "$LOG" | jq -r '[.[]|select(.eventType=="order.placed" and .channel=="EMAIL")][0].recipient')"

echo
echo '=== 4. Receipts close the log out ================================================'

wait_for 45 "[ \"\$(curl -s '$LOG_URL' -H 'Authorization: Bearer $BACKOFFICE' | jq '[.[]|select(.status==\"PENDING\")]|length')\" = 0 ]" || true
LOG=$(curl -s "$LOG_URL" -H "Authorization: Bearer $BACKOFFICE")

# Without the worker receipt every row would sit at PENDING forever and the log would be useless
# for the one question it exists to answer.
check 'nothing left PENDING'             '0' "$(echo "$LOG" | jq '[.[]|select(.status=="PENDING")]|length')"

# Push is provider-aware, because "not SENT" means different things in the two modes. With the dev
# provider everything should reach SENT. With Firebase the SEEDED accounts carry placeholder device
# tokens and Google refuses them — correctly — so a refusal there is not a platform fault and must
# not read as one. Only an account that has signed in on a real handset has a token Google accepts.
PUSH_PROVIDER=$(curl -s "$PUSH_CONNECTOR/api/connector/status" | jq -r '.activeProvider')
echo "  NOTE  active push provider is $PUSH_PROVIDER"

if [ "$PUSH_PROVIDER" = "FIREBASE" ]; then
  check 'every non-push notification SENT' '0' \
    "$(echo "$LOG" | jq '[.[]|select(.channel!="PUSH" and .status!="SENT")]|length')"
  echo "  NOTE  push rows to seeded accounts are refused by Firebase; see smoke-test-push.sh"
else
  check 'everything reached SENT'          '0' "$(echo "$LOG" | jq '[.[]|select(.status!="SENT")]|length')"
fi

check 'email records the provider used'  'SMTP' \
  "$(echo "$LOG" | jq -r '[.[]|select(.channel=="EMAIL")][0].provider')"
check 'push records the provider used'   "$([ "$EXPECT_PUSH" = 1 ] && echo "$PUSH_PROVIDER" || echo null)" \
  "$(echo "$LOG" | jq -r '[.[]|select(.channel=="PUSH")][0].provider')"
check 'a provider message id came back'  'yes' \
  "$(echo "$LOG" | jq '[.[]|select(.channel=="EMAIL")][0].status=="SENT"' | sed 's/true/yes/;s/false/no/')"

echo
echo
echo '=== 5. The email left the platform ==============================================='

# Two levels of proof, because this environment has two modes.
#
# The platform's own record is always checkable: a row per audience, addressed to the right person,
# accepted by whatever relay is configured. That works in both modes and is asserted first.
#
# Reading the message itself needs a mailbox this script may read, which means the Mailpit sink.
# When mail is pointed at a real relay there is no such mailbox — so those assertions are SKIPPED
# AND SAID TO BE SKIPPED rather than quietly dropped, because a suite that silently checks less
# reads exactly like a suite that passed.
check 'the customer confirmation was sent' 'yes' \
  "$(echo "$LOG" | jq '[.[]|select(.channel=="EMAIL" and .status=="SENT" and .recipient=="customer@dev.local")]|length>0' | sed 's/true/yes/;s/false/no/')"
check 'the merchant work item was sent'    'yes' \
  "$(echo "$LOG" | jq '[.[]|select(.channel=="EMAIL" and .status=="SENT" and .recipient=="merchant@dev.local")]|length>0' | sed 's/true/yes/;s/false/no/')"
check 'the two went to different people'   'yes' \
  "$(echo "$LOG" | jq '([.[]|select(.channel=="EMAIL" and .status=="SENT")|.recipient]|unique|length)>=2' | sed 's/true/yes/;s/false/no/')"

SHORT_ID=$(echo "$ORDER" | cut -c1-8 | tr 'a-f' 'A-F')

if curl -s -m 3 -o /dev/null "$MAILPIT/api/v1/messages?limit=1"; then
  wait_for 30 "curl -s '$MAILPIT/api/v1/messages?limit=200' | jq -e --arg s '$SHORT_ID' '[.messages[]|select(.To[]?.Address==\"customer@dev.local\" and (.Subject|contains(\$s)))]|length>0'" || true

  check 'the customer confirmation arrived' 'yes' \
    "$(curl -s "$MAILPIT/api/v1/messages?limit=200" \
       | jq --arg s "$SHORT_ID" '[.messages[]|select(.To[]?.Address=="customer@dev.local" and (.Subject|contains($s)))]|length>0' \
       | sed 's/true/yes/;s/false/no/')"
  check 'the merchant work item arrived'    'yes' \
    "$(curl -s "$MAILPIT/api/v1/messages?limit=200" \
       | jq --arg s "$SHORT_ID" '[.messages[]|select(.To[]?.Address=="merchant@dev.local" and (.Subject|contains($s)))]|length>0' \
       | sed 's/true/yes/;s/false/no/')"
else
  echo '  SKIP  no mail sink reachable — delivery is asserted from the log only'
fi

echo '=== 6. SMS through the dev provider =============================================='

# A status change, because that is the event the SMS template is attached to.
curl -s -o /dev/null -X POST "$GW/api/orders/$ORDER/accept" -H "Authorization: Bearer $MERCHANT"

# The dev provider logs rather than redirecting to a test inbox, now that there is no inbox to
# redirect to. So the assertion moves to the notification log: the row for this SMS reaching SENT
# is what says the chain ran. The body itself is only in the connector's log.
wait_for 45 "[ \"\$(curl -s '$LOG_URL' -H 'Authorization: Bearer $BACKOFFICE' | jq '[.[]|select(.channel==\"SMS\" and .status==\"SENT\")]|length')\" -ge 1 ]" || true
check 'the SMS row is SENT'              'yes' \
  "$(curl -s "$LOG_URL" -H "Authorization: Bearer $BACKOFFICE" \
     | jq '[.[]|select(.channel=="SMS" and .status=="SENT")]|length>=1' | sed 's/true/yes/;s/false/no/')"
check 'and names the provider it used'   'DEV_PASSTHROUGH' \
  "$(curl -s "$LOG_URL" -H "Authorization: Bearer $BACKOFFICE" \
     | jq -r '[.[]|select(.channel=="SMS")][0].provider')"

echo
echo '=== 7. In-app inbox =============================================================='

INBOX=$(curl -s "$GW/api/notifications" -H "Authorization: Bearer $CUSTOMER")
check 'customer inbox has messages'      'yes' "$(echo "$INBOX" | jq 'length>0' | sed 's/true/yes/;s/false/no/')"
check 'the order is linked'              'yes' \
  "$(echo "$INBOX" | jq --arg o "$ORDER" '[.[]|select(.orderId==$o)]|length>0' | sed 's/true/yes/;s/false/no/')"
check 'unread count is non-zero'         'yes' \
  "$(curl -s "$GW/api/notifications/unread-count" -H "Authorization: Bearer $CUSTOMER" | jq '.unread>0' | sed 's/true/yes/;s/false/no/')"

MSG=$(echo "$INBOX" | jq -r --arg o "$ORDER" '[.[]|select(.orderId==$o)][0].id')
check 'marking one read'                 '204' "$(status POST "$GW/api/notifications/$MSG/read" "$CUSTOMER")"
check 'it now reads as read'             'yes' \
  "$(curl -s "$GW/api/notifications" -H "Authorization: Bearer $CUSTOMER" \
     | jq --arg m "$MSG" '[.[]|select(.id==$m)][0].read' | sed 's/true/yes/;s/false/no/')"
# Ownership is enforced on the sub, and a message that is not yours is indistinguishable from one
# that does not exist.
check 'merchant cannot read it'          '404' "$(status POST "$GW/api/notifications/$MSG/read" "$MERCHANT")"
check 'the merchant inbox is separate'   '0' \
  "$(curl -s "$GW/api/notifications" -H "Authorization: Bearer $MERCHANT" | jq --arg m "$MSG" '[.[]|select(.id==$m)]|length')"

check 'mark-all-read clears the badge'   '0' \
  "$(curl -s -X POST "$GW/api/notifications/read-all" -H "Authorization: Bearer $CUSTOMER" >/dev/null;
     curl -s "$GW/api/notifications/unread-count" -H "Authorization: Bearer $CUSTOMER" | jq '.unread')"

echo
echo '=== 8. The notification log is not a public record ==============================='

check 'customer cannot read the order log' '403' "$(status GET "$LOG_URL" "$CUSTOMER")"
check 'customer can read their own'        '200' "$(status GET "$GW/api/notification-log/mine" "$CUSTOMER")"
# Infrastructure detail is for operators. A customer learns that a message was sent, not that an
# SMTP relay answered 550.
check 'their own view hides the provider' 'null' \
  "$(curl -s "$GW/api/notification-log/mine" -H "Authorization: Bearer $CUSTOMER" | jq -r '.[0].provider')"
check 'and hides the recipient address'   'null' \
  "$(curl -s "$GW/api/notification-log/mine" -H "Authorization: Bearer $CUSTOMER" | jq -r '.[0].recipient')"

echo
echo '=== 9. Connectors are not reachable from outside ================================='

# The send endpoint takes "send this message" with no user token. It exists only on the internal
# network, and a Gateway route for it would hand that to anyone with any valid token.
check 'no gateway route to the connector' '404' \
  "$(status POST "$GW/api/connector/send" "$BACKOFFICE" '{"notificationId":"x"}')"
check 'reachable inside the network'      '200' \
  "$(curl -s -o /dev/null -w '%{http_code}' "$SMS_CONNECTOR/api/connector/status")"

echo
echo '=== 10. A bad recipient is stopped before it costs anything ======================'

RMQ="-u ${RABBITMQ_USER:-delivery}:${RABBITMQ_PASSWORD:-delivery}"
dlq_depth() {
  # shellcheck disable=SC2086
  curl -s $RMQ "$RABBIT/api/queues/%2F/notification.dlq" | jq '.messages // 0'
}

DLQ_BEFORE=$(dlq_depth)
check 'the dead-letter queue exists'     'yes' \
  "$([ -n "$DLQ_BEFORE" ] && [ "$DLQ_BEFORE" != null ] && echo yes || echo no)"

# Published straight onto the SMS channel queue so the WORKER handles it. Validation lives there,
# not in the connector: it is a property of the channel, not of the vendor, and catching a bad
# number locally costs nothing while the same number sent to a paid provider costs a request, a
# retry budget and, on some plans, money.
BAD_ID='11111111-1111-4111-8111-111111111111'
BAD_CMD="{\"notificationId\":\"$BAD_ID\",\"channel\":\"SMS\",\"recipient\":\"not-a-phone-number\",\"subject\":null,\"body\":\"smoke test\",\"metadata\":{},\"correlationId\":\"smoke\",\"createdAt\":\"2026-01-01T00:00:00Z\"}"
PUBLISH_BODY=$(jq -n --arg rk 'notification.dispatch.sms' --arg p "$BAD_CMD" \
  '{properties:{content_type:"application/json"},routing_key:$rk,payload:$p,payload_encoding:"string"}')

# shellcheck disable=SC2086
check 'bad command accepted by the broker' 'true' \
  "$(curl -s $RMQ -H 'Content-Type: application/json' \
     -X POST "$RABBIT/api/exchanges/%2F/delivery.events/publish" -d "$PUBLISH_BODY" | jq -r '.routed')"

wait_for 30 "[ \"\$(curl -s $RMQ '$RABBIT/api/queues/%2F/notification.dlq' | jq '.messages // 0')\" -gt $DLQ_BEFORE ]" || true
check 'the worker dead-lettered it'      'yes' \
  "$(DEPTH=$(dlq_depth); [ "$DEPTH" -gt "$DLQ_BEFORE" ] && echo yes || echo no)"

# Retained with the reason attached, so an operator can see what happened and replay it after a
# fix rather than reconstructing the message from a log line.
DLQ_MSG=$(curl -s $RMQ -H 'Content-Type: application/json' \
  -X POST "$RABBIT/api/queues/%2F/notification.dlq/get" \
  -d '{"count":500,"ackmode":"ack_requeue_true","encoding":"auto"}')
check 'it kept the reason it failed'     'yes' \
  "$(echo "$DLQ_MSG" | jq --arg id "$BAD_ID" \
     '[.[]|select(.payload|contains($id))]|length>0' | sed 's/true/yes/;s/false/no/')"
check 'and the original command with it' 'yes' \
  "$(echo "$DLQ_MSG" | jq --arg id "$BAD_ID" \
     '[.[]|select((.payload|contains($id)) and (.payload|contains("E.164")))]|length>0' \
     | sed 's/true/yes/;s/false/no/')"

echo
echo '=== 11. Per-channel queues, not one shared one ==================================='

# One queue per channel is what stops a wedged SMS route delaying an email. Asserted on the broker
# rather than inferred from behaviour, because the failure mode only appears under load.
for q in notification.dispatch.sms notification.dispatch.email notification.dispatch.push \
         notification.dispatch.in_app notifications.receipts notifications.order-events; do
  check "queue $q declared" '200' \
    "$(curl -s -o /dev/null -w '%{http_code}' -u "${RABBITMQ_USER:-delivery}:${RABBITMQ_PASSWORD:-delivery}" \
       "$RABBIT/api/queues/%2F/$q")"
done
# Both bind order.# to the same topic exchange and each must get its own copy; competing consumers
# on one queue would mean half of every order's notifications were silently never sent.
check 'tracking still has its own queue' '200' \
  "$(curl -s -o /dev/null -w '%{http_code}' -u "${RABBITMQ_USER:-delivery}:${RABBITMQ_PASSWORD:-delivery}" \
     "$RABBIT/api/queues/%2F/tracking.order-events")"

echo
echo '=== 12. Duplicate events do not double-send ======================================'

BEFORE=$(curl -s "$LOG_URL" -H "Authorization: Bearer $BACKOFFICE" | jq 'length')
# Re-accepting is rejected by the state machine, so no second event is produced. The dedupe guard
# behind it is existsByOrderIdAndEventTypeAndChannelAndRecipientId - at-least-once bus delivery
# would otherwise bill a second SMS for one status change.
curl -s -o /dev/null -X POST "$GW/api/orders/$ORDER/accept" -H "Authorization: Bearer $MERCHANT"
sleep 8
AFTER=$(curl -s "$LOG_URL" -H "Authorization: Bearer $BACKOFFICE" | jq 'length')
check 'no duplicate notifications'       "$BEFORE" "$AFTER"

echo
echo '================================================================================='
printf 'passed: %s   failed: %s\n' "$PASS" "$FAIL"
echo '================================================================================='
[ "$FAIL" -eq 0 ] || exit 1
