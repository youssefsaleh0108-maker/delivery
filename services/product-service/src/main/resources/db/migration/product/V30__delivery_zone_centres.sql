-- ---------------------------------------------------------------------------------------------
-- Where a delivery area sits on a map: an optional centre point per area.
--
-- WHY THIS EXISTS. V18 made areas names on purpose ("Hamra", not a polygon), because in this market
-- an address is a landmark and a floor, and the reliable answer to "where is this going" is to ask.
-- That is still right for pricing, and nothing here changes it. What a name cannot do is be drawn:
-- a merchant's Demand Radar (Figma 121:8) shows which neighbourhoods around the shop are ordering,
-- and a name has no position to put a circle at.
--
-- A CENTRE, NOT A BOUNDARY. One point per area, entered by the back office, marking roughly the
-- middle of the neighbourhood. It is used for exactly two things: placing the area's circle on the
-- demand map, and deciding which areas lie around a shop that has dropped a pin. A polygon would be
-- more precise and would need a mapping workflow nobody has; a circle drawn at the heart of
-- "Mar Mikhael" is as precise as a neighbourhood-level map needs to be.
--
-- Optional. Every existing area has none, and an area without one keeps working everywhere it did:
-- it is listed rather than drawn, and is found around a shop only through that shop's own coverage.
-- ---------------------------------------------------------------------------------------------

-- numeric(9,6): the type and scale of a store pin (V20), so a centre and a pin compare like for
-- like and a value does not change on the way through a double.
ALTER TABLE delivery_zones
    ADD COLUMN center_lat numeric(9, 6),
    ADD COLUMN center_lng numeric(9, 6);

-- Per-axis ranges. They cannot catch a transposed pair, but they do catch a centre typed in the
-- wrong unit or a sentinel like 999.
ALTER TABLE delivery_zones
    ADD CONSTRAINT chk_zone_center_range
    CHECK ((center_lat IS NULL OR center_lat BETWEEN -90 AND 90)
       AND (center_lng IS NULL OR center_lng BETWEEN -180 AND 180));

-- Both axes or neither. A lone latitude passes every range check and would draw the area on the
-- prime meridian; GeoPoint refuses half a point on the way in, and this makes it unstorable.
ALTER TABLE delivery_zones
    ADD CONSTRAINT chk_zone_center_pair
    CHECK ((center_lat IS NULL) = (center_lng IS NULL));

COMMENT ON COLUMN delivery_zones.center_lat IS
    'Roughly the middle of the area, for drawing it on the merchant demand map and for finding the '
    'areas near a shop pin. Not a boundary. NULL until the back office places the area.';
