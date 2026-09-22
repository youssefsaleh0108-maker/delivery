-- Whether a shop takes orders from the table, as against merely handing out its menu there.
--
-- A table code opens the shop's page carrying `?t=7`. What happens next is the shop's decision and
-- not the code's: a bakery may want the codes purely as a menu on the wall, while a restaurant
-- wants a diner at table 7 to build an order and send it to the till. Both print the same cards.
--
-- So it is a switch of its own beside the table count, not an inference from it. Off is where every
-- shop starts, including the ones that already have cards printed — turning it on is a decision a
-- shopkeeper makes once they know an order will arrive on a device somebody is watching, and a
-- default of on would have started taking orders for shops that never asked.
--
-- The web ordering work reads this off the shop's public page and draws its pad or does not. This
-- migration and the endpoint beside it only record what the shop said.

ALTER TABLE stores ADD COLUMN table_ordering BOOLEAN NOT NULL DEFAULT false;
