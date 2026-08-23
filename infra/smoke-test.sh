#!/bin/sh
# Phase 1 end-to-end smoke test, run from inside the compose network.
#
#   cd infra && ./smoke-test.ps1        (Windows)
#   docker run --rm --network delivery -v "$PWD/smoke-test.sh:/smoke.sh:ro" alpine:latest \
#     sh -c "apk add --no-cache curl jq >/dev/null && sh /smoke.sh"
#
# Every call goes through the API Gateway with a real Keycloak token — nothing here talks to a
# service directly, so the test exercises routing, JWT validation and rate limiting as well as the
# catalog itself.

set -eu

GW="http://traefik:8100"
KC="http://keycloak:8080/realms/delivery-platform/protocol/openid-connect/token"
KC_ADMIN="http://keycloak:8080"

PASS=0
FAIL=0

check() { # check <description> <expected> <actual>
  if [ "$2" = "$3" ]; then
    printf '  \033[32mPASS\033[0m  %-58s %s\n' "$1" "$3"
    PASS=$((PASS + 1))
  else
    printf '  \033[31mFAIL\033[0m  %-58s expected %s, got %s\n' "$1" "$2" "$3"
    FAIL=$((FAIL + 1))
  fi
}

token() { # token <username> <password> [client]
  curl -s -X POST "$KC" \
    -d "client_id=${3:-delivery-portal}" -d "username=$1" -d "password=$2" \
    -d "grant_type=password" | jq -r '.access_token'
}

# Reads a claim out of a JWT payload.
#
# The padding dance is load-bearing: JWT segments are base64url with padding stripped, and busybox
# `base64 -d` returns empty for an unpadded input instead of erroring. Without this, every claim
# read silently yields "" and assertions compare "" to "" and pass — which is exactly how a missing
# `sub` claim slipped through the first run of this script.
claim() { # claim <jwt> <jq-filter>
  p=$(echo "$1" | cut -d. -f2 | tr '_-' '/+')
  case $(( ${#p} % 4 )) in
    2) p="$p==" ;;
    3) p="$p=" ;;
  esac
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
echo '=== 1. Authentication ==========================================================='

MERCHANT=$(token merchant merchant)
CUSTOMER=$(token customer customer mobile-app)
BACKOFFICE=$(token backoffice backoffice delivery-portal)

[ -n "$MERCHANT" ] && [ "$MERCHANT" != null ] || { echo 'Could not obtain a merchant token'; exit 1; }

MERCHANT_SUB=$(claim "$MERCHANT" '.sub')

check 'merchant token carries MERCHANT role'  'MERCHANT'   "$(claim "$MERCHANT" '.realm_access.roles[]' | grep -x MERCHANT || echo none)"
# Guards the Keycloak `basic` client scope: without it tokens authenticate and carry roles but have
# no `sub`, and every ownership check below fails for a reason that looks nothing like the cause.
check 'merchant token carries a sub claim'    'yes'        "$([ -n "$MERCHANT_SUB" ] && [ "$MERCHANT_SUB" != null ] && echo yes || echo no)"
check 'unauthenticated request rejected'      '401'        "$(curl -s -o /dev/null -w '%{http_code}' "$GW/api/products")"
check 'garbage token rejected'                '401'        "$(status GET /api/products not-a-token)"

echo
echo '=== 2. Second merchant (for the ownership test) ================================='

# The realm ships one merchant. Cross-merchant isolation is the security property that matters most
# in this phase, so a second one is created here via the admin API rather than assumed.
ADMIN=$(curl -s -X POST "$KC_ADMIN/realms/master/protocol/openid-connect/token" \
  -d 'client_id=admin-cli' -d 'grant_type=password' -d "username=${KEYCLOAK_ADMIN:-admin}" -d "password=${KEYCLOAK_ADMIN_PASSWORD:-admin}" | jq -r '.access_token')

[ -n "$ADMIN" ] && [ "$ADMIN" != null ] || { echo 'Could not obtain a Keycloak admin token'; exit 1; }

# firstName and lastName are NOT optional here. Keycloak's user-profile feature evaluates
# VERIFY_PROFILE dynamically at login when they are missing, and the token request then fails with
# "Account is not fully set up" — while the user record still shows an empty requiredActions array,
# which makes it look like a password problem instead.
CREATE_USER=$(curl -s -o /dev/null -w '%{http_code}' -X POST \
  "$KC_ADMIN/admin/realms/delivery-platform/users" \
  -H "Authorization: Bearer $ADMIN" -H 'Content-Type: application/json' \
  -d '{"username":"merchant2","email":"merchant2@dev.local","firstName":"Max","lastName":"Merchant",
       "enabled":true,"emailVerified":true}')
case "$CREATE_USER" in
  201|409) : ;;
  *) echo "  note: creating merchant2 returned $CREATE_USER" ;;
esac

M2_ID=$(curl -s "$KC_ADMIN/admin/realms/delivery-platform/users?username=merchant2&exact=true" \
  -H "Authorization: Bearer $ADMIN" | jq -r '.[0].id')

# Set the password through reset-password rather than the `credentials` array on create: the array
# is silently ignored often enough that it is not worth relying on.
curl -s -o /dev/null -X PUT \
  "$KC_ADMIN/admin/realms/delivery-platform/users/$M2_ID/reset-password" \
  -H "Authorization: Bearer $ADMIN" -H 'Content-Type: application/json' \
  -d '{"type":"password","value":"merchant2","temporary":false}'

ROLE=$(curl -s "$KC_ADMIN/admin/realms/delivery-platform/roles/MERCHANT" \
  -H "Authorization: Bearer $ADMIN" | jq -c '{id,name}')
curl -s -o /dev/null -X POST \
  "$KC_ADMIN/admin/realms/delivery-platform/users/$M2_ID/role-mappings/realm" \
  -H "Authorization: Bearer $ADMIN" -H 'Content-Type: application/json' -d "[$ROLE]"

MERCHANT2=$(token merchant2 merchant2)
check 'second merchant provisioned'           'MERCHANT'   "$(claim "$MERCHANT2" '.realm_access.roles[]' | grep -x MERCHANT || echo none)"

echo
echo '=== 3. Categories ==============================================================='

CATS=$(curl -s "$GW/api/categories" -H "Authorization: Bearer $CUSTOMER")
# Assert the seeded roots are present rather than an exact count: this script is re-runnable, and
# the create below adds a category that survives into the next run.
check 'seeded root categories present'        '3'          "$(echo "$CATS" | jq '[.[] | select(.name=="Food" or .name=="Groceries" or .name=="Pharmacy")] | length')"
check 'Food has two children'                 '2'          "$(echo "$CATS" | jq '[.[] | select(.name=="Food")][0].children | length')"
check 'merchant cannot create a category'     '403'        "$(status POST /api/categories "$MERCHANT" '{"name":"Hacked"}')"
# 201 first run, 409 on re-run — a duplicate must be a conflict, never a 500.
check 'backoffice can create a category'      'ok'         "$(case "$(status POST /api/categories "$BACKOFFICE" '{"name":"Beverages"}')" in 201|409) echo ok ;; *) status POST /api/categories "$BACKOFFICE" '{"name":"Beverages"}' ;; esac)"

FOOD=$(echo "$CATS" | jq -r '[.[] | select(.name=="Food")][0].id')

echo
echo '=== 4. Product creation and ownership ==========================================='

check 'customer cannot create a product'      '403'        "$(status POST /api/products "$CUSTOMER" '{"name":"X","price":1.00}')"
check 'price must be positive'                '400'        "$(status POST /api/products "$MERCHANT" '{"name":"Free lunch","price":0}')"
check 'name is required'                      '400'        "$(status POST /api/products "$MERCHANT" '{"price":5.00}')"

CREATED=$(curl -s -X POST "$GW/api/products" -H "Authorization: Bearer $MERCHANT" \
  -H 'Content-Type: application/json' \
  -d "{\"name\":\"Margherita Pizza\",\"description\":\"Tomato, mozzarella, basil\",\"price\":12.50,\"categoryId\":\"$FOOD\"}")
PRODUCT=$(echo "$CREATED" | jq -r '.id')

check 'product created'                       'DRAFT'      "$(echo "$CREATED" | jq -r '.status')"
check 'merchantId taken from the token'       "$MERCHANT_SUB" "$(echo "$CREATED" | jq -r '.merchantId')"
check 'owner can read own draft'              '200'        "$(status GET "/api/products/$PRODUCT" "$MERCHANT")"
check 'other merchant cannot read the draft'  '404'        "$(status GET "/api/products/$PRODUCT" "$MERCHANT2")"
check 'customer cannot read the draft'        '404'        "$(status GET "/api/products/$PRODUCT" "$CUSTOMER")"
check 'other merchant cannot edit it'         '404'        "$(status PUT "/api/products/$PRODUCT" "$MERCHANT2" '{"name":"Stolen","price":1.00}')"
check 'other merchant cannot archive it'      '404'        "$(status DELETE "/api/products/$PRODUCT" "$MERCHANT2")"
check 'draft is not in the public catalog'    '0'          "$(curl -s "$GW/api/products" -H "Authorization: Bearer $CUSTOMER" | jq '[.content[] | select(.id=="'"$PRODUCT"'")] | length')"

echo
echo '=== 5. Image upload (presign -> PUT -> confirm) =================================='

check 'cannot publish without an image'       '422'        "$(status POST "/api/products/$PRODUCT/publish" "$MERCHANT")"
check 'disallowed content type refused'       '422'        "$(status POST "/api/products/$PRODUCT/images/presign" "$MERCHANT" '{"contentType":"application/x-msdownload"}')"
check 'other merchant cannot presign'         '404'        "$(status POST "/api/products/$PRODUCT/images/presign" "$MERCHANT2" '{"contentType":"image/png"}')"

PRESIGN=$(curl -s -X POST "$GW/api/products/$PRODUCT/images/presign" \
  -H "Authorization: Bearer $MERCHANT" -H 'Content-Type: application/json' \
  -d '{"contentType":"image/png"}')
FILE_ID=$(echo "$PRESIGN" | jq -r '.fileId')
UPLOAD_URL=$(echo "$PRESIGN" | jq -r '.uploadUrl')
OBJECT_KEY=$(echo "$PRESIGN" | jq -r '.objectKey')

check 'presigned URL issued'                  'yes'        "$([ -n "$UPLOAD_URL" ] && [ "$UPLOAD_URL" != null ] && echo yes || echo no)"
check 'object key namespaced by product'      'yes'        "$(echo "$OBJECT_KEY" | grep -q "^products/$PRODUCT/" && echo yes || echo no)"

# Smallest valid PNG (1x1, transparent).
printf '\211PNG\r\n\032\n\0\0\0\rIHDR\0\0\0\1\0\0\0\1\10\6\0\0\0\37\25\304\211\0\0\0\nIDATx\234c\370\17\0\1\1\1\0\30\335\215\260\0\0\0\0IEND\256B`\202' > /tmp/pixel.png

# The URL is used EXACTLY as issued — signed for whatever MINIO_PUBLIC_ENDPOINT is set to, which is
# the endpoint a browser or device would use. From inside the compose network that host is not
# reachable, so --connect-to redirects the TCP connection to minio:9000 while leaving the Host
# header intact. Rewriting the URL itself would change the Host header, and since SigV4 signs it
# (X-Amz-SignedHeaders=host), MinIO rejects the request with 403 SignatureDoesNotMatch — which is
# the same failure a misconfigured public-endpoint produces in production, so a test that rewrote
# the URL would hide exactly the bug it should catch.
#
# The mapping is derived from the URL rather than hardcoded, so changing MINIO_PUBLIC_ENDPOINT in
# infra/.env (as physical-device testing requires) does not silently break this test.
UPLOAD_HOSTPORT=$(echo "$UPLOAD_URL" | sed -E 's|^https?://([^/]+)/.*|\1|')
case "$UPLOAD_HOSTPORT" in
  *:*) : ;;
  *) UPLOAD_HOSTPORT="$UPLOAD_HOSTPORT:80" ;;
esac

UPLOAD_CODE=$(curl -s -o /dev/null -w '%{http_code}' \
  --connect-to "$UPLOAD_HOSTPORT:minio:9000" \
  -X PUT "$UPLOAD_URL" -H 'Content-Type: image/png' --data-binary @/tmp/pixel.png)
check 'client PUT straight to MinIO'          '200'        "$UPLOAD_CODE"

check 'other merchant cannot confirm'         '404'        "$(status POST "/api/products/$PRODUCT/images/$FILE_ID/confirm" "$MERCHANT2")"
check 'owner confirms the upload'             '204'        "$(status POST "/api/products/$PRODUCT/images/$FILE_ID/confirm" "$MERCHANT")"

WITH_IMAGE=$(curl -s "$GW/api/products/$PRODUCT" -H "Authorization: Bearer $MERCHANT")
check 'image attached to the product'         '1'          "$(echo "$WITH_IMAGE" | jq '.imageRefs | length')"
check 'readable image URL returned'           '1'          "$(echo "$WITH_IMAGE" | jq '.imageUrls | length')"

echo
echo '=== 6. Publish and browse ======================================================='

check 'publish succeeds once imaged'          '200'        "$(status POST "/api/products/$PRODUCT/publish" "$MERCHANT")"
check 'now visible to customers'              '1'          "$(curl -s "$GW/api/products" -H "Authorization: Bearer $CUSTOMER" | jq '[.content[] | select(.id=="'"$PRODUCT"'")] | length')"
check 'search finds it'                       '1'          "$(curl -s "$GW/api/products?search=margherita" -H "Authorization: Bearer $CUSTOMER" | jq '[.content[] | select(.id=="'"$PRODUCT"'")] | length')"
check 'category filter works'                 '1'          "$(curl -s "$GW/api/products?categoryId=$FOOD" -H "Authorization: Bearer $CUSTOMER" | jq '[.content[] | select(.id=="'"$PRODUCT"'")] | length')"
check 'other merchant sees nothing of theirs' '0'          "$(curl -s "$GW/api/products/mine" -H "Authorization: Bearer $MERCHANT2" | jq '.totalElements')"
check 'owner sees it in their own list'       '1'          "$(curl -s "$GW/api/products/mine" -H "Authorization: Bearer $MERCHANT" | jq '[.content[] | select(.id=="'"$PRODUCT"'")] | length')"

echo
echo '=== 7. Archive =================================================================='

check 'owner archives the product'            '200'        "$(status DELETE "/api/products/$PRODUCT" "$MERCHANT")"
check 'archived product leaves the catalog'   '0'          "$(curl -s "$GW/api/products" -H "Authorization: Bearer $CUSTOMER" | jq '[.content[] | select(.id=="'"$PRODUCT"'")] | length')"
check 'archived product still readable by owner' '200'     "$(status GET "/api/products/$PRODUCT" "$MERCHANT")"

echo
echo '================================================================================='
printf 'passed: %s   failed: %s\n' "$PASS" "$FAIL"
echo '================================================================================='
[ "$FAIL" -eq 0 ] || exit 1
