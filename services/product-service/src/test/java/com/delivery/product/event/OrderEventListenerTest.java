package com.delivery.product.event;

import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.slf4j.MDC;

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
    private OrderEventListener listener;

    @BeforeEach
    void setUp() {
        reviewableOrders = mock(ReviewableOrderRepository.class);
        listener = new OrderEventListener(reviewableOrders, new ObjectMapper());
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
