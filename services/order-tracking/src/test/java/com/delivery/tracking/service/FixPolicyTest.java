package com.delivery.tracking.service;

import java.time.Duration;
import java.time.Instant;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import com.delivery.tracking.service.FixPolicy.FixRejectedException;
import com.delivery.tracking.service.FixPolicy.Previous;
import com.delivery.tracking.service.FixPolicy.Reason;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * Which reported positions are believed.
 *
 * <p>Every case is a handset doing something handsets really do: an "approximate location"
 * permission, a clock set by hand, a report drained from a queue after a tunnel, a multipath
 * glitch, and the old simulator's rider in London. The shipped limits are used throughout, so a
 * change to a default shows up here as a changed expectation rather than passing silently.
 */
@DisplayName("which rider positions are believed")
class FixPolicyTest {

    private static final Instant NOW = Instant.parse("2026-09-19T10:00:00Z");

    /** Downtown Beirut, and one degree of latitude in metres on the provider's sphere. */
    private static final double LAT = 33.8938;
    private static final double LNG = 35.5018;
    private static final double METRES_PER_DEGREE_LAT = 111_195.08;

    private final FixPolicy policy = FixPolicy.defaults();

    private static Fix fix(double lat, double lng, Float accuracyM, Instant takenAt) {
        return new Fix(lat, lng, accuracyM, takenAt);
    }

    /** A point {@code metres} due north of downtown Beirut. */
    private static double north(double metres) {
        return LAT + metres / METRES_PER_DEGREE_LAT;
    }

    private Reason refusal(Fix fix, Previous previous) {
        try {
            policy.admit(fix, previous, NOW);
        } catch (FixRejectedException e) {
            return e.reason();
        }
        throw new AssertionError("Expected the fix to be refused");
    }

    @Nested
    @DisplayName("how precise it is")
    class Accuracy {

        @Test
        void a_fix_exactly_as_precise_as_the_limit_is_accepted() {
            assertThat(policy.admit(fix(LAT, LNG, 100f, NOW), null, NOW)).isEqualTo(NOW);
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

        /** Older app builds never sent an accuracy; refusing them would be a contract change. */
        @Test
        void a_fix_that_does_not_say_how_precise_it_is_is_accepted() {
            assertThat(policy.admit(fix(LAT, LNG, null, NOW), null, NOW)).isEqualTo(NOW);
        }
    }

    @Nested
    @DisplayName("when it was taken")
    class Timing {

        @Test
        void is_recorded_at_the_moment_the_phone_took_it() {
            Instant takenAt = NOW.minusSeconds(8);

            assertThat(policy.admit(fix(LAT, LNG, 6f, takenAt), null, NOW)).isEqualTo(takenAt);
        }

        /** What every report was before the field existed: stamped on arrival. */
        @Test
        void a_fix_with_no_time_is_stamped_on_arrival() {
            assertThat(policy.admit(fix(LAT, LNG, 6f, null), null, NOW)).isEqualTo(NOW);
        }

        /** A phone a few seconds fast is normal; nothing is ever stored in the future, though. */
        @Test
        void a_fix_slightly_ahead_of_our_clock_is_recorded_as_now() {
            assertThat(policy.admit(fix(LAT, LNG, 6f, NOW.plusSeconds(20)), null, NOW))
                    .isEqualTo(NOW);
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

            assertThat(policy.admit(fix(LAT, LNG, 6f, takenAt), null, NOW)).isEqualTo(takenAt);
        }
    }

    @Nested
    @DisplayName("where it is, against the last fix accepted")
    class Movement {

        /** Recording it would walk the rider backwards on every map watching them. */
        @Test
        void a_fix_older_than_the_last_one_accepted_is_refused() {
            Previous last = new Previous(LAT, LNG, 6f, NOW.minusSeconds(5));

            assertThat(refusal(fix(LAT, LNG, 6f, NOW.minusSeconds(10)), last))
                    .isEqualTo(Reason.FIX_OUT_OF_ORDER);
        }

        /** One fix goes to every order the rider carries; the second copy is not a jump. */
        @Test
        void the_same_fix_reported_on_a_second_order_is_accepted() {
            Instant takenAt = NOW.minusSeconds(2);
            Previous last = new Previous(LAT, LNG, 6f, takenAt);

            assertThat(policy.admit(fix(LAT, LNG, 6f, takenAt), last, NOW)).isEqualTo(takenAt);
        }

        /** 300 m in 20 s is 54 km/h — a scooter on a clear road. */
        @Test
        void a_scooter_at_city_speed_is_accepted() {
            Previous last = new Previous(LAT, LNG, 6f, NOW.minusSeconds(20));

            assertThat(policy.admit(fix(north(300), LNG, 6f, NOW), last, NOW)).isEqualTo(NOW);
        }

        /** Three kilometres in ten seconds is a multipath glitch, not a rider. */
        @Test
        void a_jump_of_kilometres_in_seconds_is_refused() {
            Previous last = new Previous(LAT, LNG, 6f, NOW.minusSeconds(10));

            assertThat(refusal(fix(north(3_000), LNG, 6f, NOW), last))
                    .isEqualTo(Reason.IMPLAUSIBLE_JUMP);
        }

        /**
         * The old simulator's last point, and the case this whole policy was written for: a rider
         * "in London" whose next report is from Beirut.
         */
        @Test
        void london_to_beirut_in_twenty_seconds_is_refused() {
            Previous london = new Previous(51.5074, -0.1278, 8f, NOW.minusSeconds(20));

            assertThat(refusal(fix(LAT, LNG, 6f, NOW), london)).isEqualTo(Reason.IMPLAUSIBLE_JUMP);
        }

        /**
         * 150 m in one second is too fast for two sharp fixes (42 m of travel, 10 m of radii and
         * 50 m of slack reach 102 m) but not for two fixes that each admit 40 m of doubt (172 m):
         * the handset's own uncertainty is part of what is reachable.
         */
        @Test
        void the_fixes_own_uncertainty_widens_what_is_reachable() {
            Previous sharp = new Previous(LAT, LNG, 5f, NOW.minusSeconds(1));
            Previous vague = new Previous(LAT, LNG, 40f, NOW.minusSeconds(1));

            assertThat(refusal(fix(north(150), LNG, 5f, NOW), sharp))
                    .isEqualTo(Reason.IMPLAUSIBLE_JUMP);
            assertThat(policy.admit(fix(north(150), LNG, 40f, NOW), vague, NOW)).isEqualTo(NOW);
        }

        /**
         * The anchor forgets. Without this, one bad fix that got through — or the London point
         * above — would refuse an honest rider for hours; with it, for at most five minutes.
         */
        @Test
        void an_anchor_older_than_the_window_is_not_compared_with() {
            Previous london = new Previous(51.5074, -0.1278, 8f, NOW.minus(Duration.ofMinutes(6)));

            assertThat(policy.admit(fix(LAT, LNG, 6f, NOW), london, NOW)).isEqualTo(NOW);
        }

        @Test
        void a_first_fix_has_nothing_to_be_compared_with() {
            assertThat(policy.admit(fix(LAT, LNG, 6f, NOW), null, NOW)).isEqualTo(NOW);
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
