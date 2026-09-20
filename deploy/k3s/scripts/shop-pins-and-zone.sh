#!/bin/bash
# Repairs, in ONE running environment, the two things every shop on it is missing: a map pin, and a
# calendar that is not UTC. Run ON THE SERVER, as root, one step at a time:
#
#   bash shop-pins-and-zone.sh <namespace> <step> [args]
#
#   report                 what the shops look like now. Counts only. Changes nothing, and it is
#                          safe to run whenever — start and finish here.
#   pins [--dry-run]       give every shop with NO pin one, placed around Beirut and spread out, and
#                          a delivery circle where it has none. Never moves a pin that exists.
#   zone <shop> [shop...]  put the NAMED shops on Asia/Beirut. A shop is named by its slug or its
#                          id; nothing else is touched.
#   zone-demo              the same for the eight 'demo-merchant' shops, which is the one set whose
#                          opening hours this repository wrote itself.
#
# Why the zone is not simply set everywhere
# -----------------------------------------
# A shop's stored zone is the zone its OPENING HOURS were typed against. A real shop that entered
# 08:00-23:00 while the row said UTC meant 08:00-23:00 UTC, and moving the row to Asia/Beirut moves
# its shutters three hours without anybody asking it. So real shops are named, one at a time, by
# somebody who has checked what their hours are supposed to mean. There is no "all".
#
# The demo shops are different: V12 wrote their hours as Lebanese trading hours and then read them
# in UTC, so for them Asia/Beirut is a correction rather than a change. Note that V39 already does
# this on deploy — `zone-demo` is only for an environment that has not taken that migration yet.
#
# What it prints
# --------------
# Counts, the slugs it is about to touch, and nothing else. It reads and writes the `stores` table
# and no other: no customer, no order and no address ever passes through it.
#
# Safe to re-run. Every write is conditional on the field still being empty, so a second run of
# `pins` reports zero and changes nothing.
set -uo pipefail

NS="${1:?usage: shop-pins-and-zone.sh <namespace> <step> [args]}"
STEP="${2:?usage: shop-pins-and-zone.sh <namespace> <step> [args]}"
shift 2

PG_POD="${PG_POD:-postgres-0}"
DB="${DB:-delivery}"
DB_USER="${DB_USER:-delivery}"
SCHEMA="${SCHEMA:-product}"
ZONE="${ZONE:-Asia/Beirut}"

k() { kubectl -n "$NS" "$@"; }
die() { echo "ERROR: $*" >&2; exit 1; }

# The SQL goes in on stdin rather than on a command line, where any user on this box could read it
# out of the process table.
#
# psqlq is the scripted one: no headers, no decoration, one answer per line. psqlt draws the
# report's table, and is the only place column headings are wanted.
psqlq() { k exec -i "$PG_POD" -- psql -U "$DB_USER" -d "$DB" -qAt -v ON_ERROR_STOP=1 -f -; }
psqlt() { k exec -i "$PG_POD" -- psql -U "$DB_USER" -d "$DB" -q -v ON_ERROR_STOP=1 -f -; }

k get pod "$PG_POD" >/dev/null 2>&1 || die "no pod $PG_POD in namespace $NS"

# --------------------------------------------------------------------------------- where the shops go
#
# Twelve real places in and around Beirut, spread over roughly nine kilometres. Spread is the whole
# point: with every shop on one corner, "shops near you", the radius filter and each shop's delivery
# circle answer the same for all of them and demonstrate nothing. Hamra to Antelias is wide enough
# that a 5 km search (delivery.catalog.item-search.radius-metres) takes most of them and leaves the
# furthest out, which is the case worth being able to see.
#
# The radius column is the shop's own delivery circle, in metres, and is only applied where the shop
# has none. Sizes differ on purpose so "this shop does not reach you" has something to say.
SPOTS_SQL="(1, 33.895900, 35.482000, 4000),   -- Hamra
    (2, 33.899500, 35.520000, 3000),   -- Mar Mikhael
    (3, 33.895500, 35.515500, 2500),   -- Gemmayzeh
    (4, 33.886900, 35.520000, 8000),   -- Achrafieh
    (5, 33.879700, 35.484200, 6000),   -- Verdun
    (6, 33.872000, 35.515500, 2500),   -- Badaro
    (7, 33.895900, 35.504000, 5000),   -- Downtown
    (8, 33.915000, 35.585000, 2000),   -- Antelias
    (9, 33.888500, 35.495500, 3500),   -- Sanayeh
    (10, 33.868000, 35.535000, 3000),  -- Furn el Chebbak
    (11, 33.906000, 35.545000, 4500),  -- Dora
    (12, 33.861000, 35.495000, 5000)   -- Ouzai"

# The pin each unpinned shop is about to get.
#
# Ordered by created_at so the assignment is stable: the same shop keeps the same corner however
# often this runs, and a shop pinned by hand in between simply drops out of the set.
#
# More shops than spots is handled rather than left to collide: the cycle number (integer division)
# nudges the second time round the ring by 400 m, so two shops on the same spot are still two points
# a distance query can tell apart.
placement_cte() {
    cat <<SQL
WITH spots(seq, lat, lng, radius) AS (VALUES
    $SPOTS_SQL
),
targets AS (
    SELECT id, slug, row_number() OVER (ORDER BY created_at, id) AS rn
    FROM $SCHEMA.stores
    WHERE latitude IS NULL
),
placed AS (
    SELECT t.id,
           t.slug,
           s.lat + (((t.rn - 1) / (SELECT count(*) FROM spots)) * 0.004) AS lat,
           s.lng + (((t.rn - 1) / (SELECT count(*) FROM spots)) * 0.004) AS lng,
           s.radius
    FROM targets t
    JOIN spots s ON s.seq = ((t.rn - 1) % (SELECT count(*) FROM spots)) + 1
)
SQL
}

# A shop named on the command line. Slugs are [a-z0-9-] by construction (Store.slugify) and ids are
# hex and dashes, so one rule covers both — and it is a rule, not an escape: anything else is
# refused rather than quoted, because a name that needs quoting is a name somebody mistyped.
quote_names() {
    local out="" name
    for name in "$@"; do
        case "$name" in
            *[!A-Za-z0-9-]*|"") die "'$name' is not a shop slug or id (letters, digits and dashes)" ;;
        esac
        out="$out${out:+, }'$name'"
    done
    [ -n "$out" ] || die "name at least one shop"
    echo "$out"
}

case "$STEP" in

report)
    echo "== shops in $NS =="
    psqlt <<SQL
SELECT status,
       count(*)                                              AS shops,
       count(*) FILTER (WHERE latitude IS NOT NULL)          AS with_a_pin,
       count(*) FILTER (WHERE latitude IS NULL)              AS without_a_pin,
       count(*) FILTER (WHERE timezone = 'UTC')              AS on_utc,
       count(*) FILTER (WHERE timezone = '$ZONE')            AS on_zone,
       count(*) FILTER (WHERE delivery_radius_metres IS NULL) AS no_circle
FROM $SCHEMA.stores
GROUP BY status
ORDER BY status;
SQL
    echo
    echo "-- shops with no pin, by slug (a slug is the shop's public storefront key, not customer data):"
    psqlq <<SQL
SELECT slug FROM $SCHEMA.stores WHERE latitude IS NULL ORDER BY created_at, id;
SQL
    ;;

pins)
    DRY=no
    [ "${1:-}" = "--dry-run" ] && DRY=yes

    echo "== shops about to be placed =="
    psqlq <<SQL
$(placement_cte)
SELECT slug || '  ->  ' || round(lat, 5) || ', ' || round(lng, 5)
     || '   circle ' || radius || ' m'
FROM placed ORDER BY slug;
SQL

    if [ "$DRY" = yes ]; then
        echo
        echo "-- dry run: nothing written."
        exit 0
    fi

    echo
    echo "== writing =="
    # The WHERE repeats "latitude IS NULL" although `placed` already selected on it: between the
    # two the merchant's own app may have dropped a pin, and this must never overwrite one.
    #
    # `location`, the PostGIS geography, is a GENERATED column — it follows these two and is never
    # written. The V20 CHECK constraints (in range, both-or-neither, not Null Island) stand behind
    # every value below.
    psqlq <<SQL
$(placement_cte)
UPDATE $SCHEMA.stores st
SET latitude = p.lat,
    longitude = p.lng,
    delivery_radius_metres = COALESCE(st.delivery_radius_metres, p.radius)
FROM placed p
WHERE st.id = p.id
  AND st.latitude IS NULL;
SQL
    [ $? -eq 0 ] || die "the update failed; nothing was committed"

    echo
    echo "== after =="
    psqlq <<SQL
SELECT 'pinned: '   || count(*) FILTER (WHERE latitude IS NOT NULL)
    || ' / ' || count(*) || ' shops, '
    || count(*) FILTER (WHERE delivery_radius_metres IS NULL) || ' still with no circle'
FROM $SCHEMA.stores;
SQL
    ;;

zone|zone-demo)
    if [ "$STEP" = zone-demo ]; then
        PREDICATE="merchant_id = 'demo-merchant'"
        echo "== the demo shops, to $ZONE =="
    else
        NAMES=$(quote_names "$@") || exit 1
        PREDICATE="(slug IN ($NAMES) OR id::text IN ($NAMES))"
        echo "== named shops, to $ZONE =="
    fi

    # Named but not found is worth saying out loud: a typo in a slug is otherwise a silent no-op
    # that looks exactly like success.
    psqlq <<SQL
SELECT slug || '  ' || timezone || ' -> $ZONE'
FROM $SCHEMA.stores
WHERE $PREDICATE AND timezone <> '$ZONE'
ORDER BY slug;
SQL

    echo
    echo "== writing =="
    # Only rows that are not already there, so re-running reports nothing and writes nothing.
    psqlq <<SQL
UPDATE $SCHEMA.stores
SET timezone = '$ZONE'
WHERE $PREDICATE
  AND timezone <> '$ZONE';
SQL
    [ $? -eq 0 ] || die "the update failed; nothing was committed"

    echo
    psqlq <<SQL
SELECT 'on $ZONE: ' || count(*) FILTER (WHERE timezone = '$ZONE')
    || ' / ' || count(*) || ' shops'
FROM $SCHEMA.stores;
SQL
    ;;

*)
    die "unknown step '$STEP'. One of: report, pins, zone, zone-demo"
    ;;
esac
