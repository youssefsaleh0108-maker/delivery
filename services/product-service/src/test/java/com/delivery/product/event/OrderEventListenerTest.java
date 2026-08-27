package com.delivery.product.event;

import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.slf4j.MDC;

import com.delivery.product.domain.DeliveredOrderLine;
import com.delivery.product.domain.DeliveredOrderLineRepository;
import com.delivery.product.domain.ReviewableOrder;
import com.delivery.product.domain.ReviewableOrderRepository;
import com.fasterxml.jackson.databind.ObjectMapper;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;

/**
 * The projection that makes a review checkable.
 *
 * <p>Product Service cannot see the orders schema, so "did this customer actually have this
 * delivered from this shop" has to be answered locally. This listener is the only thing that writes
 * that record, which makes it the thing standing between the review endpoint and anyone who wants
 * to reorder the storefront ranking with invented order ids.
 *
 * <p>It records only delivered orders. Accepting a placed one would let a customer rate a shop on
 * the strength of an order they then cancelled.
 */
class OrderEventListenerTest {

    private static final UUID ORDER = UUID.randomUUID();
    private static final UUID STORE = UUID.randomUUID();

    private ReviewableOrderRepository reviewableOrders;
    private DeliveredOrderLineRepository deliveredLines;
    private OrderEventListener listener;

    @BeforeEach
    void setUp() {
        reviewableOrders = mock(ReviewableOrderRepository.class);
        deliveredLines = mock(DeliveredOrderLineRepository.class);
        listener = new OrderEventListener(reviewableOrders, deliveredLines, new ObjectMapper());
        MDC.clear();
    }

    private static String event(UUID orderId, UUID storeId, String customerId) {
        return """
                {"orderId":"%s","storeId":%s,"customerId":%s,"status":"DELIVERED"}
                """.formatted(orderId,
                storeId == null ? "null" : "\"" + storeId + "\"",
                customerId == null ? "null" : "\"" + customerId + "\"");
    }

    private void deliver(String payload) {
        listener.onOrderEvent(payload, "order.delivered", "order.delivered", "corr-1");
    }

    private ReviewableOrder recorded() {
        ArgumentCaptor<ReviewableOrder> captor = ArgumentCaptor.forClass(ReviewableOrder.class);
        verify(reviewableOrders).save(captor.capture());
        return captor.getValue();
    }

    @Nested
    @DisplayName("a delivered order")
    class Delivered {

        @Test
        void is_recorded_as_reviewable() {
            deliver(event(ORDER, STORE, "customer-sub"));

            ReviewableOrder saved = recorded();
            assertThat(saved.getOrderId()).isEqualTo(ORDER);
            assertThat(saved.getStoreId()).isEqualTo(STORE);
            assertThat(saved.getCustomerId()).isEqualTo("customer-sub");
        }

        /** Both halves of the eligibility rule have to come off this row. */
        @Test
        void permits_a_review_by_its_own_customer_for_its_own_shop() {
            deliver(event(ORDER, STORE, "customer-sub"));

            ReviewableOrder saved = recorded();
            assertThat(saved.allowsReviewBy("customer-sub", STORE)).isTrue();
            assertThat(saved.allowsReviewBy("someone-else", STORE)).isFalse();
            assertThat(saved.allowsReviewBy("customer-sub", UUID.randomUUID())).isFalse();
        }

        /**
         * The bus is at-least-once. Keying on the order id means a redelivery rewrites the same row
         * rather than colliding on the primary key or adding a second.
         */
        @Test
        void is_written_under_the_order_id_so_a_redelivery_overwrites_it() {
            deliver(event(ORDER, STORE, "customer-sub"));
            deliver(event(ORDER, STORE, "customer-sub"));

            ArgumentCaptor<ReviewableOrder> captor = ArgumentCaptor.forClass(ReviewableOrder.class);
            verify(reviewableOrders, org.mockito.Mockito.times(2)).save(captor.capture());
            assertThat(captor.getAllValues()).extracting(ReviewableOrder::getOrderId)
                    .containsExactly(ORDER, ORDER);
        }
    }

    /**
     * The basket, kept so the cross-sell rail has something real to count.
     *
     * <p>Everything asserted here exists to protect one property: a number this platform publishes
     * as "people also ordered this" must be a count of baskets that were genuinely handed over.
     */
    @Nested
    @DisplayName("the delivered basket")
    class Basket {

        private static String eventWithItems(String items) {
            return """
                    {"orderId":"%s","storeId":"%s","customerId":"customer-sub",
                     "status":"DELIVERED","items":[%s]}
                    """.formatted(ORDER, STORE, items);
        }

        private static String line(UUID productId, int qty) {
            return """
                    {"productId":"%s","productName":"Something","unitPrice":9.50,"qty":%d}
                    """.formatted(productId, qty);
        }

        private java.util.List<DeliveredOrderLine> savedLines() {
            ArgumentCaptor<DeliveredOrderLine> captor =
                    ArgumentCaptor.forClass(DeliveredOrderLine.class);
            verify(deliveredLines, org.mockito.Mockito.atLeastOnce()).save(captor.capture());
            return captor.getAllValues();
        }

        @Test
        void keeps_every_line_of_a_delivered_order() {
            UUID hummus = UUID.randomUUID();
            UUID bread = UUID.randomUUID();

            deliver(eventWithItems(line(hummus, 1) + "," + line(bread, 2)));

            assertThat(savedLines()).extracting(DeliveredOrderLine::getProductId)
                    .containsExactlyInAnyOrder(hummus, bread);
        }

        /** The shop is denormalised onto the line so cross-sell can be scoped without a join. */
        @Test
        void records_which_shop_the_basket_came_from() {
            deliver(eventWithItems(line(UUID.randomUUID(), 1)));

            assertThat(savedLines()).allSatisfy(
                    saved -> assertThat(saved.getStoreId()).isEqualTo(STORE));
        }

        /**
         * The whole reason the row is keyed on the order rather than given a surrogate id. Double
         * counting a basket would inflate a number this service publishes as evidence.
         */
        @Test
        void is_written_under_the_order_id_so_a_redelivery_cannot_count_it_twice() {
            UUID hummus = UUID.randomUUID();

            deliver(eventWithItems(line(hummus, 1)));
            deliver(eventWithItems(line(hummus, 1)));

            assertThat(savedLines()).allSatisfy(saved -> {
                assertThat(saved.getOrderId()).isEqualTo(ORDER);
                assertThat(saved.getProductId()).isEqualTo(hummus);
            });
        }

        /**
         * An errand's "items" are free text a customer typed, not catalog rows. The part of a basket
         * that is catalogued is still worth counting.
         */
        @Test
        void skips_a_line_with_no_catalog_product_without_losing_the_rest() {
            UUID real = UUID.randomUUID();

            deliver(eventWithItems(
                    "{\"productName\":\"whatever the shop has\",\"qty\":1},"
                            + line(real, 1)));

            assertThat(savedLines()).extracting(DeliveredOrderLine::getProductId)
                    .containsExactly(real);
        }

        @Test
        void skips_a_line_whose_product_id_is_not_a_uuid_without_losing_the_rest() {
            UUID real = UUID.randomUUID();

            deliver(eventWithItems(
                    "{\"productId\":\"not-a-uuid\",\"qty\":1}," + line(real, 1)));

            assertThat(savedLines()).extracting(DeliveredOrderLine::getProductId)
                    .containsExactly(real);
        }

        /**
         * The column is NOT NULL with CHECK (qty > 0), and the rail counts baskets rather than
         * units — so losing a whole line over a field nothing reads would be the wrong trade.
         */
        @Test
        void normalises_a_missing_or_nonsensical_quantity_rather_than_dropping_the_line() {
            UUID product = UUID.randomUUID();

            deliver(eventWithItems("{\"productId\":\"" + product + "\",\"qty\":0}"));

            assertThat(savedLines()).singleElement()
                    .satisfies(saved -> assertThat(saved.getQty()).isEqualTo(1));
        }

        /** A basket that was never handed over is not evidence that two things go together. */
        @Test
        void a_cancelled_order_contributes_nothing() {
            listener.onOrderEvent(eventWithItems(line(UUID.randomUUID(), 1)),
                    "order.cancelled", "order.cancelled", "corr-1");

            verify(deliveredLines, never()).save(any());
        }

        @Test
        void an_order_with_no_items_is_not_an_error() {
            assertThatCode(() -> deliver(eventWithItems(""))).doesNotThrowAnyException();

            verify(deliveredLines, never()).save(any());
        }
    }

    @Nested
    @DisplayName("everything else on the queue")
    class Ignored {

        /** Rating a shop on the strength of an order you then cancelled is not a review. */
        @Test
        void a_placed_order_is_not_yet_reviewable() {
            listener.onOrderEvent(event(ORDER, STORE, "customer-sub"), "order.placed",
                    "order.placed", "corr-1");

            verify(reviewableOrders, never()).save(any());
        }

        @Test
        void a_cancelled_order_is_not_reviewable() {
            listener.onOrderEvent(event(ORDER, STORE, "customer-sub"), "order.cancelled",
                    "order.cancelled", "corr-1");

            verify(reviewableOrders, never()).save(any());
        }

        /** The queue binds order.# so unrelated order events arrive and must simply be dropped. */
        @Test
        void an_unrelated_order_event_is_dropped() {
            listener.onOrderEvent(event(ORDER, STORE, "customer-sub"), "order.status_changed",
                    "order.status_changed", "corr-1");

            verify(reviewableOrders, never()).save(any());
        }

        /** The header is preferred, but the routing key stands in when it is absent. */
        @Test
        void the_routing_key_is_used_when_the_event_type_header_is_missing() {
            listener.onOrderEvent(event(ORDER, STORE, "customer-sub"), null,
                    "order.delivered", "corr-1");

            verify(reviewableOrders).save(any());
        }
    }

    @Nested
    @DisplayName("orders with nothing to review")
    class NotReviewable {

        /** An errand has no shop, so there is no storefront rating for it to feed. */
        @Test
        void an_errand_with_no_shop_is_skipped_rather_than_failing() {
            deliver(event(ORDER, null, "customer-sub"));

            verify(reviewableOrders, never()).save(any());
        }

        @Test
        void an_event_with_no_customer_is_skipped() {
            deliver(event(ORDER, STORE, null));

            verify(reviewableOrders, never()).save(any());
        }

        /**
         * A malformed message must not spin the queue. A missing review invitation is a smaller
         * problem than a consumer stuck redelivering the same bad payload.
         */
        @Test
        void an_unreadable_payload_does_not_rethrow() {
            assertThatCode(() -> deliver("{not json")).doesNotThrowAnyException();

            verify(reviewableOrders, never()).save(any());
        }

        @Test
        void an_order_id_that_is_not_a_uuid_does_not_rethrow() {
            assertThatCode(() -> deliver(
                    "{\"orderId\":\"not-a-uuid\",\"storeId\":\"" + STORE
                            + "\",\"customerId\":\"customer-sub\"}"))
                    .doesNotThrowAnyException();

            verify(reviewableOrders, never()).save(any());
        }

        /** A database failure must not spin the queue either. */
        @Test
        void a_repository_failure_does_not_rethrow() {
            org.mockito.Mockito.doThrow(new IllegalStateException("db down"))
                    .when(reviewableOrders).save(any());

            assertThatCode(() -> deliver(event(ORDER, STORE, "customer-sub")))
                    .doesNotThrowAnyException();
        }
    }

    @Nested
    @DisplayName("tracing")
    class Tracing {

        /** Consumer threads are pooled; a leftover id would mislabel the next order. */
        @Test
        void the_correlation_id_is_cleared_after_the_event() {
            deliver(event(ORDER, STORE, "customer-sub"));

            assertThat(MDC.get("correlationId")).isNull();
        }

        @Test
        void it_is_cleared_even_when_the_event_is_unreadable() {
            deliver("{not json");

            assertThat(MDC.get("correlationId")).isNull();
        }

        @Test
        void an_event_with_no_correlation_id_is_handled() {
            assertThatCode(() -> listener.onOrderEvent(event(ORDER, STORE, "customer-sub"),
                    "order.delivered", "order.delivered", null)).doesNotThrowAnyException();

            verify(reviewableOrders).save(any());
        }
    }
}
