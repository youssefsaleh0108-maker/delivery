-- Ordering at the table: the switch a shop has to turn on first.
--
-- A diner sits down in a restaurant, scans the code printed on the table, and the shop's public menu
-- opens in their phone's browser at /s/<slug>?t=7. They choose, and send. It becomes a ticket in the
-- restaurant's own orders, marked Table 7. They pay at the table, as they always have.
--
-- That is an endpoint which prints paper in a real kitchen, reachable by anybody with the address,
-- because the diner has no account and will not be asked for one. So it is off for every shop on this
-- platform until somebody at that shop turns it on, and this column is that decision. DEFAULT false is
-- the whole of the migration's safety: every shop that exists keeps answering a scanned code with the
-- menu and a line saying to order with the staff, and nothing starts happening to anybody's kitchen
-- because a release went out.
--
-- It is a property of the SHOP and not of the page, which is what keeps the public page cacheable: the
-- answer is the same for every reader of that shop, so it does not split the rendering the way the
-- table code itself would (PublicShopPageController memoises per shop per language, and the table
-- never reaches the server's rendering at all).
--
-- Nothing else keys off this yet. Turning it on adds an order pad to the shop's own page; it changes
-- no price, no fee and no settlement, because a table order is not a sale the platform is part of.

ALTER TABLE stores ADD COLUMN table_ordering boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN stores.table_ordering IS
    'Whether this shop takes orders from a diner at a table, through its own public page. Off until '
    'the shop turns it on: the endpoint that writes a kitchen ticket is anonymous by necessity, so a '
    'shop opts in rather than out.';
