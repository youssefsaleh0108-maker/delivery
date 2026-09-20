package com.delivery.tracking.service;

import java.time.Duration;
import java.time.Instant;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import com.delivery.tracking.service.FixPolicy.Admission;
import com.delivery.tracking.service.FixPolicy.FixRejectedException;
import com.delivery.tracking.service.FixPolicy.Previous;
import com.delivery.tracking.service.FixPolicy.Reason;
import com.delivery.tracking.service.FixPolicy.Skip;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * Which reported positions are believed.
 *
 * <p>Every case is a handset doing something handsets really do: an "approximate location"
 * permission, a clock set by hand, a report drained from a queue after a tunnel, a multipath
 * glitch, an old app build with no fix time, an emulator in Mountain View, and the old simulator's
 * rider in London. The shipped limits are used throughout, so a change to a default shows up here
 * as a changed expectation rather than passing silently.
 */
@DisplayName("which rider positions are believed")
class FixPolicyTest {

    private static final Instant NOW = Instant.parse("2026-09-19T10:00:00Z");

    /** Downtown Beirut, and one degree of latitude in metres on the provider's sphere. */
    private static final double LAT = 33.8938;
    private static final double LNG = 35.5018;
    private static final double METRES_PER_DEGREE_LAT = 111_195.08;

    private static final double LONDON_LAT = 51.5074;
    private static final double LONDON_LNG = -0.1278;
    private static final double MOUNTAIN_VIEW_LAT = 37.4220;
    private static final double MOUNTAIN_VIEW_LNG = -122.0841;

    private final FixPolicy policy = FixPolicy.defaults();
    private final FixPolicy dev = FixPolicy.defaults(false);

    private static Fix fix(double lat, double lng, Float accuracyM, Instant takenAt) {
        return new Fix(lat, lng, accuracyM, takenAt);
    }

    /** A point {@code metres} due north of downtown Beirut. */
    private static double north(double metres) {
        return LAT + metres / METRES_PER_DEGREE_LAT;
    }

    private Instant recordedAt(FixPolicy which, Fix fix, Previous previous) {
        Admission admission = which.admit(fix, previous, NOW);
        assertThat(admission.recorded()).as("recorded, not skipped as %s", admission.skip())
                .isTrue();
        return admission.at();
    }

    private Instant recordedAt(Fix fix, Previous previous) {
        return recordedAt(policy, fix, previous);
    }

    private Reason refusal(FixPolicy which, Fix fix, Previous previous) {
        try {
            which.admit(fix, previous, NOW);
        } catch (FixRejectedException e) {
            return e.reason();
        }
        throw new AssertionError("Expected the fix to be refused");
    }

    private Reason refusal(Fix fix, Previous previous) {
        return refusal(policy, fix, previous);
    }

    @Nested
    @DisplayName("when it was taken")
    class Timing {

        /**
         * Every app build before the field existed. Without a time a report cannot be judged for
         * age at all, which is how a drained queue — or the London walk — would pass as "now".
         */
        @Test
        void a_fix_that_does_not_say_when_it_was_taken_is_refused() {
            assertThat(refusal(fix(LAT, LNG, 6f, null), null)).isEqualTo(Reason.FIX_TIME_MISSING);
            assertThat(refusal(dev, fix(LAT, LNG, 6f, null), null))
                    .as("in dev too: it is not about where the fix is")
                    .isEqualTo(Reason.FIX_TIME_MISSING);
        }

        @Test
        void is_recorded_at_the_moment_the_phone_took_it() {
            Instant takenAt = NOW.minusSeconds(8);

            assertThat(recordedAt(fix(LAT, LNG, 6f, takenAt), null)).isEqualTo(takenAt);
        }

        /** A phone a few seconds fast is normal; nothing is ever stored in the future, though. */
        @Test
        void a_fix_slightly_ahead_of_our_clock_is_recorded_as_now() {
            assertThat(recordedAt(fix(LAT, LNG, 6f, NOW.plusSeconds(20)), null)).isEqualTo(NOW);
        }

        /**
         * A future time would keep a rider "present" on the roster after their phone died, and an
         * ETA measured from it would look fresher than anything real.
         */
        @Test
        void a_fix_dated_beyond_the_clock_allowance_is_refused() {
            assertThat(refusal(fix(LAT, LNG, 6f, NOW.plusSeconds(31)), null))
                    .isEqualTo(Reason.FIX_IN_FUTURE);
            assertThat(refusal(fix(LAT, LNG, 6f, NOW.plus(Duration.ofHours(3))), null))
                    .isEqualTo(Reason.FIX_IN_FUTURE);
        }

        /** A report drained from a queue, or a cached last-known position: where they were. */
        @Test
        void a_fix_older_than_a_minute_is_refused() {
            assertThat(refusal(fix(LAT, LNG, 6f, NOW.minusSeconds(61)), null))
                    .isEqualTo(Reason.FIX_TOO_OLD);
        }

        @Test
        void a_fix_just_inside_the_age_limit_is_accepted() {
            Instant takenAt = NOW.minusSeconds(59);

            assertThat(recordedAt(fix(LAT, LNG, 6f, takenAt), null)).isEqualTo(takenAt);
        }
    }

    @Nested
    @DisplayName("how precise it is")
    class Accuracy {

        @Test
        void a_fix_exactly_as_precise_as_the_limit_is_accepted() {
            assertThat(recordedAt(fix(LAT, LNG, 100f, NOW), null)).isEqualTo(NOW);
        }

        /**
         * What an Android "approximate location" grant produces. Drawn on a customer's map it
         * would put the rider blocks away from where they are.
         */
        @Test
        void a_fix_kilometres_wide_is_refused() {
            assertThat(refusal(fix(LAT, LNG, 2_000f, NOW), null)).isEqualTo(Reason.ACCURACY_TOO_LOW);
        }

        @Test
        void a_fix_just_wider_than_the_limit_is_refused() {
            assertThat(refusal(fix(LAT, LNG, 100.5f, NOW), null)).isEqualTo(Reason.ACCURACY_TOO_LOW);
        }

        /** Not every handset reports a radius; the time is what is required, not this. */
        @Test
        void a_fix_that_does_not_say_how_precise_it_is_is_accepted() {
            assertThat(recordedAt(fix(LAT, LNG, null, NOW), null)).isEqualTo(NOW);
        }
    }

    @Nested
    @DisplayName("where it is")
    class ServiceArea {

        /** The old app build's London walk, and a spoofing app's default city. */
        @Test
        void a_fix_from_london_is_refused_as_outside_the_service_area() {
            assertThat(refusal(fix(LONDON_LAT, LONDON_LNG, 8f, NOW), null))
                    .isEqualTo(Reason.OUTSIDE_SERVICE_AREA);
        }

        @Test
        void an_emulators_mountain_view_is_refused_where_the_area_is_enforced() {
            assertThat(refusal(fix(MOUNTAIN_VIEW_LAT, MOUNTAIN_VIEW_LNG, 5f, NOW), null))
                    .isEqualTo(Reason.OUTSIDE_SERVICE_AREA);
        }

        /** Dev's riders are emulators; dev is the one environment that turns the check off. */
        @Test
        void with_the_area_off_as_in_dev_the_same_fixes_are_accepted() {
            assertThat(recordedAt(dev, fix(MOUNTAIN_VIEW_LAT, MOUNTAIN_VIEW_LNG, 5f, NOW), null))
                    .isEqualTo(NOW);
            assertThat(recordedAt(dev, fix(LONDON_LAT, LONDON_LNG, 8f, NOW), null)).isEqualTo(NOW);
        }

        /** Tripoli in the north, Naqoura in the south, the Bekaa's eastern edge: all inside. */
        @Test
        void the_whole_country_is_inside_it() {
            assertThat(recordedAt(fix(34.4367, 35.8497, 6f, NOW), null)).isEqualTo(NOW);
            assertThat(recordedAt(fix(33.1181, 35.1394, 6f, NOW), null)).isEqualTo(NOW);
            assertThat(recordedAt(fix(34.0047, 36.2110, 6f, NOW), null)).isEqualTo(NOW);
        }

        @Test
        void the_margin_is_about_fifteen_kilometres() {
            // 10 km south of the southern border: inside the margin.
            assertThat(recordedAt(fix(33.05 - 10_000 / METRES_PER_DEGREE_LAT, 35.2, 6f, NOW), null))
                    .isEqualTo(NOW);
            // 20 km south of it: outside.
            assertThat(refusal(fix(33.05 - 20_000 / METRES_PER_DEGREE_LAT, 35.2, 6f, NOW), null))
                    .isEqualTo(Reason.OUTSIDE_SERVICE_AREA);
        }
    }

    @Nested
    @DisplayName("whether it is new, against the last fix accepted")
    class Newness {

        /** The same fix twice — an old build sent one fix to every order it carried. */
        @Test
        void a_fix_dated_the_same_as_the_last_one_is_ignored_not_refused() {
            Previous last = new Previous(LAT, LNG, 6f, NOW.minusSeconds(2));

            Admission admission = policy.admit(fix(LAT, LNG, 6f, NOW.minusSeconds(2)), last, NOW);

            assertThat(admission.recorded()).isFalse();
            assertThat(admission.skip()).isEqualTo(Skip.NOT_NEWER);
        }

        /** Recording it would walk the rider backwards on every map watching them. */
        @Test
        void a_fix_older_than_the_last_one_accepted_is_ignored() {
            Previous last = new Previous(LAT, LNG, 6f, NOW.minusSeconds(5));

            assertThat(policy.admit(fix(LAT, LNG, 6f, NOW.minusSeconds(10)), last, NOW).skip())
                    .isEqualTo(Skip.NOT_NEWER);
        }

        /** The rate floor: no write and no push for a report under five seconds after the last. */
        @Test
        void a_fix_under_five_seconds_after_the_last_one_is_ignored() {
            Previous last = new Previous(LAT, LNG, 6f, NOW.minusMillis(4_900));

            assertThat(policy.admit(fix(north(10), LNG, 6f, NOW), last, NOW).skip())
                    .isEqualTo(Skip.TOO_SOON);
        }

        @Test
        void a_fix_five_seconds_after_the_last_one_is_recorded() {
            Previous last = new Previous(LAT, LNG, 6f, NOW.minusSeconds(5));

            assertThat(recordedAt(fix(north(10), LNG, 6f, NOW), last)).isEqualTo(NOW);
        }

        /** An ignored fix is judged first: nothing is refused for being a duplicate of a good one. */
        @Test
        void a_duplicate_is_ignored_even_where_it_would_have_been_a_jump() {
            Previous last = new Previous(LAT, LNG, 6f, NOW.minusSeconds(1));

            assertThat(policy.admit(fix(north(3_000), LNG, 6f, NOW), last, NOW).skip())
                    .isEqualTo(Skip.TOO_SOON);
        }
    }

    @Nested
    @DisplayName("whether the rider could have got there")
    class Movement {

        /** 300 m in 20 s is 54 km/h — a scooter on a clear road. */
        @Test
        void a_scooter_at_city_speed_is_accepted() {
            Previous last = new Previous(LAT, LNG, 6f, NOW.minusSeconds(20));

            assertThat(recordedAt(fix(north(300), LNG, 6f, NOW), last)).isEqualTo(NOW);
        }

        /** Three kilometres in ten seconds is a multipath glitch, not a rider. */
        @Test
        void a_jump_of_kilometres_in_seconds_is_refused() {
            Previous last = new Previous(LAT, LNG, 6f, NOW.minusSeconds(10));

            assertThat(refusal(fix(north(3_000), LNG, 6f, NOW), last))
                    .isEqualTo(Reason.IMPLAUSIBLE_JUMP);
        }

        /**
         * Six seconds at 150 km/h is 250 m. Two sharp fixes add 10 m of radii and 50 m of slack, so
         * they reach 310 m and 400 m is too far; two fixes that each admit 60 m of doubt reach
         * 420 m, and the same 400 m is believable: the handset's own uncertainty is part of what is
         * reachable.
         */
        @Test
        void the_fixes_own_uncertainty_widens_what_is_reachable() {
            Previous sharp = new Previous(LAT, LNG, 5f, NOW.minusSeconds(6));
            Previous vague = new Previous(LAT, LNG, 60f, NOW.minusSeconds(6));

            assertThat(refusal(fix(north(400), LNG, 5f, NOW), sharp))
                    .isEqualTo(Reason.IMPLAUSIBLE_JUMP);
            assertThat(recordedAt(fix(north(400), LNG, 60f, NOW), vague)).isEqualTo(NOW);
        }

        /**
         * The anchor forgets. Without this, one bad fix that got through would refuse an honest
         * rider for hours; with it, for at most five minutes.
         */
        @Test
        void an_anchor_older_than_the_window_is_not_compared_with() {
            Previous tripoli = new Previous(34.4367, 35.8497, 8f, NOW.minus(Duration.ofMinutes(6)));

            assertThat(recordedAt(fix(LAT, LNG, 6f, NOW), tripoli)).isEqualTo(NOW);
        }

        /**
         * After an upgrade: the last fix the platform holds is the old build's London walk, twenty
         * seconds old. It is outside the service area, so it anchors nothing, and the rider's first
         * real fix is recorded — where the area is enforced and in dev, where it is not.
         */
        @Test
        void the_first_real_fix_after_the_london_walk_is_accepted_in_every_environment() {
            Previous london = new Previous(LONDON_LAT, LONDON_LNG, 8f, NOW.minusSeconds(20));

            assertThat(recordedAt(policy, fix(LAT, LNG, 6f, NOW), london)).isEqualTo(NOW);
            assertThat(recordedAt(dev, fix(LAT, LNG, 6f, NOW), london)).isEqualTo(NOW);
        }

        /** And dev's emulator, having left Mountain View as the anchor, is not judged against it. */
        @Test
        void an_anchor_outside_the_area_is_ignored_even_where_the_area_is_not_enforced() {
            Previous emulator = new Previous(MOUNTAIN_VIEW_LAT, MOUNTAIN_VIEW_LNG, 5f,
                    NOW.minusSeconds(10));

            assertThat(recordedAt(dev, fix(LAT, LNG, 6f, NOW), emulator)).isEqualTo(NOW);
        }

        @Test
        void a_first_fix_has_nothing_to_be_compared_with() {
            assertThat(recordedAt(fix(LAT, LNG, 6f, NOW), null)).isEqualTo(NOW);
            assertThat(Previous.of(null, null, null, null)).isNull();
            assertThat(Previous.of(LAT, LNG, 6f, null)).isNull();
        }
    }

    /** The message goes into an HTTP body a client renders; nothing from the request is in it. */
    @Test
    void a_refusal_names_its_reason_and_echoes_nothing_it_was_sent() {
        assertThatThrownBy(() -> policy.admit(fix(12.3456, 65.4321, 2_000f, NOW), null, NOW))
                .isInstanceOf(FixRejectedException.class)
                .hasMessageNotContaining("12.3456")
                .hasMessageNotContaining("2000")
                .satisfies(e -> assertThat(((FixRejectedException) e).reason())
                        .isEqualTo(Reason.ACCURACY_TOO_LOW));
    }
}
