package com.delivery.product.domain;

import java.math.BigDecimal;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * The rules a coordinate has to pass before it can reach the database or a map.
 *
 * <p>These matter more than the arithmetic below them. A bad coordinate does not throw anywhere
 * useful on its own — it simply puts a shop somewhere it is not, and nothing downstream can tell
 * that from a shop that really is there.
 */
@DisplayName("a coordinate")
class GeoPointTest {

    @Nested
    @DisplayName("outside the ranges that exist")
    class OutOfRange {

        @ParameterizedTest(name = "({0}, {1}) is refused")
        @CsvSource({
                "90.000001,  35.5",
                "-90.000001, 35.5",
                "91,         35.5",
                "-500,       35.5",
                "33.8,       180.000001",
                "33.8,       -180.000001",
                "33.8,       181",
                "33.8,       -900"
        })
        void is_refused(String latitude, String longitude) {
            assertThatThrownBy(() -> new GeoPoint(new BigDecimal(latitude), new BigDecimal(longitude)))
                    .isInstanceOf(GeoPoint.InvalidCoordinateException.class);
        }

        /** The boundaries themselves are real places — the poles and the antimeridian. */
        @ParameterizedTest(name = "({0}, {1}) is accepted")
        @CsvSource({
                "90,  0.0001",
                "-90, 0.0001",
                "0.0001, 180",
                "0.0001, -180"
        })
        void the_boundary_itself_is_accepted(String latitude, String longitude) {
            assertThatCode(() -> new GeoPoint(new BigDecimal(latitude), new BigDecimal(longitude)))
                    .doesNotThrowAnyException();
        }
    }

    @Nested
    @DisplayName("that is not really a coordinate")
    class NotACoordinate {

        /**
         * The one rejection that surprises people. (0, 0) is a genuine point in the Gulf of Guinea
         * and is essentially never the one anybody meant — it is what an uninitialised float, a
         * dropped form field and a failed parse all produce.
         */
        @Test
        void null_island_is_refused_because_it_is_almost_always_an_unset_field() {
            assertThatThrownBy(() -> GeoPoint.of(0d, 0d))
                    .isInstanceOf(GeoPoint.InvalidCoordinateException.class)
                    .hasMessageContaining("(0, 0)");
        }

        /** A zero on one axis alone is an ordinary place, and must not be caught by that rule. */
        @Test
        void a_zero_on_one_axis_alone_is_a_real_place() {
            assertThatCode(() -> GeoPoint.of(0d, 9.05d)).doesNotThrowAnyException();
            assertThatCode(() -> GeoPoint.of(51.48d, 0d)).doesNotThrowAnyException();
        }

        @Test
        void half_a_pin_is_refused() {
            assertThatThrownBy(() -> new GeoPoint(new BigDecimal("33.89"), null))
                    .isInstanceOf(GeoPoint.InvalidCoordinateException.class);
            assertThatThrownBy(() -> new GeoPoint(null, new BigDecimal("35.50")))
                    .isInstanceOf(GeoPoint.InvalidCoordinateException.class);
        }

        /** Neither set is "this shop has no pin", which every read site has to be able to express. */
        @Test
        void neither_set_is_no_pin_at_all_rather_than_an_error() {
            assertThat(GeoPoint.ofNullable(null, null)).isNull();
        }

        @Test
        void but_one_of_the_two_being_set_is_still_an_error() {
            assertThatThrownBy(() -> GeoPoint.ofNullable(new BigDecimal("33.89"), null))
                    .isInstanceOf(GeoPoint.InvalidCoordinateException.class);
        }
    }

    @Nested
    @DisplayName("stored to the precision of the column")
    class Precision {

        /**
         * Normalised here rather than left to Postgres to round, so the value this service returns
         * is the value it wrote — otherwise a merchant sees their pin change after saving it.
         */
        @Test
        void is_rounded_to_six_decimal_places() {
            GeoPoint point = new GeoPoint(
                    new BigDecimal("33.8937912345"), new BigDecimal("35.5017894999"));

            assertThat(point.latitude()).isEqualByComparingTo("33.893791");
            assertThat(point.longitude()).isEqualByComparingTo("35.501789");
            assertThat(point.latitude().scale()).isEqualTo(6);
        }

        /** Rounding must not be able to create Null Island out of a point that was not there. */
        @Test
        void a_point_that_rounds_towards_zero_is_still_not_null_island() {
            assertThatCode(() -> new GeoPoint(new BigDecimal("0.0000004"), new BigDecimal("9.05")))
                    .doesNotThrowAnyException();
        }
    }

    @Nested
    @DisplayName("measured against another")
    class Distance {

        // Two junctions in Beirut, roughly 1.5 km apart on the map.
        private static final GeoPoint HAMRA = GeoPoint.of(33.897700d, 35.482900d);
        private static final GeoPoint DOWNTOWN = GeoPoint.of(33.895800d, 35.500900d);

        @Test
        void is_zero_from_a_point_to_itself() {
            assertThat(HAMRA.distanceMetresTo(HAMRA)).isZero();
        }

        @Test
        void is_the_same_in_both_directions() {
            assertThat(HAMRA.distanceMetresTo(DOWNTOWN))
                    .isCloseTo(DOWNTOWN.distanceMetresTo(HAMRA), within(0.001d));
        }

        /**
         * A known pair, checked against an independent calculation to within a few metres. The point
         * is not the exact figure — it is that the formula is not out by a factor, a hemisphere or a
         * swapped axis, all of which produce plausible-looking numbers.
         */
        @Test
        void matches_the_real_distance_between_two_known_points() {
            assertThat(HAMRA.distanceMetresTo(DOWNTOWN)).isCloseTo(1_672d, within(20d));
        }

        /** A degree of latitude is about 111 km everywhere, which is the easiest sanity check there is. */
        @Test
        void a_degree_of_latitude_is_about_111_kilometres() {
            assertThat(GeoPoint.of(33d, 35d).distanceMetresTo(GeoPoint.of(34d, 35d)))
                    .isCloseTo(111_195d, within(500d));
        }

        /**
         * A degree of longitude shrinks towards the poles. Getting the two axes the wrong way round
         * is the commonest geocoding bug there is, and this is what catches it.
         */
        @Test
        void a_degree_of_longitude_is_shorter_away_from_the_equator() {
            double atEquator = GeoPoint.of(0.0001d, 35d).distanceMetresTo(GeoPoint.of(0.0001d, 36d));
            double inBeirut = GeoPoint.of(33.9d, 35d).distanceMetresTo(GeoPoint.of(33.9d, 36d));

            assertThat(inBeirut).isLessThan(atEquator);
            assertThat(inBeirut).isCloseTo(atEquator * Math.cos(Math.toRadians(33.9d)), within(500d));
        }

        private static org.assertj.core.data.Offset<Double> within(double tolerance) {
            return org.assertj.core.data.Offset.offset(tolerance);
        }
    }
}
