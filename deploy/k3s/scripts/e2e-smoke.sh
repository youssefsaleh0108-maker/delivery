#!/bin/sh
# End-to-end smoke over one deployed environment, from OUTSIDE — the same doors the apps use.
#
#   sh e2e-smoke.sh dev [--with-email you@example.com]
#
# Every demo role signs in against the environment's own Keycloak, then exercises its surface:
# the customer browses and PLACES A REAL CASH ORDER, the merchant sees their queue, the rider the
# job board, backoffice the applications, the carrier their company, and the money and points
# services answer. Pass --with-email to also push one real verification code through the mail
# relay (it sends an actual email, so it is opt-in).
set -u

ENV="${1:?usage: e2e-smoke.sh <dev|qa> [--with-email addr]}"
API="https://api-$ENV.youdrop.shop"
IAM="https://iam-$ENV.youdrop.shop"
MAIL_TO=""
[ "${2:-}" = "--with-email" ] && MAIL_TO="${3:?--with-email needs an address}"

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf "  ok   %s\n" "$1"; }
bad()  { FAIL=$((FAIL+1)); printf "  FAIL %s -- %s\n" "$1" "$2"; }

tok() { # tok <user> <pass>
  curl -s -X POST "$IAM/realms/delivery-platform/protocol/openid-connect/token" \
    -d client_id=mobile-app -d "username=$1" -d "password=$2" -d grant_type=password \
    | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p'
}
code() { # code <token> <method> <path> [json]
  if [ -n "${4:-}" ]; then
    curl -s -o /tmp/e2e_body -w "%{http_code}" -X "$2" -H "Authorization: Bearer $1" \
      -H "Content-Type: application/json" -d "$4" "$API$3"
  else
    curl -s -o /tmp/e2e_body -w "%{http_code}" -X "$2" -H "Authorization: Bearer $1" "$API$3"
  fi
}

echo "=== $ENV : sign-in, all five roles ==="
CUST=$(tok customer 100001);  [ -n "$CUST" ] && ok "customer signs in"  || bad "customer sign-in" "no token"
RIDER=$(tok rider 300003);    [ -n "$RIDER" ] && ok "rider signs in"    || bad "rider sign-in" "no token"
MERCH=$(tok merchant 200002); [ -n "$MERCH" ] && ok "merchant signs in" || bad "merchant sign-in" "no token"
BACK=$(tok backoffice 400004);[ -n "$BACK" ] && ok "backoffice signs in" || bad "backoffice sign-in" "no token"
CARR=$(tok carrier 500005);   [ -n "$CARR" ] && ok "carrier signs in"   || bad "carrier sign-in" "no token"

echo "=== $ENV : the customer's day ==="
C=$(code "$CUST" GET "/api/stores")
STORES=$(grep -c '"id"' /tmp/e2e_body 2>/dev/null || echo 0)
[ "$C" = 200 ] && [ "$STORES" -ge 1 ] && ok "storefront lists shops ($STORES ids)" || bad "storefront" "HTTP $C"
C=$(code "$CUST" GET "/api/categories")
[ "$C" = 200 ] && ok "categories answer" || bad "categories" "HTTP $C"
C=$(code "$CUST" GET "/api/products?page=0&size=5")
PRODUCT=$(sed -n 's/.*"id" *: *"\([a-f0-9-]\{36\}\)".*/\1/p' /tmp/e2e_body | head -1)
[ -z "$PRODUCT" ] && PRODUCT=$(grep -oE '"id":"[a-f0-9-]{36}"' /tmp/e2e_body | head -1 | cut -d'"' -f4)
[ "$C" = 200 ] && [ -n "$PRODUCT" ] && ok "catalogue answers with products" || bad "catalogue" "HTTP $C"
if [ -n "$PRODUCT" ]; then
  C=$(code "$CUST" POST "/api/orders" "{\"items\":[{\"productId\":\"$PRODUCT\",\"qty\":1}],\"deliveryAddress\":\"E2E suite, Hamra, Beirut\",\"contactPhone\":\"+96170123456\",\"paymentMethod\":\"CASH\",\"deliveryTier\":\"STANDARD\"}")
  ORDER=$(grep -oE '"id":"[a-f0-9-]{36}"' /tmp/e2e_body | head -1 | cut -d'"' -f4)
  { [ "$C" = 200 ] || [ "$C" = 201 ]; } && [ -n "$ORDER" ] && ok "cash order placed ($C)" || bad "place order" "HTTP $C: $(head -c 120 /tmp/e2e_body)"
  C=$(code "$CUST" GET "/api/orders/mine?page=0&size=5")
  [ "$C" = 200 ] && grep -q "$ORDER" /tmp/e2e_body 2>/dev/null && ok "order shows in customer history" || bad "order history" "HTTP $C"
fi
C=$(code "$CUST" GET "/api/points/balance")
[ "$C" = 200 ] && ok "points balance answers" || bad "points" "HTTP $C"
C=$(code "$CUST" GET "/api/transfers/methods")
grep -q CASH_ON_DELIVERY /tmp/e2e_body && ok "payment methods list" || bad "transfer methods" "HTTP $C"
C=$(code "$CUST" GET "/api/transfers/rate")
[ "$C" = 200 ] && ok "LBP rate quoted" || bad "transfer rate" "HTTP $C"
C=$(code "$CUST" GET "/api/notifications?page=0&size=1")
[ "$C" = 200 ] && ok "in-app inbox answers" || bad "notifications inbox" "HTTP $C"

echo "=== $ENV : the merchant's day ==="
C=$(code "$MERCH" GET "/api/stores/mine")
[ "$C" = 200 ] && ok "merchant sees their shop(s)" || bad "stores/mine" "HTTP $C"
C=$(code "$MERCH" GET "/api/orders/merchant?page=0&size=5")
[ "$C" = 200 ] && ok "merchant order queue answers" || bad "orders/merchant" "HTTP $C"

echo "=== $ENV : the rider's day ==="
C=$(code "$RIDER" GET "/api/orders/available?page=0&size=5")
[ "$C" = 200 ] && ok "job board answers" || bad "orders/available" "HTTP $C"

echo "=== $ENV : the carrier's day ==="
C=$(code "$CARR" GET "/api/delivery-providers/my-company")
if [ "$C" = 200 ]; then ok "carrier company loads"
elif [ "$C" = 404 ]; then bad "carrier company" "404 - demo carrier has no company (run the carrier seed)"
else bad "carrier company" "HTTP $C"; fi

echo "=== $ENV : the backoffice day ==="
BC=$(curl -s -o /tmp/e2e_body -w "%{http_code}" -X POST "$IAM/realms/delivery-platform/protocol/openid-connect/token" -d client_id=delivery-portal -d username=backoffice -d password=400004 -d grant_type=password)
PTOK=$(sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p' /tmp/e2e_body)
[ -n "$PTOK" ] && ok "backoffice signs in on the portal client" || bad "portal client sign-in" "HTTP $BC"
C=$(code "$PTOK" GET "/api/onboarding/applications")
[ "$C" = 200 ] && ok "applications list answers" || bad "onboarding applications" "HTTP $C"

if [ -n "$MAIL_TO" ]; then
  echo "=== $ENV : one real verification email ==="
  C=$(curl -s -o /tmp/e2e_body -w "%{http_code}" -X POST "$API/api/onboarding/verifications" \
    -H "Content-Type: application/json" -d "{\"channel\":\"EMAIL\",\"destination\":\"$MAIL_TO\"}")
  { [ "$C" = 200 ] || [ "$C" = 202 ]; } && ok "verification code accepted for $MAIL_TO" || bad "verification send" "HTTP $C: $(head -c 100 /tmp/e2e_body)"
fi

echo "=== $ENV : $PASS passed, $FAIL failed ==="
[ "$FAIL" = 0 ]
