-- Coordinates on a store, and the index that turns "shops near me" into a query rather than a scan.
--
-- The latitude/longitude columns have existed since V11 and have never been written to: nothing
-- validated them, nothing returned them, and every map in the design was therefore a placeholder.
-- This migration makes them real — the range rules, the geometry the nearby query needs, and the
-- index behind it.
--
-- To be clear about what this does NOT change: delivery is still priced by AREA, exactly as V18
-- argued. A street address in this market is a landmark and a floor, not something a geocoder
-- resolves to the door, and nothing below turns metres into money. Coordinates are here for the
-- map pin, the address picker and the "near me" rail, which are the three things the design draws
-- and the schema could not answer.

-- ---------------------------------------------------------------------------------------------
-- The rules a coordinate has to obey.
-- ---------------------------------------------------------------------------------------------
--
-- Enforced here as well as in GeoPoint, and both are wanted. The value object gives a merchant a
-- readable 400; these constraints are what stops a bad row arriving from a backfill, a repair
-- script, or a future writer that forgets the value object exists. A rule that only lives in
-- application code is a convention, not a constraint.
ALTER TABLE stores
    ADD CONSTRAINT chk_store_latitude
        CHECK (latitude IS NULL OR latitude BETWEEN -90 AND 90),
    ADD CONSTRAINT chk_store_longitude
        CHECK (longitude IS NULL OR longitude BETWEEN -180 AND 180),

    -- Half a pin is not a pin. Without this a store could carry a latitude and no longitude, and
    -- the generated column below would silently be NULL — a shop that has "set its location" and
    -- is invisible on every map, with nothing anywhere saying why.
    ADD CONSTRAINT chk_store_pin_complete
        CHECK ((latitude IS NULL) = (longitude IS NULL)),

    -- Null Island. (0, 0) is what an uninitialised float, a dropped form field and a failed parse
    -- all produce; it is a real point in the Gulf of Guinea and it is essentially never the one
    -- anybody meant. Refusing it turns the commonest coordinate bug from an invisible wrong answer
    -- into a loud rejection at the moment it is written.
    ADD CONSTRAINT chk_store_pin_not_null_island
        CHECK (latitude IS NULL OR latitude <> 0 OR longitude <> 0);

-- ---------------------------------------------------------------------------------------------
-- The geometry, and why it is generated.
-- ---------------------------------------------------------------------------------------------

-- Assert the extension rather than assume it. It IS enabled — infra/postgres/init creates it in
-- `public` on first boot, the image is postgis/postgis:17-3.5, and both the orders and tracking
-- schemas already hold geography columns that would not have created without it. But if this ever
-- runs against a plain Postgres, "type geography does not exist" three statements later is a much
-- worse message than saying so here.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'postgis') THEN
        RAISE EXCEPTION 'product-service V20 needs the postgis extension, which is not installed in this database. It is created by infra/postgres/init/01-databases-and-extensions.sql; without it there is no indexed nearby query.';
    END IF;
END
$$;

ALTER TABLE stores
    -- Generated from the two columns above rather than written by the application, for the same
    -- reason tracking_events.location is (V10 there): the pin and the geometry can then never
    -- disagree, and this service needs no spatial Hibernate dialect — nothing in Java ever reads
    -- or writes this column, only the WHERE clause does.
    --
    -- geography, not geometry, so ST_DWithin's radius is metres on the spheroid rather than
    -- degrees. A degree of longitude is 111 km at the equator and 78 km in Beirut, so a
    -- geometry-based radius silently means something different in every city.
    --
    -- Every PostGIS name MUST be schema-qualified with public.: the extension lives in `public`,
    -- but Flyway pins the search path to this service's own schema. Same trap as gin_trgm_ops in
    -- V11 and gist_geography_ops below.
    ADD COLUMN location public.geography(Point, 4326)
        GENERATED ALWAYS AS
            (public.ST_SetSRID(public.ST_MakePoint(longitude, latitude), 4326)::public.geography)
        STORED;

-- The "near me" query. GIST is the index type geography needs, and its operator class needs
-- qualifying for the reason above.
--
-- Partial on ACTIVE, matching idx_stores_live_vertical: a nearby search is a customer-facing
-- query and must never surface a DRAFT or SUSPENDED shop, so the rows the index does not hold are
-- rows the query must not return anyway.
CREATE INDEX idx_stores_location ON stores
    USING gist (location public.gist_geography_ops)
    WHERE status = 'ACTIVE';
