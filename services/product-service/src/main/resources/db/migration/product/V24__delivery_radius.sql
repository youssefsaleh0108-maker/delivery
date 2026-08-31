-- The merchant's delivery circle: how far from the pin this shop will carry.
--
-- Null means what it always meant — the shop delivers wherever the platform's zones reach — so
-- every existing store keeps its behaviour. A value only binds when the shop HAS a pin: a circle
-- needs a centre, and the storefront enforces that ordering (the radius endpoint refuses a store
-- with no location). The check itself runs on V20's generated geography column, which is exactly
-- what that column was built for.
ALTER TABLE stores ADD COLUMN delivery_radius_metres INT
    CHECK (delivery_radius_metres IS NULL OR delivery_radius_metres BETWEEN 200 AND 50000);
