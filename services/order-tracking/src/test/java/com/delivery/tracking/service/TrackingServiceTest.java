package com.delivery.tracking.service;

import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.data.domain.Pageable;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.ValueOperations;

import com.delivery.tracking.domain.OrderParticipants;
import com.delivery.tracking.domain.OrderParticipantsRepository;
import com.delivery.tracking.domain.TrackingEvent;
import com.delivery.tracking.domain.TrackingEventRepository;
import com.delivery.tracking.route.GeoPoint;
import com.fasterxml.jackson.databind.ObjectMapper;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * How a ping is written, and how the order's own latest position is read back.
 *
 * <p>Two rules do the work here. A rider may only write a position onto their own delivery —
 * otherwise any rider could move the pin on somebody else's order and the customer's map would
 * show a stranger. And a cache failure must degrade the read path rather than fail the write path:
 * losing a ping loses the position permanently, while losing the cache entry only costs a Postgres
 * query. Who may read what is TrackingReadAccessTest, end to end through the routes.
 */
class TrackingServiceTest {

    private static final UUID ORDER = UUID.randomUUID();
    private static final String CUSTOMER = "customer-sub";
    private static final String MERCHANT = "merchant-sub";
    private static final String RIDER = "rider-sub";
    private static final String BACKOFFICE = "backoffice-sub";
    private static final String CACHE_KEY = "delivery:tracking:order:" + ORDER;

    private TrackingEventRepository events;
    private OrderParticipantsRepository participants;
    private PresenceService presence;
    private StringRedisTemplate redis;
    private ValueOperations<String, String> values;
    private ObjectMapper objectMapper;
    private TrackingService tracking;

    @BeforeEach
    void setUp() {
        events = mock(TrackingEventRepository.class);
        participants = mock(OrderParticipantsRepository.class);
        presence = mock(PresenceService.class);
        redis = mock(StringRedisTemplate.class);
        values = mock(ValueOperations.class);
        objectMapper = new ObjectMapper()
                .registerModule(new com.fasterxml.jackson.datatype.jsr310.JavaTimeModule());
        tracking = new TrackingService(events, participants, presence, redis, objectMapper,
                Duration.ofSeconds(60));

        when(redis.opsForValue()).thenReturn(values);
        when(events.save(any(TrackingEvent.class))).thenAnswer(call -> call.getArgument(0));
        when(events.findLatestForOrder(any(UUID.class), any(Pageable.class))).thenReturn(List.of());
        when(events.findByOrderIdOrderByRecordedAtAsc(any(UUID.class))).thenReturn(List.of());
        // Presence is where a fix is judged and given its time; standing in for it, every fix is
        // believed and recorded at the phone's time.
        when(presence.recordFix(anyString(), any(Fix.class), any())).thenAnswer(call -> {
            Fix fix = call.getArgument(1);
            return Optional.of(fix.takenAt());
        });
        orderInStatus("PICKED_UP");
    }

    /** A fix the phone took just now, in downtown Beirut unless told otherwise. */
    private static Fix fix(double lat, double lng, Float accuracyM) {
        return new Fix(lat, lng, accuracyM, Instant.now());
    }

    private OrderParticipants orderAssignedTo(String riderId, String status) {
        OrderParticipants order = new OrderParticipants(ORDER, CUSTOMER, MERCHANT, riderId, status);
        // The shop is at the fix below, so nothing here is withheld for being far from it.
        order.applyRoute(null, new GeoPoint(33.89, 35.50), new GeoPoint(33.90, 35.52));
        when(participants.findById(ORDER)).thenReturn(Optional.of(order));
        return order;
    }

    private OrderParticipants orderInStatus(String status) {
        return orderAssignedTo(RIDER, status);
    }

    private TrackingEvent event(double lat, double lng) {
        return new TrackingEvent(ORDER, RIDER, lat, lng, 5.0f);
    }

    @Nested
    @DisplayName("a rider ping")
    class Pinging {

        @Test
        void is_recorded_and_returned() {
            TrackingService.Recorded recorded =
                    tracking.ping(ORDER, RIDER, fix(33.89, 35.50, 5.0f)).orElseThrow();

            assertThat(recorded.position().lat()).isEqualTo(33.89);
            assertThat(recorded.position().lng()).isEqualTo(35.50);
            assertThat(recorded.position().riderId()).isEqualTo(RIDER);
            verify(events).save(any(TrackingEvent.class));
        }

        @Test
        void refreshes_the_hot_read_cache() {
            tracking.ping(ORDER, RIDER, fix(33.89, 35.50, 5.0f));

            verify(values).set(eq(CACHE_KEY), anyString(), eq(Duration.ofSeconds(60)));
        }

        /** Presence remembers which order the rider's latest fix went on — the rule reads it. */
        @Test
        void tells_presence_which_order_the_fix_went_on() {
            tracking.ping(ORDER, RIDER, fix(33.89, 35.50, 5.0f));

            verify(presence).recordFix(eq(RIDER), any(Fix.class), eq(ORDER));
        }

        /**
         * Without this, any rider could write a position onto somebody else's delivery and the
         * customer watching the map would see a stranger moving towards them.
         */
        @Test
        void from_a_rider_who_is_not_assigned_is_refused() {
            assertThatThrownBy(() -> tracking.ping(ORDER, "other-rider", fix(33.89, 35.50, null)))
                    .isInstanceOf(TrackingService.TrackingNotFoundException.class);

            verify(events, never()).save(any(TrackingEvent.class));
        }

        /** The customer is not the rider, however legitimate their interest in the order. */
        @Test
        void from_the_customer_is_refused_too() {
            assertThatThrownBy(() -> tracking.ping(ORDER, CUSTOMER, fix(33.89, 35.50, null)))
                    .isInstanceOf(TrackingService.TrackingNotFoundException.class);
        }

        /** An order nobody is carrying yet has no assigned rider to match against. */
        @Test
        void on_an_unassigned_order_is_refused() {
            orderAssignedTo(null, "READY");

            assertThatThrownBy(() -> tracking.ping(ORDER, RIDER, fix(33.89, 35.50, null)))
                    .isInstanceOf(TrackingService.TrackingNotFoundException.class);
        }

        @Test
        void on_an_unknown_order_is_refused() {
            when(participants.findById(ORDER)).thenReturn(Optional.empty());

            assertThatThrownBy(() -> tracking.ping(ORDER, RIDER, fix(33.89, 35.50, null)))
                    .isInstanceOf(TrackingService.TrackingNotFoundException.class);
        }

        /**
         * Redis being down must not fail a ping. The write is the thing that cannot be recovered;
         * the cache entry can be rebuilt from Postgres on the next read.
         */
        @Test
        void still_succeeds_when_the_cache_is_unavailable() {
            doThrow(new IllegalStateException("redis down"))
                    .when(values).set(anyString(), anyString(), any(Duration.class));

            assertThat(tracking.ping(ORDER, RIDER, fix(33.89, 35.50, null))).isPresent();
            verify(events).save(any(TrackingEvent.class));
        }

        /** Accuracy is optional — not every handset reports it. */
        @Test
        void without_a_reported_accuracy_is_accepted() {
            assertThat(tracking.ping(ORDER, RIDER, fix(33.89, 35.50, null)).orElseThrow()
                    .position().accuracyM()).isNull();
        }

        /**
         * The trail closes when the delivery does. A handset that keeps pinging after hand-over is
         * the ordinary case rather than the odd one — the app is backgrounded and its queue drains
         * — and every one of those points would extend the customer's view of the rider past the
         * door, and grow the record a dispute is later settled from.
         */
        @Test
        void on_a_delivered_order_is_refused() {
            orderInStatus("DELIVERED");

            assertThatThrownBy(() -> tracking.ping(ORDER, RIDER, fix(33.89, 35.50, 5.0f)))
                    .isInstanceOf(TrackingService.TrackingClosedException.class);

            verify(events, never()).save(any(TrackingEvent.class));
        }

        /** Cancelled is just as over as delivered; nothing is being carried anywhere. */
        @Test
        void on_a_cancelled_order_is_refused() {
            orderInStatus("CANCELLED");

            assertThatThrownBy(() -> tracking.ping(ORDER, RIDER, fix(33.89, 35.50, 5.0f)))
                    .isInstanceOf(TrackingService.TrackingClosedException.class);

            verify(events, never()).save(any(TrackingEvent.class));
        }

        /** Refused before the cache is touched, or the map would keep the last stale point warm. */
        @Test
        void on_a_finished_order_does_not_refresh_the_hot_read_cache() {
            orderInStatus("DELIVERED");

            assertThatThrownBy(() -> tracking.ping(ORDER, RIDER, fix(33.89, 35.50, 5.0f)))
                    .isInstanceOf(TrackingService.TrackingClosedException.class);

            verify(values, never()).set(anyString(), anyString(), any(Duration.class));
        }

        /**
         * Before collection the rider is on their way to the counter: the fix moves the live dot,
         * and never goes on the trail. A claim happens wherever the rider is — often at home — and
         * a trail starting there would keep that place for the whole retention window.
         */
        @Test
        void before_collection_moves_the_live_dot_only() {
            orderInStatus("READY");

            TrackingService.Recorded recorded =
                    tracking.ping(ORDER, RIDER, fix(33.89, 35.50, 5.0f)).orElseThrow();

            assertThat(recorded.onTrail()).isFalse();
            verify(events, never()).save(any(TrackingEvent.class));
            verify(values).set(eq(CACHE_KEY), anyString(), any(Duration.class));
        }

        @Test
        void once_collected_goes_on_the_trail() {
            assertThat(tracking.ping(ORDER, RIDER, fix(33.89, 35.50, 5.0f)).orElseThrow().onTrail())
                    .isTrue();
            verify(events).save(any(TrackingEvent.class));
        }

        /**
         * A stranger must not be able to read an order's state off the shape of the refusal — the
         * rider check runs first, so probing an id still only ever answers "not found".
         */
        @Test
        void on_a_delivered_order_from_a_stranger_is_still_a_not_found() {
            orderInStatus("DELIVERED");

            assertThatThrownBy(() -> tracking.ping(ORDER, "other-rider", fix(33.89, 35.50, null)))
                    .isInstanceOf(TrackingService.TrackingNotFoundException.class);
        }

        /** A refused ping is not evidence of anything, least of all that the rider is on duty. */
        @Test
        void from_a_stranger_does_not_touch_presence() {
            assertThatThrownBy(() -> tracking.ping(ORDER, "other-rider", fix(33.89, 35.50, null)))
                    .isInstanceOf(TrackingService.TrackingNotFoundException.class);

            verify(presence, never()).recordFix(anyString(), any(Fix.class), any());
        }

        /**
         * A fix the policy does not believe must reach nothing a customer can see: not the trail a
         * dispute is settled from, not the hot cache the map reads. Presence judges it first for
         * exactly this reason, so the refusal lands before either write.
         */
        @Test
        void that_is_not_believable_writes_nothing() {
            when(presence.recordFix(anyString(), any(Fix.class), any()))
                    .thenThrow(new FixPolicy.FixRejectedException(FixPolicy.Reason.IMPLAUSIBLE_JUMP));

            assertThatThrownBy(() -> tracking.ping(ORDER, RIDER,
                    new Fix(34.4367, 35.8497, 8.0f, Instant.now())))
                    .isInstanceOf(FixPolicy.FixRejectedException.class);

            verify(events, never()).save(any(TrackingEvent.class));
            verify(values, never()).set(anyString(), anyString(), any(Duration.class));
        }

        /**
         * A believable fix that adds nothing — a duplicate, or one under the rate floor — is not
         * refused, and reaches nothing either: no trail point, no cache entry, and nothing for the
         * controller to push.
         */
        @Test
        void that_adds_nothing_new_writes_nothing_and_returns_nothing_to_push() {
            when(presence.recordFix(anyString(), any(Fix.class), any()))
                    .thenReturn(Optional.empty());

            assertThat(tracking.ping(ORDER, RIDER, fix(33.89, 35.50, 5.0f))).isEmpty();

            verify(events, never()).save(any(TrackingEvent.class));
            verify(values, never()).set(anyString(), anyString(), any(Duration.class));
        }

        /**
         * The trail is about where the rider was when. A fix that sat in a mobile network's queue
         * for twenty seconds is recorded at the moment the phone took it, not when it landed —
         * otherwise the ETA would measure from a position it believes is fresher than it is.
         */
        @Test
        void is_recorded_at_the_moment_the_phone_took_it() {
            Instant takenAt = Instant.now().minusSeconds(20);
            ArgumentCaptor<TrackingEvent> saved = ArgumentCaptor.forClass(TrackingEvent.class);

            TrackingService.Position position = tracking.ping(ORDER, RIDER,
                    new Fix(33.89, 35.50, 6.0f, takenAt)).orElseThrow().position();

            verify(events).save(saved.capture());
            assertThat(saved.getValue().getRecordedAt()).isEqualTo(takenAt);
            assertThat(position.recordedAt()).isEqualTo(takenAt);
        }
    }

    /**
     * The order's own latest position — what the back office reads, and what the rider falls back
     * to before their first fix of the session.
     */
    @Nested
    @DisplayName("reading the order's own latest position")
    class Reading {

        @Test
        void is_served_from_the_cache_without_touching_postgres() throws Exception {
            TrackingService.Position cached = new TrackingService.Position(
                    ORDER, RIDER, 33.89, 35.50, 5.0f, Instant.now());
            when(values.get(CACHE_KEY)).thenReturn(objectMapper.writeValueAsString(cached));

            Optional<TrackingService.Position> read =
                    tracking.currentPosition(ORDER, BACKOFFICE, true);

            assertThat(read).isPresent();
            assertThat(read.get().lat()).isEqualTo(33.89);
            verify(events, never()).findLatestForOrder(any(UUID.class), any(Pageable.class));
        }

        /** A restart or an eviction must not blank the map. */
        @Test
        void falls_back_to_postgres_on_a_cache_miss() {
            when(values.get(CACHE_KEY)).thenReturn(null);
            when(events.findLatestForOrder(eq(ORDER), any(Pageable.class)))
                    .thenReturn(List.of(event(33.89, 35.50)));

            assertThat(tracking.currentPosition(ORDER, BACKOFFICE, true))
                    .hasValueSatisfying(p -> assertThat(p.lat()).isEqualTo(33.89));
        }

        /** Having paid for the query, the answer is put back in the cache. */
        @Test
        void repopulates_the_cache_after_a_miss() {
            when(values.get(CACHE_KEY)).thenReturn(null);
            when(events.findLatestForOrder(eq(ORDER), any(Pageable.class)))
                    .thenReturn(List.of(event(33.89, 35.50)));

            tracking.currentPosition(ORDER, BACKOFFICE, true);

            verify(values).set(eq(CACHE_KEY), anyString(), any(Duration.class));
        }

        /** A corrupt entry must not break the screen for as long as it stays cached. */
        @Test
        void discards_an_unreadable_cache_entry_and_reads_through() {
            when(values.get(CACHE_KEY)).thenReturn("{not json");
            when(events.findLatestForOrder(eq(ORDER), any(Pageable.class)))
                    .thenReturn(List.of(event(33.89, 35.50)));

            assertThat(tracking.currentPosition(ORDER, BACKOFFICE, true)).isPresent();

            verify(redis).delete(CACHE_KEY);
        }

        /** Nor must Redis being down: the order's latest point is in Postgres too. */
        @Test
        void reads_through_to_postgres_when_the_cache_is_unreachable() {
            when(values.get(CACHE_KEY)).thenThrow(new IllegalStateException("redis down"));
            when(events.findLatestForOrder(eq(ORDER), any(Pageable.class)))
                    .thenReturn(List.of(event(33.89, 35.50)));

            assertThat(tracking.currentPosition(ORDER, BACKOFFICE, true)).isPresent();
        }

        /** An order with no pings yet is empty, not an error. */
        @Test
        void is_empty_when_the_rider_has_not_pinged_yet() {
            when(values.get(CACHE_KEY)).thenReturn(null);

            assertThat(tracking.currentPosition(ORDER, BACKOFFICE, true)).isEmpty();
        }

        /** The rider's own latest fix, before any of this session's went on this order. */
        @Test
        void is_what_the_rider_sees_until_their_latest_fix_is_known() {
            when(values.get(CACHE_KEY)).thenReturn(null);
            when(events.findLatestForOrder(eq(ORDER), any(Pageable.class)))
                    .thenReturn(List.of(event(33.89, 35.50)));

            assertThat(tracking.currentPosition(ORDER, RIDER, false)).isPresent();
        }

        @Test
        void is_empty_rather_than_refused_for_the_customer_and_the_shop_with_no_fix_yet() {
            when(values.get(CACHE_KEY)).thenReturn(null);

            for (String participant : List.of(CUSTOMER, MERCHANT, RIDER)) {
                assertThat(tracking.currentPosition(ORDER, participant, false)).isEmpty();
            }
        }

        /** Live location is not public. A stranger must not be able to follow a rider around. */
        @Test
        void is_refused_to_anyone_not_on_the_order() {
            assertThatThrownBy(() -> tracking.currentPosition(ORDER, "stranger-sub", false))
                    .isInstanceOf(TrackingService.TrackingNotFoundException.class);
        }

        @Test
        void an_unknown_order_is_refused() {
            when(participants.findById(ORDER)).thenReturn(Optional.empty());

            assertThatThrownBy(() -> tracking.currentPosition(ORDER, CUSTOMER, false))
                    .isInstanceOf(TrackingService.TrackingNotFoundException.class);
        }
    }

    @Nested
    @DisplayName("the breadcrumb trail")
    class History {

        @Test
        void comes_back_to_the_back_office_in_the_order_it_was_recorded() {
            when(events.findByOrderIdOrderByRecordedAtAsc(ORDER))
                    .thenReturn(List.of(event(33.80, 35.40), event(33.89, 35.50)));

            List<TrackingService.Position> trail = tracking.history(ORDER, BACKOFFICE, true);

            assertThat(trail).hasSize(2);
            assertThat(trail.get(0).lat()).isEqualTo(33.80);
            assertThat(trail.get(1).lat()).isEqualTo(33.89);
        }

        /** Dispute evidence, so the same access rule applies as to the live position. */
        @Test
        void is_refused_to_anyone_not_on_the_order() {
            assertThatThrownBy(() -> tracking.history(ORDER, "stranger-sub", false))
                    .isInstanceOf(TrackingService.TrackingNotFoundException.class);
        }

        /** The shop sees the rider only until pickup, and there is no trail before it. */
        @Test
        void is_never_the_shops() {
            when(events.findByOrderIdOrderByRecordedAtAsc(ORDER))
                    .thenReturn(List.of(event(33.80, 35.40)));

            assertThat(tracking.history(ORDER, MERCHANT, false)).isEmpty();
            verify(events, never()).findByOrderIdOrderByRecordedAtAsc(ORDER);
        }

        /** Never served from the cache — the cache only ever holds the latest point. */
        @Test
        void always_reads_the_full_history_from_postgres() {
            tracking.history(ORDER, RIDER, false);

            verify(events).findByOrderIdOrderByRecordedAtAsc(ORDER);
            verify(values, never()).get(anyString());
        }

        /** A customer's trail needs the moment of collection; without it, none is shown. */
        @Test
        void is_empty_for_the_customer_while_the_collection_time_is_unknown() {
            when(presence.latestFix(RIDER)).thenReturn(Optional.of(new PresenceService.LatestFix(
                    RIDER, ORDER, 33.89, 35.50, 5f, Instant.now())));

            assertThat(tracking.history(ORDER, CUSTOMER, false)).isEmpty();
            verify(events, never()).findByOrderIdAndRecordedAtGreaterThanEqualOrderByRecordedAtAsc(
                    any(UUID.class), isNull());
        }
    }
}
