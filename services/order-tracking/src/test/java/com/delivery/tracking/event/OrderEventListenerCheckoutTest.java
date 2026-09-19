package com.delivery.tracking.event;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.within;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.HashMap;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import com.delivery.tracking.domain.OrderParticipants;
import com.delivery.tracking.domain.OrderParticipantsRepository;
import com.delivery.tracking.service.MembershipPeriodRecorder;
import com.delivery.tracking.service.PresenceService;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;

/**
 * What the checkout map reads off each order event: the checkout, the shop, and when the order was
 * collected and finished.
 *
 * <p>The times number the pickup stops on the customer's map, so the property that matters is that
 * no replay and no late message can move them: the earliest instant a PICKED_UP (or terminal)
 * snapshot reports is the one that stands, whatever order the bus delivers them in.
 */
@DisplayName("the checkout map's part of the order projection")
class OrderEventListenerCheckoutTest {

    private static final UUID ORDER = UUID.fromString("0c0c0c0c-0000-4000-8000-000000000001");
    private static final UUID CHECKOUT = UUID.fromString("c4ec0000-0000-4000-8000-000000000001");
    private static final Instant T1 = Instant.parse("2026-09-19T10:00:00Z");
    private static final Instant T2 = Instant.parse("2026-09-19T10:07:00Z");
    private static final Instant T3 = Instant.parse("2026-09-19T10:21:00Z");

    private final ObjectMapper json = new ObjectMapper();
    private final Map<UUID, OrderParticipants> rows = new HashMap<>();
    private OrderEventListener listener;

    @BeforeEach
    void setUp() {
        OrderParticipantsRepository participants = mock(OrderParticipantsRepository.class);
        // A repository that remembers, so a second event on the same order finds the first's row.
        when(participants.findById(any())).thenAnswer(
                call -> Optional.ofNullable(rows.get(call.<UUID>getArgument(0))));
        when(participants.save(any(OrderParticipants.class))).thenAnswer(call -> {
            OrderParticipants row = call.getArgument(0);
            rows.put(row.getOrderId(), row);
            return row;
        });
        listener = new OrderEventListener(participants, mock(PresenceService.class), json,
                mock(MembershipPeriodRecorder.class));
    }

    /** An order snapshot as Order Manager publishes it, trimmed to what this service reads. */
    private ObjectNode snapshot(String status, Instant occurredAt) {
        ObjectNode node = json.createObjectNode()
                .put("orderId", ORDER.toString())
                .put("customerId", "customer-sub")
                .put("merchantId", "merchant-sub")
                .put("status", status)
                .put("checkoutId", CHECKOUT.toString())
                .put("storeName", "Abou Joseph Shawarma");
        node.put("riderId", "READY".equals(status) || "PLACED".equals(status) ? null : "rider-sub");
        if (occurredAt != null) {
            node.put("occurredAt", occurredAt.toString());
        }
        return node;
    }

    private void deliver(ObjectNode event) {
        listener.onOrderEvent(event.toString(), null);
    }

    private OrderParticipants row() {
        return rows.get(ORDER);
    }

    @Test
    @DisplayName("the checkout and the shop's name are projected from the snapshot")
    void checkout_and_shop_are_projected() {
        deliver(snapshot("PLACED", T1));

        assertThat(row().getCheckoutId()).isEqualTo(CHECKOUT);
        assertThat(row().getStoreName()).isEqualTo("Abou Joseph Shawarma");
        assertThat(row().getPickedUpAt()).isNull();
        assertThat(row().getCompletedAt()).isNull();
    }

    @Test
    @DisplayName("an order placed alone belongs to no checkout")
    void an_order_placed_alone_has_no_checkout() {
        ObjectNode alone = snapshot("PLACED", T1);
        alone.putNull("checkoutId");
        deliver(alone);

        assertThat(row().getCheckoutId()).isNull();
    }

    /** Absent means "this event does not say" — never "the order left its checkout". */
    @Test
    @DisplayName("a later event that does not carry the link does not erase it")
    void a_silent_event_keeps_the_link() {
        deliver(snapshot("PLACED", T1));
        ObjectNode silent = snapshot("ACCEPTED", T2);
        silent.remove("checkoutId");
        silent.remove("storeName");
        deliver(silent);

        assertThat(row().getCheckoutId()).isEqualTo(CHECKOUT);
        assertThat(row().getStoreName()).isEqualTo("Abou Joseph Shawarma");
        assertThat(row().getStatus()).isEqualTo("ACCEPTED");
    }

    /** A message is untrusted input; an over-long label must not lose the whole event. */
    @Test
    @DisplayName("a shop name longer than the column is cut to it, not refused")
    void an_overlong_name_is_cut() {
        ObjectNode event = snapshot("PLACED", T1);
        event.put("storeName", "x".repeat(400));
        deliver(event);

        assertThat(row().getStoreName()).hasSize(160);
        assertThat(row().getCheckoutId()).isEqualTo(CHECKOUT);
    }

    @Nested
    @DisplayName("when the order was collected")
    class Collected {

        @Test
        @DisplayName("is the occurredAt of the PICKED_UP snapshot, and nothing before it")
        void stamped_on_pickup_only() {
            deliver(snapshot("READY", T1));
            assertThat(row().getPickedUpAt()).isNull();

            deliver(snapshot("PICKED_UP", T2));
            assertThat(row().getPickedUpAt()).isEqualTo(T2);
        }

        @Test
        @DisplayName("survives the same snapshot delivered twice")
        void a_replay_keeps_the_time() {
            deliver(snapshot("PICKED_UP", T2));
            deliver(snapshot("PICKED_UP", T2));

            assertThat(row().getPickedUpAt()).isEqualTo(T2);
        }

        @Test
        @DisplayName("is not moved by a later event that is still in PICKED_UP")
        void a_later_event_keeps_the_first_time() {
            deliver(snapshot("PICKED_UP", T2));
            deliver(snapshot("PICKED_UP", T3));

            assertThat(row().getPickedUpAt()).isEqualTo(T2);
        }

        /** The late message is the true collection; arrival order must not decide it. */
        @Test
        @DisplayName("is the earliest time reported, even when the messages arrive out of order")
        void out_of_order_events_keep_the_earliest_time() {
            deliver(snapshot("PICKED_UP", T3));
            deliver(snapshot("PICKED_UP", T2));

            assertThat(row().getPickedUpAt()).isEqualTo(T2);
        }
    }

    @Nested
    @DisplayName("when the order finished")
    class Completed {

        @Test
        @DisplayName("is stamped on delivery, and a replay does not move it")
        void stamped_on_delivery() {
            deliver(snapshot("PICKED_UP", T2));
            deliver(snapshot("DELIVERED", T3));
            deliver(snapshot("DELIVERED", T3.plusSeconds(90)));

            assertThat(row().getCompletedAt()).isEqualTo(T3);
            // Delivery does not rewrite the collection it followed.
            assertThat(row().getPickedUpAt()).isEqualTo(T2);
        }

        @Test
        @DisplayName("is stamped on cancellation too, with no collection time invented")
        void stamped_on_cancellation() {
            deliver(snapshot("CANCELLED", T2));

            assertThat(row().getCompletedAt()).isEqualTo(T2);
            assertThat(row().getPickedUpAt()).isNull();
        }
    }

    /**
     * Every publisher stamps occurredAt; one that did not would otherwise leave a collected stop
     * unnumbered for good. "When we heard" stands in, and the earliest-wins rule lets a real stamp
     * replace it.
     */
    @Test
    @DisplayName("an event with no readable occurredAt is stamped with when it was heard")
    void a_missing_time_falls_back_to_now() {
        ObjectNode event = snapshot("PICKED_UP", null);
        event.put("occurredAt", "yesterday-ish");
        deliver(event);

        assertThat(row().getPickedUpAt()).isCloseTo(Instant.now(), within(5, ChronoUnit.SECONDS));

        // The real stamp, which is necessarily earlier than when it was heard.
        Instant real = Instant.now().minus(3, ChronoUnit.MINUTES).truncatedTo(ChronoUnit.SECONDS);
        deliver(snapshot("PICKED_UP", real));
        assertThat(row().getPickedUpAt()).isEqualTo(real);
    }

    @Test
    @DisplayName("an occurredAt written as epoch seconds is read as well as ISO-8601")
    void epoch_seconds_are_read() {
        ObjectNode event = snapshot("PICKED_UP", null);
        event.put("occurredAt", new java.math.BigDecimal("1789812420.500000000"));
        deliver(event);

        assertThat(row().getPickedUpAt()).isEqualTo(Instant.ofEpochSecond(1789812420L, 500_000_000L));
    }
}
