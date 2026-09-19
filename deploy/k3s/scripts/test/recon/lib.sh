#!/bin/sh
# Reconciliation deep-test helpers. Run ON the box, sourced by the scenario scripts.
#
# Copy this directory to /dev/shm/recon on the box and run, in order: scen_ab.sh (a cash order's
# life, promo codes), scen_cd.sh (a merchant waiver, cancellations at every state), scen_e.sh
# (multi-shop checkout), scen_split.sh (friend split, lira intent), scen_f.sh (hand-over and
# payments, twice at once), scen_gh.sh (points payout, every role's report against the ledger,
# access checks), scen_tz.sh (day boundaries), scen_payroll.sh (a pay run). Each order is checked
# with order_check.sql; invariants.sql checks the whole ledger. The ids in the scripts are dev's
# demo shop and company as of 2026-09-19. Delete /dev/shm/recon afterwards.
#
# Tokens follow deploy/k3s/scripts/e2e-smoke.sh: the demo-logins Secret is read once into memory
# and a password only ever travels from it into curl's stdin. Tokens live in shell variables and
# are never printed. Output is ids, statuses, counts and amounts only.
set -u
ENV="${ENV:-dev}"
API="https://api-$ENV.youdrop.shop"
IAM="https://iam-$ENV.youdrop.shop"
NS="delivery-$ENV"
W="${W:-/dev/shm/recon}"
mkdir -p "$W"

DEMO_LOGINS=$(kubectl -n "$NS" get secret demo-logins -o json) \
  || { echo "cannot read the demo-logins Secret in $NS"; exit 2; }
demo_password() {
  printf '%s' "$DEMO_LOGINS" | jq -r --arg u "$1" '.data[$u] // empty' | base64 -d
}

# tok <user> [client-id]
tok() {
  demo_password "$1" | curl -s -X POST "$IAM/realms/delivery-platform/protocol/openid-connect/token" \
    -d "client_id=${2:-mobile-app}" -d "username=$1" --data-urlencode "password@-" \
    -d grant_type=password | jq -r '.access_token // empty'
}

# sub_of <token>: the JWT subject, decoded from stdin so the token is never an argument.
sub_of() {
  printf '%s' "$1" | python3 -c 'import sys,json,base64
p=sys.stdin.read().split(".")[1]; p+="="*(-len(p)%4)
print(json.loads(base64.urlsafe_b64decode(p)).get("sub",""))'
}

# roles_of <token>: realm roles, comma separated.
roles_of() {
  printf '%s' "$1" | python3 -c 'import sys,json,base64
p=sys.stdin.read().split(".")[1]; p+="="*(-len(p)%4)
print(",".join(json.loads(base64.urlsafe_b64decode(p)).get("realm_access",{}).get("roles",[])))'
}

# api <token> <method> <path> [json] [idempotency-key]: body to $W/body, prints the HTTP code.
api() {
  if [ -n "${5:-}" ]; then
    curl -s -o "$W/body" -w "%{http_code}" -X "$2" -H "Authorization: Bearer $1" \
      -H "Content-Type: application/json" -H "Idempotency-Key: $5" -d "$4" "$API$3"
  elif [ -n "${4:-}" ]; then
    curl -s -o "$W/body" -w "%{http_code}" -X "$2" -H "Authorization: Bearer $1" \
      -H "Content-Type: application/json" -d "$4" "$API$3"
  else
    curl -s -o "$W/body" -w "%{http_code}" -X "$2" -H "Authorization: Bearer $1" "$API$3"
  fi
}

# j <jq filter>: read the last response body.
j() { jq -r "$1" "$W/body" 2>/dev/null; }

# err: the error text of the last response, trimmed, for a failed call.
err() { jq -r '.error // .message // .detail // empty' "$W/body" 2>/dev/null | head -c 200; }

# sql: read-only SQL from stdin against the dev database; counts, sums and ids only.
sql() {
  kubectl -n "$NS" exec -i postgres-0 -- psql -U delivery -d delivery -At -F'|' -v ON_ERROR_STOP=1
}

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf "  PASS %s\n" "$1"; }
bad() { FAIL=$((FAIL+1)); printf "  FAIL %s -- %s\n" "$1" "$2"; }
note() { printf "  .... %s\n" "$1"; }

# check_order <order-id>: the per-order invariants in order_check.sql.
check_order() {
  kubectl -n "$NS" exec -i postgres-0 -- psql -U delivery -d delivery -At -F'|' -v ON_ERROR_STOP=1 \
    -v oid="$1" < /dev/shm/recon/order_check.sql | sed 's/^/     /'
}

# place <json> [idempotency-key]: customer places one order; sets ORDER, prints code/total.
place() {
  c=$(api "$CUST" POST "/api/orders" "$1" "${2:-recon-$(date +%s%N | cut -c1-16)}")
  ORDER=$(j '.id // empty')
  note "placed HTTP $c order=$ORDER total=$(j '.totalAmount') subtotal=$(j '.subtotal') fee=$(j '.deliveryFee') discount=$(j '.discountAmount') express=$(j '.expressSurcharge') status=$(j '.status')"
  [ -n "$ORDER" ] || note "  error: $(err)"
}

# merchant_to <order-id> <accept|prepare|ready ...>
merchant_to() {
  o="$1"; shift
  for a in "$@"; do
    c=$(api "$MERCH" POST "/api/orders/$o/$a")
    [ "$c" = 200 ] || { bad "merchant $a" "HTTP $c $(err)"; return 1; }
  done
  note "merchant moved $o through: $*"
}

# rider_to <order-id> <claim|pick-up|deliver ...>
rider_to() {
  o="$1"; shift
  for a in "$@"; do
    tries=0
    while :; do
      c=$(api "$RIDER" POST "/api/orders/$o/$a")
      [ "$c" = 200 ] && break
      tries=$((tries+1))
      if [ "$a" = claim ] && [ $tries -lt 10 ]; then sleep 3; continue; fi
      bad "rider $a" "HTTP $c $(err)"; return 1
    done
  done
  note "rider moved $o through: $*  (provider=$(j '.deliveryProviderId // "-"'))"
}

# wait_legs <order-id> <backoffice-token>: polls the ledger until the order has legs (max 60s).
wait_legs() {
  i=0
  while [ $i -lt 30 ]; do
    c=$(api "$2" GET "/api/accounting/orders/$1")
    if [ "$c" = 200 ] && [ "$(j 'length')" != "0" ]; then return 0; fi
    sleep 2; i=$((i+1))
  done
  return 1
}
