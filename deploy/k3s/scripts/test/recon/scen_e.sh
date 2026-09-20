#!/bin/sh
# E: a multi-shop checkout with a code, found by quoting first.
. /dev/shm/recon/lib.sh
CUST=$(tok customer); RIDER=$(tok rider); MERCH=$(tok merchant); BACK=$(tok backoffice)
DEMO=0dba1b5f-0543-4bfc-919d-cacc08308ecb
P1=1acf044c-486f-4aee-b93b-f15daca667bd   # 9.75
ADDR='"deliveryAddress":"Recon deep test, Hamra, Beirut","contactPhone":"+96170000001"'
CODE1=$(sed -n 's/.*CODE1=\([^ ]*\).*/\1/p' /dev/shm/recon/orders.txt | tail -1)

c=$(api "$CUST" GET "/api/stores?page=0&size=50")
STORES=$(j '(.content // .)[] | select(.id != "'$DEMO'") | .id')
E_MINE=""; E_OTHER=""; CO=""
for s in $STORES; do
  c=$(api "$CUST" GET "/api/stores/$s/products?size=20")
  for OP in $(j '(.content // .)[] | select((.status // "ACTIVE") == "ACTIVE") | .id' | head -3); do
    Q="{\"items\":[{\"productId\":\"$P1\",\"qty\":1},{\"productId\":\"$OP\",\"qty\":1}],\"promoCode\":\"$CODE1\"}"
    c=$(api "$CUST" POST "/api/orders/quote" "$Q")
    note "quote with $s/$OP HTTP $c placeable=$(j '.placeable') total=$(j '.totalAmount') disc=$(j '.discountAmount') refusals=$(j '[.shops[]? | .refusal // "ok"] | join(",")') $(err | head -c 100)"
    [ "$c" = 200 ] && [ "$(j '.placeable')" = true ] || continue
    KEY="recon-co-$(date +%s)"
    BODY="{\"items\":[{\"productId\":\"$P1\",\"qty\":1},{\"productId\":\"$OP\",\"qty\":1}],$ADDR,\"paymentMethod\":\"CASH\",\"promoCode\":\"$CODE1\",\"expectedTotal\":$(j '.totalAmount')}"
    c=$(api "$CUST" POST "/api/orders/checkout" "$BODY" "$KEY")
    CO=$(j '.checkoutId // empty')
    note "checkout HTTP $c id=$CO total=$(j '.totalAmount') $(err | head -c 150)"
    [ -n "$CO" ] || continue
    note "orders: $(j '[.orders[] | "\(.id[0:8]) store=\(.storeId[0:8]) sub=\(.subtotal) fee=\(.deliveryFee) disc=\(.discountAmount) total=\(.totalAmount)"] | join(" ; ")')"
    E_MINE=$(jq -r '.orders[] | select(.storeId == "'$DEMO'") | .id' "$W/body")
    E_OTHER=$(jq -r '.orders[] | select(.storeId != "'$DEMO'") | .id' "$W/body")
    DISC_SUM=$(jq -r '[.orders[].discountAmount] | add' "$W/body"); TOT_SUM=$(jq -r '[.orders[].totalAmount] | add' "$W/body"); TOT=$(j '.totalAmount')
    awk "BEGIN{exit !($DISC_SUM == 1)}" && ok "discount shares sum to the code (1.00)" || bad "discount shares" "sum=$DISC_SUM"
    awk "BEGIN{exit !($TOT_SUM == $TOT)}" && ok "order totals sum to the checkout total ($TOT)" || bad "checkout total" "sum=$TOT_SUM vs $TOT"
    c=$(api "$CUST" POST "/api/orders/checkout" "$BODY" "$KEY"); note "replay same key HTTP $c same checkout=$( [ "$(j '.checkoutId')" = "$CO" ] && echo yes || echo NO)"
    break 2
  done
done
[ -n "$CO" ] || { bad "multi-shop checkout" "no placeable pair found"; exit 0; }
c=$(api "$CUST" POST "/api/orders/$E_OTHER/cancel" '{"reason":"recon test"}'); note "cancel the other shop's order HTTP $c"
if merchant_to "$E_MINE" accept prepare ready && rider_to "$E_MINE" claim pick-up deliver; then
  wait_legs "$E_MINE" "$BACK" && check_order "$E_MINE"
fi
check_order "$E_OTHER"
printf '%s\n' "select 'checkout|' || count(*) || '|' || sum(discount_amount) || '|' || sum(total_amount) from orders.orders where checkout_id = '$CO';
select 'redemption|order=' || substr(r.order_id::text,1,8) || '|amount=' || r.amount || '|order status=' || o.status || '|order discount=' || o.discount_amount from orders.promo_redemptions r join orders.orders o on o.id = r.order_id where o.checkout_id = '$CO';" | sql
echo "E_MINE=$E_MINE E_OTHER=$E_OTHER CO=$CO" >> /dev/shm/recon/orders.txt
echo "=== E done: $PASS pass $FAIL fail"
