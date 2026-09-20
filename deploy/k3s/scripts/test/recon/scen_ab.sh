#!/bin/sh
# A: a cash order through its whole life. B: promo codes (partial and 100%) on an EXPRESS order.
. /dev/shm/recon/lib.sh
CUST=$(tok customer); RIDER=$(tok rider); MERCH=$(tok merchant); BACK=$(tok backoffice)
P1=1acf044c-486f-4aee-b93b-f15daca667bd   # 9.75, demo merchant's shop
P2=d4252ea2-1290-4f46-a9f7-1bc154af8f27   # 8.25
ADDR='"deliveryAddress":"Recon deep test, Hamra, Beirut","contactPhone":"+96170000001"'
RUN=$(date -u +%H%M%S)

echo "=== A. cash order, STANDARD, whole life"
place "{\"items\":[{\"productId\":\"$P1\",\"qty\":2}],$ADDR,\"paymentMethod\":\"CASH\",\"deliveryTier\":\"STANDARD\"}"
A=$ORDER
if merchant_to "$A" accept prepare ready && rider_to "$A" claim pick-up deliver; then
  wait_legs "$A" "$BACK" && note "legs: $(j '[.[] | "\(.leg)=\(.amount)/\(.status)"] | join(", ")')" \
    || bad "A settled" "no legs after 60s"
  check_order "$A"
fi
echo "A=$A" >> /dev/shm/recon/orders.txt

echo "=== B1. EXPRESS + AMOUNT_OFF 1.00 promo"
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ); LATER=$(date -u -d '+3 hours' +%Y-%m-%dT%H:%M:%SZ)
c=$(api "$BACK" POST "/api/promotions" "{\"code\":\"RECON-A$RUN\",\"kind\":\"AMOUNT_OFF\",\"value\":1.00,\"minSubtotal\":0,\"startsAt\":\"$NOW\",\"endsAt\":\"$LATER\",\"maxRedemptions\":8,\"maxPerCustomer\":8}")
PROMO1=$(j '.id // empty'); note "promo RECON-A$RUN HTTP $c id=$PROMO1"
place "{\"items\":[{\"productId\":\"$P2\",\"qty\":1}],$ADDR,\"paymentMethod\":\"CASH\",\"deliveryTier\":\"EXPRESS\",\"promoCode\":\"RECON-A$RUN\"}"
B1=$ORDER
if [ -n "$B1" ] && merchant_to "$B1" accept prepare ready && rider_to "$B1" claim pick-up deliver; then
  wait_legs "$B1" "$BACK" && note "legs: $(j '[.[] | "\(.leg)=\(.amount)"] | join(", ")')" || bad "B1 settled" "no legs"
  check_order "$B1"
fi
echo "B1=$B1 PROMO1=$PROMO1 CODE1=RECON-A$RUN" >> /dev/shm/recon/orders.txt

echo "=== B2. a code worth the whole bill (total 0.00)"
c=$(api "$BACK" POST "/api/promotions" "{\"code\":\"RECON-F$RUN\",\"kind\":\"AMOUNT_OFF\",\"value\":50.00,\"minSubtotal\":0,\"startsAt\":\"$NOW\",\"endsAt\":\"$LATER\",\"maxRedemptions\":2,\"maxPerCustomer\":2}")
PROMO2=$(j '.id // empty'); note "promo RECON-F$RUN HTTP $c id=$PROMO2"
place "{\"items\":[{\"productId\":\"$P2\",\"qty\":1}],$ADDR,\"paymentMethod\":\"CASH\",\"deliveryTier\":\"STANDARD\",\"promoCode\":\"RECON-F$RUN\"}"
B2=$ORDER
if [ -n "$B2" ] && merchant_to "$B2" accept prepare ready && rider_to "$B2" claim pick-up deliver; then
  wait_legs "$B2" "$BACK" && note "legs: $(j '[.[] | "\(.leg)=\(.amount)"] | join(", ")')" || bad "B2 settled" "no legs"
  check_order "$B2"
fi
echo "B2=$B2 PROMO2=$PROMO2 CODE2=RECON-F$RUN" >> /dev/shm/recon/orders.txt
echo "=== AB done: $PASS pass $FAIL fail"
