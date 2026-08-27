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
import org.springframework.data.domain.Pageable;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.ValueOperations;

import com.delivery.tracking.domain.OrderParticipants;
import com.delivery.tracking.domain.OrderParticipantsRepository;
import com.delivery.tracking.domain.TrackingEvent;
import com.delivery.tracking.domain.TrackingEventRepository;
import com.fasterxml.jackson.databind.ObjectMapper;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyDouble;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Where the rider is, who is allowed to ask, and what happens when Redis is not there.
 *
 * <p>Two rules do the work. A rider may only write a position onto their own delivery — otherwise
 * any rider could move the pin on somebody else's order and the customer's map would show a
 * stranger. And a cache failure must degrade the read path rather than fail the write path: losing a
 * ping loses the position permanently, while losing the cache entry only costs a Postgres query.
 */
class TrackingServiceTest {

    private static final UUID ORDER = UUID.randomUUID();
    private static final String CUSTOMER = "customer-sub";
    private static final String MERCHANT = "merchant-sub";
    private static final String RIDER = "rider-sub";
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
        orderAssignedTo(RIDER);
    }

    private void orderAssignedTo(String riderId) {
        when(participants.findById(ORDER)).thenReturn(Optional.of(
                new OrderParticipants(ORDER, CUSTOMER, MERCHANT, riderId, "PICKED_UP")));
    }

    private TrackingEvent event(double lat, double lng) {
        return new TrackingEvent(ORDER, RIDER, lat, lng, 5.0f);
    }

    @Nested
    @DisplayName("a rider ping")
    class Pinging {

        @Test
        void is_recorded_and_returned() {
            TrackingService.Position position = tracking.ping(ORDER, RIDER, 33.89, 35.50, 5.0f);

            assertThat(position.lat()).isEqualTo(33.89);
            assertThat(position.lng()).isEqualTo(35.50);
            assertThat(position.riderId()).isEqualTo(RIDER);
            verify(events).save(any(TrackingEvent.class));
        }

        @Test
        void refreshes_the_hot_read_cache() {
            tracking.ping(ORDER, RIDER, 33.89, 35.50, 5.0f);

            verify(values).set(eq(CACHE_KEY), anyString(), eq(Duration.ofSeconds(60)));
        }

        /**
         * Without this, any rider could write a position onto somebody else's delivery and the
         * customer watching the map would see a stranger moving towards them.
         */
        @Test
        void from_a_rider_who_is_not_assigned_is_refused() {
            assertThatThrownBy(() -> tracking.ping(ORDER, "other-rider", 33.89, 35.50, null))
                    .isInstanceOf(TrackingService.TrackingNotFoundException.class);

            verify(events, never()).save(any(TrackingEvent.class));
        }

        /** The customer is not the rider, however legitimate their interest in the order. */
        @Test
        void from_the_customer_is_refused_too() {
            assertThatThrownBy(() -> tracking.ping(ORDER, CUSTOMER, 33.89, 35.50, null))
                    .isInstanceOf(TrackingService.TrackingNotFoundException.class);
        }

        /** An order nobody is carrying yet has no assigned rider to match against. */
        @Test
        void on_an_unassigned_order_is_refused() {
            orderAssignedTo(null);

            assertThatThrownBy(() -> tracking.ping(ORDER, RIDER, 33.89, 35.50, null))
                    .isInstanceOf(TrackingService.TrackingNotFoundException.class);
        }

        @Test
        void on_an_unknown_order_is_refused() {
            when(participants.findById(ORDER)).thenReturn(Optional.empty());

            assertThatThrownBy(() -> tracking.ping(ORDER, RIDER, 33.89, 35.50, null))
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

            TrackingService.Position position = tracking.ping(ORDER, RIDER, 33.89, 35.50, null);

            assertThat(position).isNotNull();
            verify(events).save(any(TrackingEvent.class));
        }

        /** Accuracy is optional — not every handset reports it. */
        @Test
        void without_a_reported_accuracy_is_accepted() {
            assertThat(tracking.ping(ORDER, RIDER, 33.89, 35.50, null).accuracyM()).isNull();
        }

        /**
         * A rider carrying an order is still a rider who is present. Counting only off-order pings
         * would empty the on-duty roster of exactly the people who are working.
         */
        @Test
        void also_counts_as_evidence_that_the_rider_is_still_present() {
            tracking.ping(ORDER, RIDER, 33.89, 35.50, 5.0f);

            verify(presence).recordFix(RIDER, 33.89, 35.50, 5.0f);
        }

        /** A refused ping is not evidence of anything, least of all that the rider is on duty. */
        @Test
        void from_a_stranger_does_not_touch_presence() {
            assertThatThrownBy(() -> tracking.ping(ORDER, "other-rider", 33.89, 35.50, null))
                    .isInstanceOf(TrackingService.TrackingNotFoundException.class);

            verify(presence, never()).recordFix(anyString(), anyDouble(), anyDouble(), any());
        }
    }

    @Nested
    @DisplayName("reading the current position")
    class Reading {

        @Test
        void is_served_from_the_cache_without_touching_postgres() throws Exception {
            TrackingService.Position cached = new TrackingService.Position(
                    ORDER, RIDER, 33.89, 35.50, 5.0f, Instant.now());
            when(values.get(CACHE_KEY)).thenReturn(objectMapper.writeValueAsString(cached));

            Optional<TrackingService.Position> read =
                    tracking.currentPosition(ORDER, CUSTOMER, false);

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

            assertThat(tracking.currentPosition(ORDER, CUSTOMER, false))
                    .hasValueSatisfying(p -> assertThat(p.lat()).isEqualTo(33.89));
        }

        /** Having paid for the query, the answer is put back in the cache. */
        @Test
        void repopulates_the_cache_after_a_miss() {
            when(values.get(CACHE_KEY)).thenReturn(null);
            when(events.findLatestForOrder(eq(ORDER), any(Pageable.class)))
                    .thenReturn(List.of(event(33.89, 35.50)));

            tracking.currentPosition(ORDER, CUSTOMER, false);

            verify(values).set(eq(CACHE_KEY), anyString(), any(Duration.class));
        }

        /** A corrupt entry must not break the screen for as long as it stays cached. */
        @Test
        void discards_an_unreadable_cache_entry_and_reads_through() {
            when(values.get(CACHE_KEY)).thenReturn("{not json");
            when(events.findLatestForOrder(eq(ORDER), any(Pageable.class)))
                    .thenReturn(List.of(event(33.89, 35.50)));

            assertThat(tracking.currentPosition(ORDER, CUSTOMER, false)).isPresent();

            verify(redis).delete(CACHE_KEY);
        }

        /** An order with no pings yet is empty, not an error. */
        @Test
        void is_empty_when_the_rider_has_not_pinged_yet() {
            when(values.get(CACHE_KEY)).thenReturn(null);

            assertThat(tracking.currentPosition(ORDER, CUSTOMER, false)).isEmpty();
        }

        @Test
        void is_visible_to_the_customer_the_merchant_and_the_rider() {
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

        /** Backoffice sees everything — that is the point of the support role. */
        @Test
        void is_visible_to_backoffice_without_being_on_the_order() {
            when(values.get(CACHE_KEY)).thenReturn(null);

            assertThat(tracking.currentPosition(ORDER, "backoffice-sub", true)).isEmpty();
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
        void comes_back_in_the_order_it_was_recorded() {
            when(events.findByOrderIdOrderByRecordedAtAsc(ORDER))
                    .thenReturn(List.of(event(33.80, 35.40), event(33.89, 35.50)));

            List<TrackingService.Position> trail = tracking.history(ORDER, CUSTOMER, false);

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

        @Test
        void is_visible_to_backoffice() {
            assertThat(tracking.history(ORDER, "backoffice-sub", true)).isEmpty();
        }

        /** Never served from the cache — the cache only ever holds the latest point. */
        @Test
        void always_reads_the_full_history_from_postgres() {
            tracking.history(ORDER, CUSTOMER, false);

            verify(events).findByOrderIdOrderByRecordedAtAsc(ORDER);
            verify(values, never()).get(anyString());
        }
    }
}
