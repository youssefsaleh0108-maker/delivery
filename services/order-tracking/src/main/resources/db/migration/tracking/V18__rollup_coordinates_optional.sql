-- A trail's summary no longer keeps where the rider was.
--
-- tracking_events is kept for delivery.tracking.raw-ping-retention-days (30), then each day is
-- rolled up into tracking_event_rollup and its partition dropped (TrackingPartitionMaintenance).
-- The rollup kept every order's first and last point of the day for good: with real rider
-- positions those are the shop, or the claim (often the rider's home), and usually the customer's
-- door — outliving the very trail whose retention the rollup is part of. New rollups keep the
-- count, the first and last times and the straight-line span, and write NULL coordinates, so the
-- four columns stop being required.
--
-- Existing rows are kept exactly as they are: nothing here deletes or rewrites them. Every row
-- rolled up so far on dev came from the old simulated London walk, and production starts from a
-- fresh database, so no real rider's or customer's position is left behind in them.
ALTER TABLE tracking_event_rollup
    ALTER COLUMN first_lat DROP NOT NULL,
    ALTER COLUMN first_lng DROP NOT NULL,
    ALTER COLUMN last_lat  DROP NOT NULL,
    ALTER COLUMN last_lng  DROP NOT NULL;
