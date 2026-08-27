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

import com.delivery.tracking.domain.OrderParticipants;
import com.delivery.tracking.domain.OrderParticipantsRepository;
import com.delivery.tracking.route.GeoPoint;
import com.delivery.tracking.route.HaversineRouteProvider;
import com.delivery.tracking.route.RouteProviderRegistry;
import com.delivery.tracking.service.EtaService.EtaResult;
import com.delivery.tracking.service.EtaService.Leg;
import com.delivery.tracking.service.EtaService.Reason;
import com.delivery.tracking.service.TrackingService.Position;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.assertj.core.api.Assertions.within;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyBoolean;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * When the platform is willing to promise an arrival time, and when it refuses.
 *
 * <p>Almost every test here is about a refusal, which is the right proportion. An ETA is the number
 * a customer plans their evening around, and the failure that matters is not an estimate that is a
 * few minutes out — it is an estimate produced from nothing at all: no fix, a fix from twenty
 * minutes ago, an order with no coordinates on it, a routing provider that did not answer. In every
 * one of those the endpoint must come back empty-handed and say which one it was.
 */
class EtaServiceTest {

    private static final UUID ORDER = UUID.randomUUID();
    private static final String CUSTOMER = "customer-sub";
    private static final String MERCHANT = "merchant-sub";
    private static final String RIDER = "rider-sub";

    // Beirut: a restaurant, a customer about 15 km away, and a rider on the restaurant's doorstep.
    private static final GeoPoint PICKUP = new GeoPoint(33.8938, 35.5018);
    private static final GeoPoint DROPOFF = new GeoPoint(33.9550, 35.6500);

    private TrackingService tracking;
    private OrderParticipantsRepository participants;
    private EtaService eta;

    @BeforeEach
    void setUp() {
        tracking = mock(TrackingService.class);
        participants = mock(OrderParticipantsRepository.class);
        // 60 km/h so a distance in kilometres is a time in minutes, and the assertions stay legible.
        RouteProviderRegistry providers = new RouteProviderRegistry(
                List.of(new HaversineRouteProvider(60)), HaversineRouteProvider.NAME);

        eta = new EtaService(tracking, participants, providers, Duration.ofMinutes(5));
    }

    /** An order in the given status, with route points if {@code routed}. */
    private OrderParticipants order(String status, boolean routed) {
        OrderParticipants order = new OrderParticipants(ORDER, CUSTOMER, MERCHANT, RIDER, status);
        if (routed) {
            order.applyRoute(UUID.randomUUID(), PICKUP, DROPOFF);
        }
        when(participants.findById(ORDER)).thenReturn(Optional.of(order));
        return order;
    }

    private void riderAt(GeoPoint point, Instant fixTakenAt) {
        when(tracking.currentPosition(any(UUID.class), anyString(), anyBoolean()))
                .thenReturn(Optional.of(new Position(ORDER, RIDER, point.lat(), point.lng(),
                        5.0f, fixTakenAt)));
    }

    private EtaResult ask() {
        return eta.estimateFor(ORDER, CUSTOMER, false);
    }

    @Nested
    @DisplayName("with nothing to go on the ETA is absent")
    class Absent {

        /**
         * The rule the endpoint exists to keep. A rider who has not pinged could be at the
         * restaurant or still at home, and a number derived from the pickup point would be rendered
         * by the app as a promise.
         */
        @Test
        void when_the_rider_has_never_pinged() {
            order("PICKED_UP", true);
            when(tracking.currentPosition(any(UUID.class), anyString(), anyBoolean()))
                    .thenReturn(Optional.empty());

            EtaResult result = ask();

            assertThat(result.available()).isFalse();
            assertThat(result.reason()).isEqualTo(Reason.NO_FIX);
            assertThat(result.estimatedArrival()).isNull();
            assertThat(result.remainingMetres()).isNull();
        }

        /** A fix from twenty minutes ago is a memory, not a position. */
        @Test
        void when_the_last_fix_is_older_than_the_platform_will_measure_from() {
            order("PICKED_UP", true);
            riderAt(PICKUP, Instant.now().minus(Duration.ofMinutes(20)));

            EtaResult result = ask();

            assertThat(result.available()).isFalse();
            assertThat(result.reason()).isEqualTo(Reason.STALE_FIX);
            assertThat(result.estimatedArrival()).isNull();
        }

        /**
         * Today's normal case: order events carry a postal address and no coordinates, so there is
         * nothing to measure towards. Reported as such rather than guessed at.
         */
        @Test
        void when_the_order_carries_no_coordinates() {
            order("PICKED_UP", false);
            riderAt(PICKUP, Instant.now());

            EtaResult result = ask();

            assertThat(result.available()).isFalse();
            assertThat(result.reason()).isEqualTo(Reason.NO_DESTINATION);
        }

        /** Nothing is on its way to anybody once the order is over. */
        @Test
        void when_the_order_has_already_been_delivered() {
            order("DELIVERED", true);

            EtaResult result = ask();

            assertThat(result.available()).isFalse();
            assertThat(result.reason()).isEqualTo(Reason.ORDER_COMPLETE);
        }

        /** A terminal order should not even cost a position lookup. */
        @Test
        void without_looking_up_a_position_it_does_not_need() {
            order("CANCELLED", true);

            ask();

            verify(tracking, never()).currentPosition(any(UUID.class), anyString(), anyBoolean());
        }

        /**
         * Even with no number in it, the response says who would have produced one. A client that
         * cannot tell a dev estimator from a routing engine cannot decide how much to trust either.
         */
        @Test
        void but_still_says_which_provider_was_asked() {
            order("PICKED_UP", false);
            riderAt(PICKUP, Instant.now());

            assertThat(ask().provider()).isEqualTo(HaversineRouteProvider.NAME);
        }
    }

    @Nested
    @DisplayName("with a fresh fix and a destination")
    class Available {

        @Test
        void the_remaining_distance_is_measured_from_where_the_rider_actually_is() {
            order("PICKED_UP", true);
            riderAt(PICKUP, Instant.now());

            EtaResult result = ask();

            assertThat(result.available()).isTrue();
            assertThat(result.reason()).isNull();
            // Pickup to dropoff: the 15.27 km great circle pinned in HaversineRouteProviderTest.
            assertThat(result.remainingMetres()).isCloseTo(15_274d, within(50d));
        }

        @Test
        void the_arrival_instant_is_the_fix_plus_the_travel_time() {
            order("PICKED_UP", true);
            Instant fixAt = Instant.now();
            riderAt(PICKUP, fixAt);

            EtaResult result = ask();

            // 15.27 km at 60 km/h is a shade over fifteen minutes.
            assertThat(result.remainingSeconds()).isBetween(900L, 930L);
            // Anchored to the fix, not to the moment of asking: the distance was measured from
            // where the rider was then, and the seconds since have been spent covering some of it.
            assertThat(result.estimatedArrival())
                    .isEqualTo(fixAt.plusSeconds(result.remainingSeconds()));
        }

        /** A rider standing on the doorstep has arrived; the maths must agree. */
        @Test
        void a_rider_already_at_the_door_has_no_distance_left() {
            order("PICKED_UP", true);
            riderAt(DROPOFF, Instant.now());

            assertThat(ask().remainingMetres()).isCloseTo(0d, within(1d));
        }

        /**
         * Before collection the journey is rider → restaurant → customer. Measuring straight to the
         * customer would make the ETA improve as the rider drove away from the food.
         */
        @Test
        void before_pickup_the_estimate_covers_both_legs() {
            order("READY", true);
            // 15 km on the far side of the customer from the restaurant, so a straight-to-customer
            // measurement and a via-the-restaurant one cannot be confused.
            riderAt(new GeoPoint(34.0162, 35.7982), Instant.now());

            EtaResult result = ask();

            assertThat(result.leg()).isEqualTo(Leg.TO_PICKUP);
            // Rider→pickup (30.5 km) plus pickup→dropoff (15.3 km). The direct rider→customer hop
            // is 15.3 km, so a shortcut would be off by a factor of three and unmissable here.
            assertThat(result.remainingMetres()).isCloseTo(45_812d, within(100d));
        }

        @Test
        void once_the_rider_is_carrying_it_the_estimate_is_the_run_to_the_customer() {
            order("PICKED_UP", true);
            riderAt(PICKUP, Instant.now());

            assertThat(ask().leg()).isEqualTo(Leg.TO_DROPOFF);
        }

        /**
         * An arrival instant in the past is a contradiction, not a prediction — a screen would
         * render it as "arrived" for a rider who is visibly still on the road.
         */
        @Test
        void an_overdue_estimate_is_reported_as_imminent_rather_than_in_the_past() {
            order("PICKED_UP", true);
            // Four minutes old: inside the five-minute fix window, but the fifteen-minute journey
            // measured from it would still land in the future, so shorten the journey instead.
            riderAt(new GeoPoint(33.9549, 35.6499), Instant.now().minus(Duration.ofMinutes(4)));

            EtaResult result = ask();

            assertThat(result.estimatedArrival()).isAfterOrEqualTo(result.computedAt());
        }

        /** The number and its provenance travel together, always. */
        @Test
        void the_answer_names_the_provider_that_computed_it() {
            order("PICKED_UP", true);
            riderAt(PICKUP, Instant.now());

            assertThat(ask().provider()).isEqualTo(HaversineRouteProvider.NAME);
        }
    }

    @Nested
    @DisplayName("who may ask")
    class Authorisation {

        /**
         * Checked here as well as inside TrackingService, so the unavailable reasons above cannot
         * become an oracle: a stranger must not learn whether an order has a rider, a fix or a
         * destination.
         */
        @Test
        void a_stranger_is_refused_before_learning_anything_about_the_order() {
            order("PICKED_UP", true);

            assertThatThrownBy(() -> eta.estimateFor(ORDER, "stranger-sub", false))
                    .isInstanceOf(TrackingService.TrackingNotFoundException.class);

            verify(tracking, never()).currentPosition(any(UUID.class), anyString(), anyBoolean());
        }

        @Test
        void backoffice_may_ask_about_any_order() {
            order("PICKED_UP", true);
            riderAt(PICKUP, Instant.now());

            assertThat(eta.estimateFor(ORDER, "backoffice-sub", true).available()).isTrue();
        }

        @Test
        void an_unknown_order_is_refused() {
            when(participants.findById(ORDER)).thenReturn(Optional.empty());

            assertThatThrownBy(() -> ask())
                    .isInstanceOf(TrackingService.TrackingNotFoundException.class);
        }
    }
}
