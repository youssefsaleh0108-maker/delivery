#!/bin/sh
# Whether this environment's storefront is real. Run after every sync by the demo-storefront-gate
# Job (base/demo-storefront-gate.yaml).
#
# Migration V12__demo_storefront seeds EIGHT shops and their products, owned by the synthetic
# merchant 'demo-merchant', into every fresh database. That is right for dev and for a test
# environment — the three store states a storefront has to render are all represented deliberately
# — and it is wrong for a shop that customers open, where eight restaurants that do not exist sit
# above the real ones and can be ordered from.
#
# A migration cannot be gated: Flyway runs what is in the jar, and a migration that has already run
# is never re-evaluated. So the seeding stays as it is and this removes it afterwards, which also
# means an environment that is PROMOTED to production is cleaned by the same code as one that was
# born that way.
#
# ALWAYS REPORTS, only sometimes deletes. In dev and qa it counts what is there and leaves it.
set -eu

TIER="${ENVIRONMENT_TIER:-}"
NS="${NAMESPACE:-unknown}"
say() { echo "[demo-gate] $*"; }

if [ -z "$TIER" ]; then
  say "ENVIRONMENT_TIER is not set in this environment's platform-env."
  say "It decides whether the demo storefront is kept, so there is no safe default to assume:"
  say "  development | test  keep the eight demo shops"
  say "  production          delete them, and prove they are gone"
  say "Add it to the overlay's platform-env literals. Nothing was changed."
  exit 1
fi

# Flyway runs inside product-service, which starts in parallel with this Job. Wait for the table
# rather than guessing: a purge that ran before the seed would report success and change nothing.
i=0
until psql -h "$PGHOST" -U "$PGUSER" -d delivery -At \
      -c "select 1 from information_schema.tables where table_name = 'stores'" | grep -q 1; do
  i=$((i + 1))
  if [ "$i" -ge 60 ]; then
    say "the stores table still does not exist after 10 minutes."
    say "product-service has not finished its migrations, or this is not the right database."
    exit 1
  fi
  [ "$i" = 1 ] && say "waiting for product-service's migrations to create the stores table"
  sleep 10
done

count() { psql -h "$PGHOST" -U "$PGUSER" -d delivery -At -c "$1"; }
DEMO_SHOPS="select count(*) from stores where merchant_id = 'demo-merchant'"
DEMO_ITEMS="select count(*) from products where merchant_id = 'demo-merchant'"

shops=$(count "$DEMO_SHOPS")
items=$(count "$DEMO_ITEMS")
say "$NS is tier '$TIER': $shops demo shop(s), $items demo product(s)"

if [ "$TIER" != production ]; then
  say "kept — this is not a production environment."
  say "To see them:  select name, slug, status from stores where merchant_id = 'demo-merchant';"
  exit 0
fi

if [ "$shops" = 0 ] && [ "$items" = 0 ]; then
  say "nothing to remove; this storefront is already real. (Idempotent: this runs every sync.)"
  exit 0
fi

# Products first. Everything else that hangs off a store — hours, offers, reviews, zones, staff,
# scans, categories — is ON DELETE CASCADE, but products.store_id is ON DELETE RESTRICT, so the
# stores cannot go until their products have.
say "removing the demo storefront"
psql -h "$PGHOST" -U "$PGUSER" -d delivery -v ON_ERROR_STOP=1 <<'SQL'
BEGIN;
DELETE FROM products WHERE merchant_id = 'demo-merchant';
DELETE FROM stores   WHERE merchant_id = 'demo-merchant';
COMMIT;
SQL

left_shops=$(count "$DEMO_SHOPS")
left_items=$(count "$DEMO_ITEMS")
if [ "$left_shops" = 0 ] && [ "$left_items" = 0 ]; then
  say "removed $shops shop(s) and $items product(s); 0 remain."
else
  say "FAILED: $left_shops shop(s) and $left_items product(s) are still there."
  exit 1
fi

# The aisles V12 also created (Coffee & Tea, Convenience, Dairy & Eggs, ...) are NOT removed. They
# carry no merchant, nothing points at a shop that no longer exists, and they are the category tree
# a real catalogue is filed under — deleting them would mean the back office typing them back in
# before the first merchant can list anything.
say "$(count "select count(*) from categories") categories kept (the aisle tree; they belong to no merchant)"
say "Anything a real merchant has created is untouched: $(count "select count(*) from stores where merchant_id <> 'demo-merchant'") shop(s) remain."
