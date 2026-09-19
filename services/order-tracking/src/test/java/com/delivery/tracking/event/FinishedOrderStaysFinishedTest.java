package com.delivery.tracking.event;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import java.time.Duration;
import java.time.Instant;
import java.util.HashMap;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.data.redis.core.StringRedisTemplate;

import com.delivery.tracking.domain.OrderParticipants;
import com.delivery.tracking.domain.OrderParticipantsRepository;
import com.delivery.tracking.domain.TrackingEventRepository;
import com.delivery.tracking.service.Fix;
import com.delivery.tracking.service.MembershipPeriodRecorder;
import com.delivery.tracking.service.PresenceService;
import com.delivery.tracking.service.TrackingService;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;

/**
 * A delivered or cancelled order is over, whatever the bus delivers afterwards.
 *
 * <p>Order events arrive at least once and in no guaranteed order, so the PICKED_UP snapshot of an
 * order that has since been delivered can land again at any time. Applied as it came, it put the
 * order back in PICKED_UP: the rider's pings were accepted on it again, it counted as live for the
 * rider and the customer, and the finished order's map started following the rider once more.
 */
@DisplayName("a finished order stays finished")
class FinishedOrderStaysFinishedTest {

    private static final UUID ORDER = UUID.fromString("0f1e0000-0000-4000-8000-000000000001");
    private static final String RIDER = "rider-sub";
    private static final Instant PICKED_UP = Instant.parse("2026-09-19T10:07:00Z");
    private static final Instant DELIVERED = Instant.parse("2026-09-19T10:21:00Z");

    private final ObjectMapper json = new ObjectMapper();
    private final Map<UUID, OrderParticipants> rows = new HashMap<>();
    private OrderParticipantsRepository participants;
    private OrderEventListener listener;

    @BeforeEach
    void setUp() {
        participants = mock(OrderParticipantsRepository.class);
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

    private void deliver(String status, Instant occurredAt) {
        ObjectNode node = json.createObjectNode()
                .put("orderId", ORDER.toString())
                .put("customerId", "customer-sub")
                .put("merchantId", "merchant-sub")
                .put("riderId", RIDER)
                .put("status", status)
                .put("occurredAt", occurredAt.toString());
        listener.onOrderEvent(node.toString(), null);
    }

    private OrderParticipants row() {
        return rows.get(ORDER);
    }

    @Test
    @DisplayName("a replayed PICKED_UP after DELIVERED does not reopen it")
    void a_replayed_pickup_does_not_reopen_a_delivered_order() {
        deliver("PICKED_UP", PICKED_UP);
        deliver("DELIVERED", DELIVERED);

        deliver("PICKED_UP", PICKED_UP);

        assertThat(row().getStatus()).isEqualTo("DELIVERED");
        assertThat(row().isComplete()).isTrue();
        assertThat(row().isTrackable()).as("counted as a live delivery").isFalse();
        assertThat(row().isCarrying()).isFalse();
        assertThat(row().getCompletedAt()).isEqualTo(DELIVERED);
        assertThat(row().getPickedUpAt()).isEqualTo(PICKED_UP);
    }

    /**
     * Out of order rather than replayed: the collection's own snapshot lands only after the
     * delivery's. The order stays finished, and the collection time it reports is still kept.
     */
    @Test
    @DisplayName("a PICKED_UP that arrives after DELIVERED keeps it finished and still dates the pickup")
    void a_late_pickup_keeps_the_order_finished_and_dates_the_pickup() {
        deliver("DELIVERED", DELIVERED);

        deliver("PICKED_UP", PICKED_UP);

        assertThat(row().getStatus()).isEqualTo("DELIVERED");
        assertThat(row().getCompletedAt()).isEqualTo(DELIVERED);
        assertThat(row().getPickedUpAt()).isEqualTo(PICKED_UP);
    }

    /** A collection dated after the order ended is not a collection. */
    @Test
    @DisplayName("a PICKED_UP dated after the end is not taken as the pickup")
    void a_pickup_dated_after_the_end_is_ignored() {
        deliver("DELIVERED", DELIVERED);

        deliver("PICKED_UP", DELIVERED.plusSeconds(60));

        assertThat(row().getPickedUpAt()).isNull();
    }

    @Test
    @DisplayName("a late READY after CANCELLED does not reopen it either")
    void a_late_snapshot_does_not_reopen_a_cancelled_order() {
        deliver("CANCELLED", DELIVERED);

        deliver("READY", PICKED_UP);

        assertThat(row().getStatus()).isEqualTo("CANCELLED");
        assertThat(row().isComplete()).isTrue();
        assertThat(row().isTrackable()).isFalse();
    }

    @Test
    @DisplayName("and the rider's pings on it are still refused as finished")
    void pings_on_it_stay_refused() {
        deliver("PICKED_UP", PICKED_UP);
        deliver("DELIVERED", DELIVERED);
        deliver("PICKED_UP", PICKED_UP);

        TrackingService tracking = new TrackingService(mock(TrackingEventRepository.class),
                participants, mock(PresenceService.class), mock(StringRedisTemplate.class), json,
                Duration.ofSeconds(60));

        assertThatThrownBy(() -> tracking.ping(ORDER, RIDER,
                new Fix(33.8938, 35.5018, 6f, Instant.now())))
                .isInstanceOf(TrackingService.TrackingClosedException.class);
    }
}
