-- The order a shop thread is about, as Order Manager confirmed it. Owned by App Notification Service.
--
-- V24 reserved chat_shop_threads.order_id for this, and it now holds the latest order Order Manager
-- confirmed for the thread (to its customer, or to a merchant of its shop). The id alone cannot label
-- a thread, though: both sides are shown the order's kind (a service order reads differently from a
-- basket), and the merchant inbox lists up to a hundred threads at once, which must not become a
-- hundred reads of Order Manager. So the kind is stored beside the id, written only in the same step
-- and from the same confirmed answer. The short number is not stored: it is the id's first eight
-- characters, as every order screen already derives it.
--
-- Existing rows have no order, so the new column starts NULL everywhere and the check holds.

ALTER TABLE chat_shop_threads ADD COLUMN order_kind varchar(16);

-- An id without a kind, or a kind without an id, would be a label nobody could draw.
ALTER TABLE chat_shop_threads ADD CONSTRAINT ck_chat_shop_thread_order
    CHECK ((order_id IS NULL) = (order_kind IS NULL));
