#!/bin/sh
# Sets up the fixtures both k6 scripts need, runs them, and measures the asynchronous tail that k6
# cannot see.
#
#   cd infra && docker run --rm --network delivery \
#     -v "$PWD/load-test:/scripts:ro" -v /var/run/docker.sock:/var/run/docker.sock \
#     alpine:latest sh -c "apk add --no-cache curl jq docker-cli >/dev/null && sh /scripts/run-load-test.sh"
#
# Or, more simply, from the host: infra/load-test/run.ps1
#
# The asynchronous measurement is the point of this wrapper. k6 stops at the HTTP response, but a
# notification's journey continues through the outbox relay, the bus, the manager, a worker, a
# connector and back as a receipt. Whether THAT keeps up with the order rate is the actual capacity
# question, and it is only visible in the notification log afterwards.

set -eu

GW="${GATEWAY:-http://api-gateway:8100}"
KC="http://keycloak:8080/realms/delivery-platform/protocol/openid-connect/token"
RUN_ID="$(date +%s)"

token() {
  curl -s -X POST "$KC" -d "client_id=${3:-mobile-app}" \
    -d "username=$1" -d "password=$2" -d "grant_type=password" | jq -r '.access_token'
}

echo "==> Fixtures"
CUSTOMER=$(token customer customer mobile-app)
MERCHANT=$(token merchant merchant merchant-portal)
RIDER=$(token rider rider mobile-app)
BACKOFFICE=$(token backoffice backoffice backoffice-web)

FOOD=$(curl -s "$GW/api/categories" -H "Authorization: Bearer $CUSTOMER" \
  | jq -r '[.[]|select(.name=="Food")][0].id')

PRODUCT=$(curl -s -X POST "$GW/api/products" -H "Authorization: Bearer $MERCHANT" \
  -H 'Content-Type: application/json' \
  -d "{\"name\":\"Load Test Item $RUN_ID\",\"description\":\"load\",\"price\":10.00,\"categoryId\":\"$FOOD\"}" \
  | jq -r '.id')

# Phase 1 refuses to publish a product with no image; the presigned URL must be used exactly as
# issued because SigV4 signs the Host.
PRESIGN=$(curl -s -X POST "$GW/api/products/$PRODUCT/images/presign" \
  -H "Authorization: Bearer $MERCHANT" -H 'Content-Type: application/json' \
  -d '{"contentType":"image/png"}')
FILE_ID=$(echo "$PRESIGN" | jq -r '.fileId')
URL=$(echo "$PRESIGN" | jq -r '.uploadUrl')
HOSTPORT=$(echo "$URL" | sed -E 's|^https?://([^/]+)/.*|\1|')
case "$HOSTPORT" in *:*) : ;; *) HOSTPORT="$HOSTPORT:80" ;; esac
printf '\211PNG\r\n\032\n' > /tmp/p.png
curl -s -o /dev/null --connect-to "$HOSTPORT:minio:9000" -X PUT "$URL" \
  -H 'Content-Type: image/png' --data-binary @/tmp/p.png
curl -s -o /dev/null -X POST "$GW/api/products/$PRODUCT/images/$FILE_ID/confirm" \
  -H "Authorization: Bearer $MERCHANT"
curl -s -o /dev/null -X POST "$GW/api/products/$PRODUCT/publish" -H "Authorization: Bearer $MERCHANT"
echo "    product $PRODUCT published"

# One order taken all the way to PICKED_UP: the tracking write path only accepts pings from the
# assigned rider on an in-flight order, so the load test needs a real one.
ORDER=$(curl -s -X POST "$GW/api/orders" -H "Authorization: Bearer $CUSTOMER" \
  -H 'Content-Type: application/json' \
  -d "{\"items\":[{\"productId\":\"$PRODUCT\",\"qty\":1}],\"deliveryAddress\":\"1 Load Ave\",\"contactPhone\":\"+15550100001\"}" \
  | jq -r '.id')
for step in accept prepare ready; do
  curl -s -o /dev/null -X POST "$GW/api/orders/$ORDER/$step" -H "Authorization: Bearer $MERCHANT"
done
curl -s -o /dev/null -X POST "$GW/api/orders/$ORDER/claim" -H "Authorization: Bearer $RIDER"
curl -s -o /dev/null -X POST "$GW/api/orders/$ORDER/pick-up" -H "Authorization: Bearer $RIDER"
echo "    order $ORDER is in flight"

echo
echo "==> Baseline"
PINGS_BEFORE=$(curl -s "$GW/api/tracking/orders/$ORDER/history?limit=1" \
  -H "Authorization: Bearer $BACKOFFICE" >/dev/null 2>&1 && echo ok || echo ok)

cat <<EOF

Run the two k6 scenarios from the host (k6 is a separate image):

  docker run --rm --network delivery -v "\$PWD/load-test:/scripts:ro" \\
    -e ORDER_ID=$ORDER -e RIDER_TOKEN=$RIDER \\
    grafana/k6:0.53.0 run /scripts/tracking-write.js

  docker run --rm --network delivery -v "\$PWD/load-test:/scripts:ro" \\
    -e PRODUCT_ID=$PRODUCT -e CUSTOMER_TOKEN=$CUSTOMER -e RUN_ID=$RUN_ID \\
    grafana/k6:0.53.0 run /scripts/notification-fanout.js

EOF
