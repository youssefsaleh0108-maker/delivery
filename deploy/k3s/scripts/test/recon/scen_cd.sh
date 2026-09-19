#!/bin/sh
# C: a merchant fee waiver. D: cancellations at every state (E, the checkout, is scen_e.sh).
. /dev/shm/recon/lib.sh
CUST=$(tok customer); RIDER=$(tok rider); MERCH=$(tok merchant); BACK=$(tok backoffice delivery-portal)
MSUB=$(sub_of "$MERCH")
P1=1acf044c-486f-4aee-b93b-f15daca667bd   # 9.75
P2=d4252ea2-1290-4f46-a9f7-1bc154af8f27   # 8.25
ADDR='"deliveryAddress":"Recon deep test, Hamra, Beirut","contactPhone":"+96170000001"'
CODE1=$(sed -n 's/.*CODE1=\([^ ]*\).*/\1/p' /dev/shm/recon/orders.txt | tail -1)
PROMO1=$(sed -n 's/.*PROMO1=\([^ ]*\).*/\1/p' /dev/shm/recon/orders.txt | tail -1)
note "reusing code $CODE1 ($PROMO1)"

echo "=== C. a merchant waiver scoped to the demo merchant, ten minutes"
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ); SOON=$(date -u -d '+10 minutes' +%Y-%m-%dT%H:%M:%SZ)
c=$(api "$BACK" POST "/api/offers" "{\"audience\":\"MERCHANT\",\"title\":\"Recon deep test\",\"minSubtotal\":0,\"startsAt\":\"$NOW\",\"endsAt\":\"$SOON\",\"merchantRef\":\"$MSUB\"}")
OFFER=$(j '.id // empty'); note "offer HTTP $c id=$OFFER live=$(j '.live')"
place "{\"items\":[{\"productId\":\"$P1\",\"qty\":1}],$ADDR,\"paymentMethod\":\"CASH\"}"
C=$ORDER
[ -n "$OFFER" ] && { c=$(api "$BACK" POST "/api/offers/$OFFER/withdraw"); note "offer withdrawn HTTP $c live=$(j '.live')"; }
if [ -n "$C" ] && merchant_to "$C" accept prepare ready && rider_to "$C" claim pick-up deliver; then
  wait_legs "$C" "$BACK" && note "legs: $(j '[.[] | "\(.leg)=\(.amount)"] | join(", ")')" || bad "C settled" "no legs"
  check_order "$C"
fi
echo "C=$C OFFER=$OFFER" >> /dev/shm/recon/orders.txt

echo "=== D1. cancelled by the customer at PLACED, with a code"
c=$(api "$BACK" GET "/api/promotions/$PROMO1"); note "code given before: $(j '.givenAway // .given // "?"') redeemed=$(j ".redeemedCount")"
place "{\"items\":[{\"productId\":\"$P2\",\"qty\":1}],$ADDR,\"paymentMethod\":\"CASH\",\"promoCode\":\"$CODE1\"}"
D1=$ORDER
c=$(api "$CUST" POST "/api/orders/$D1/cancel" '{"reason":"recon test"}'); note "customer cancel HTTP $c status=$(j '.status') payment=$(j '.paymentStatus')"
c=$(api "$BACK" GET "/api/promotions/$PROMO1"); note "code given after cancel: $(j '.givenAway // .given // "?"') redeemed=$(j ".redeemedCount")"
check_order "$D1"

echo "=== D2. accepted, customer tries, merchant cancels"
place "{\"items\":[{\"productId\":\"$P2\",\"qty\":1}],$ADDR,\"paymentMethod\":\"CASH\"}"
D2=$ORDER; merchant_to "$D2" accept
c=$(api "$CUST" POST "/api/orders/$D2/cancel" '{"reason":"recon test"}'); note "customer cancel at ACCEPTED HTTP $c"
c=$(api "$MERCH" POST "/api/orders/$D2/cancel" '{"reason":"recon test"}'); note "merchant cancel at ACCEPTED HTTP $c status=$(j '.status')"
check_order "$D2"

echo "=== D3. READY and claimed by the rider, then the merchant cancels"
place "{\"items\":[{\"productId\":\"$P2\",\"qty\":1}],$ADDR,\"paymentMethod\":\"CASH\"}"
D3=$ORDER; merchant_to "$D3" accept prepare ready && rider_to "$D3" claim
c=$(api "$MERCH" POST "/api/orders/$D3/cancel" '{"reason":"recon test"}'); note "merchant cancel at READY+claimed HTTP $c status=$(j '.status') rider=$(j '.riderId // "-" | .[0:8]')"
c=$(api "$RIDER" POST "/api/orders/$D3/pick-up"); note "rider pick-up after cancel HTTP $c"
check_order "$D3"

echo "=== D4. PICKED_UP: nobody may cancel"
place "{\"items\":[{\"productId\":\"$P2\",\"qty\":1}],$ADDR,\"paymentMethod\":\"CASH\"}"
D4=$ORDER; merchant_to "$D4" accept prepare ready && rider_to "$D4" claim pick-up
for who in CUST MERCH BACK; do
  eval "t=\$$who"; c=$(api "$t" POST "/api/orders/$D4/cancel" '{"reason":"recon test"}'); note "$who cancel at PICKED_UP HTTP $c $(err | head -c 90)"
done
c=$(api "$BACK" GET "/api/orders/$D4"); note "backoffice sees actions: $(j '[.actions[]?] | join(",")')"
rider_to "$D4" deliver && wait_legs "$D4" "$BACK" && check_order "$D4"
echo "D1=$D1 D2=$D2 D3=$D3 D4=$D4" >> /dev/shm/recon/orders.txt

echo "=== CDE done: $PASS pass $FAIL fail"
