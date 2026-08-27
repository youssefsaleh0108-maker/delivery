package com.delivery.tracking.route;

import java.time.Duration;
import java.util.Optional;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.assertj.core.api.Assertions.within;

/**
 * The arithmetic behind every ETA the platform can currently produce.
 *
 * <p>Worth pinning to known points rather than to itself. A distance function is the kind of code
 * that is quietly wrong for years — a degrees/radians slip, a transposed pair, the wrong Earth
 * radius — and none of those fail, they just return a plausible number. The reference distances
 * below are independently published great-circle figures, so a regression has to disagree with the
 * world rather than with a value copied out of this implementation.
 */
class HaversineRouteProviderTest {

    /** 60 km/h makes a kilometre take exactly a minute, which keeps the timing assertions readable. */
    private final HaversineRouteProvider provider = new HaversineRouteProvider(60);

    @Nested
    @DisplayName("the distance between two points")
    class Distance {

        /**
         * Paris to London, centre to centre: 343.6 km great-circle by every published figure. The
         * tolerance is 500 m — a tenth of a percent — which is tight enough to catch a wrong Earth
         * radius and loose enough to survive the last digit of the coordinates.
         */
        @Test
        void matches_a_published_great_circle_figure() {
            double metres = HaversineRouteProvider.distanceMetres(
                    new GeoPoint(48.8566, 2.3522),
                    new GeoPoint(51.5074, -0.1278));

            assertThat(metres).isCloseTo(343_556, within(500.0));
        }

        /** A short urban hop, the length almost every real delivery actually is. */
        @Test
        void is_right_at_the_scale_a_delivery_is_measured_in() {
            double metres = HaversineRouteProvider.distanceMetres(
                    new GeoPoint(33.8938, 35.5018),
                    new GeoPoint(33.9550, 35.6500));

            assertThat(metres).isCloseTo(15_274, within(50.0));
        }

        /**
         * The formula is symmetric, and a lat/lng transposition would break that in most of the
         * world — this is the cheapest guard against the argument order silently reversing.
         */
        @Test
        void does_not_depend_on_which_end_you_start_from() {
            GeoPoint a = new GeoPoint(33.8938, 35.5018);
            GeoPoint b = new GeoPoint(33.9550, 35.6500);

            assertThat(HaversineRouteProvider.distanceMetres(a, b))
                    .isCloseTo(HaversineRouteProvider.distanceMetres(b, a), within(0.001));
        }

        /** Zero, not a rounding artefact: a rider standing on the doorstep has arrived. */
        @Test
        void is_zero_when_the_two_points_are_the_same() {
            GeoPoint here = new GeoPoint(33.8938, 35.5018);

            assertThat(HaversineRouteProvider.distanceMetres(here, here)).isZero();
        }

        /** Crossing the antimeridian is a sign error waiting to happen in a naive implementation. */
        @Test
        void survives_a_pair_that_straddles_the_antimeridian() {
            double metres = HaversineRouteProvider.distanceMetres(
                    new GeoPoint(0, 179.9),
                    new GeoPoint(0, -179.9));

            // 0.2 degrees of longitude at the equator, and emphatically not most of the way round.
            assertThat(metres).isCloseTo(22_240, within(100.0));
        }
    }

    @Nested
    @DisplayName("the estimate it produces")
    class Estimating {

        @Test
        void turns_distance_into_time_at_the_configured_average_speed() {
            Optional<RouteEstimate> estimate = provider.estimate(
                    new GeoPoint(0, 0), new GeoPoint(0, 0.0899322));

            // ~10 km at 60 km/h is ten minutes. The tolerance absorbs the coordinate rounding.
            assertThat(estimate).hasValueSatisfying(route ->
                    assertThat(route.travelTime()).isCloseTo(Duration.ofMinutes(10),
                            Duration.ofSeconds(5)));
        }

        /**
         * The provider name travels with the number, which is the whole reason a caller can tell a
         * straight-line guess from a routed answer.
         */
        @Test
        void is_labelled_as_the_dev_estimator_it_is() {
            assertThat(provider.estimate(new GeoPoint(0, 0), new GeoPoint(1, 1)))
                    .hasValueSatisfying(route ->
                            assertThat(route.provider()).isEqualTo("HAVERSINE_DEV"));
        }

        /** It needs nothing but arithmetic, which is exactly what makes it the dev provider. */
        @Test
        void is_always_available() {
            assertThat(provider.isConfigured()).isTrue();
        }

        /** A zero speed would divide by zero on a customer's screen; refuse it at startup instead. */
        @Test
        void refuses_to_start_with_a_speed_that_cannot_produce_a_time() {
            assertThatThrownBy(() -> new HaversineRouteProvider(0))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessageContaining("average-speed-kmh");
        }
    }

    @Nested
    @DisplayName("a coordinate")
    class Coordinates {

        /** Half a coordinate is not a location — and zero-filling it lands in the Gulf of Guinea. */
        @Test
        void is_absent_unless_both_halves_are_present() {
            assertThat(GeoPoint.of(33.89, null)).isEmpty();
            assertThat(GeoPoint.of(null, 35.50)).isEmpty();
            assertThat(GeoPoint.of(33.89, 35.50)).isPresent();
        }

        /** Rejected at construction, so a value that arrived on a message is checked too. */
        @Test
        void outside_the_possible_range_is_refused() {
            assertThatThrownBy(() -> new GeoPoint(91, 0))
                    .isInstanceOf(IllegalArgumentException.class);
            assertThatThrownBy(() -> new GeoPoint(0, 181))
                    .isInstanceOf(IllegalArgumentException.class);
        }
    }
}
