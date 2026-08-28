package com.delivery.tracking.service;

import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import com.delivery.tracking.domain.CarrierMembership;
import com.delivery.tracking.domain.CarrierMembershipRepository;
import com.delivery.tracking.domain.DutySession;
import com.delivery.tracking.domain.DutySessionRepository;
import com.delivery.tracking.domain.DutyState;
import com.delivery.tracking.domain.RiderDutyEvent;
import com.delivery.tracking.domain.RiderPresence;
import com.delivery.tracking.domain.RiderPresenceRepository;
import com.delivery.tracking.service.DutySessionService.HoursOnline;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * How long a rider worked, computed from what actually happened.
 *
 * <p>The number on the stat tile is the number payroll will eventually stand behind, so every rule
 * here errs the same way: only evidence counts. A day with no shift does not appear, a shift with
 * no sighting is worth zero, and a rider who went silent is credited up to the moment their phone
 * last spoke — never up to the moment the platform happened to notice the silence.
 */
class DutySessionServiceTest {

    private static final String RIDER = "rider-sub";
    private static final String DISPATCHER = "dispatcher-sub";
    private static final UUID CARRIER = UUID.randomUUID();
    private static final UUID OTHER_CARRIER = UUID.randomUUID();

    /** Mid-morning UTC, so tests can place sessions either side of a midnight they control. */
    private static final Instant NOW = Instant.parse("2026-08-27T10:00:00Z");
    private static final LocalDate TODAY = LocalDate.parse("2026-08-27");
    private static final Duration PRESENCE_WINDOW = Duration.ofMinutes(2);
    private static final Duration EXPIRE_AFTER = Duration.ofHours(4);

    private DutySessionRepository sessions;
    private RiderPresenceRepository presenceRows;
    private CarrierMembershipRepository memberships;
    private PresenceService presence;
    private DutySessionService service;

    @BeforeEach
    void setUp() {
        sessions = mock(DutySessionRepository.class);
        presenceRows = mock(RiderPresenceRepository.class);
        memberships = mock(CarrierMembershipRepository.class);
        presence = mock(PresenceService.class);

        when(sessions.findOverlapping(anyString(), any(), any())).thenReturn(List.of());
        when(presenceRows.findById(anyString())).thenReturn(Optional.empty());
        when(memberships.findById(anyString())).thenReturn(Optional.empty());

        service = new DutySessionService(sessions, presenceRows, memberships, presence,
                "UTC", PRESENCE_WINDOW, EXPIRE_AFTER);
    }

    private DutySession closed(Instant from, Instant to) {
        DutySession session = DutySession.open(RIDER, from);
        session.close(to, DutySession.EndReason.RIDER);
        return session;
    }

    private void sessionsAre(DutySession... rows) {
        when(sessions.findOverlapping(eq(RIDER), any(), any())).thenReturn(List.of(rows));
    }

    /** A presence row whose last sighting is at {@code lastSeen}, or never if null. */
    private RiderPresence lastSeenAt(Instant lastSeen) {
        RiderPresence row = RiderPresence.firstSeen(RIDER, NOW.minus(Duration.ofDays(30)));
        if (lastSeen != null) {
            row.sighted(33.89, 35.50, 5.0f, lastSeen);
        }
        when(presenceRows.findById(RIDER)).thenReturn(Optional.of(row));
        return row;
    }

    @Nested
    @DisplayName("summing hours per day")
    class Summing {

        /** History starts now, and an empty history is an empty list — not a row of zeros. */
        @Test
        void a_rider_with_no_sessions_gets_an_empty_list() {
            HoursOnline result = service.aggregate(RIDER, 7, NOW);

            assertThat(result.days()).isEmpty();
            assertThat(result.from()).isEqualTo(TODAY.minusDays(6));
            assertThat(result.to()).isEqualTo(TODAY);
            assertThat(result.zone()).isEqualTo("UTC");
        }

        @Test
        void a_closed_shift_contributes_exactly_its_interval() {
            sessionsAre(closed(Instant.parse("2026-08-27T08:00:00Z"),
                    Instant.parse("2026-08-27T09:30:00Z")));

            HoursOnline result = service.aggregate(RIDER, 7, NOW);

            assertThat(result.days()).singleElement().satisfies(day -> {
                assertThat(day.date()).isEqualTo(TODAY);
                assertThat(day.secondsOnline()).isEqualTo(5400L);
                assertThat(day.hoursOnline()).isEqualByComparingTo("1.50");
                assertThat(day.sessions()).isEqualTo(1);
            });
        }

        /**
         * The split this feature was specified around: a 23:00–01:00 shift is one hour on each day,
         * never two hours on whichever day the query happened to run.
         */
        @Test
        void a_shift_crossing_midnight_is_split_at_the_boundary() {
            sessionsAre(closed(Instant.parse("2026-08-26T23:00:00Z"),
                    Instant.parse("2026-08-27T01:00:00Z")));

            HoursOnline result = service.aggregate(RIDER, 7, NOW);

            assertThat(result.days()).hasSize(2);
            assertThat(result.days().get(0).date()).isEqualTo(TODAY.minusDays(1));
            assertThat(result.days().get(0).secondsOnline()).isEqualTo(3600L);
            assertThat(result.days().get(1).date()).isEqualTo(TODAY);
            assertThat(result.days().get(1).secondsOnline()).isEqualTo(3600L);
        }

        /** A shift that began before the window still worked hours inside it — clipped, not lost. */
        @Test
        void a_shift_older_than_the_window_is_clipped_at_the_window_start() {
            sessionsAre(closed(Instant.parse("2026-08-26T20:00:00Z"),
                    Instant.parse("2026-08-27T02:00:00Z")));

            HoursOnline result = service.aggregate(RIDER, 1, NOW);

            assertThat(result.days()).singleElement().satisfies(day -> {
                assertThat(day.date()).isEqualTo(TODAY);
                assertThat(day.secondsOnline()).isEqualTo(7200L);
            });
        }

        /** The live tile: a running shift whose rider is still present counts up to this moment. */
        @Test
        void a_running_shift_with_a_fresh_rider_counts_up_to_now() {
            sessionsAre(DutySession.open(RIDER, Instant.parse("2026-08-27T08:00:00Z")));
            lastSeenAt(NOW.minusSeconds(30));

            HoursOnline result = service.aggregate(RIDER, 7, NOW);

            assertThat(result.days()).singleElement()
                    .satisfies(day -> assertThat(day.secondsOnline()).isEqualTo(7200L));
        }

        /**
         * A rider who went quiet is credited to their last sighting — the same instant expiry will
         * close the session at, so the live number never shrinks when the sweep catches up.
         */
        @Test
        void a_running_shift_whose_rider_went_quiet_counts_only_to_the_last_sighting() {
            sessionsAre(DutySession.open(RIDER, Instant.parse("2026-08-27T06:00:00Z")));
            lastSeenAt(Instant.parse("2026-08-27T08:00:00Z"));

            HoursOnline result = service.aggregate(RIDER, 7, NOW);

            assertThat(result.days()).singleElement()
                    .satisfies(day -> assertThat(day.secondsOnline()).isEqualTo(7200L));
        }

        /** No sighting during the shift means no evidence of work, and no evidence counts as zero. */
        @Test
        void a_running_shift_with_no_sighting_at_all_is_worth_nothing_yet() {
            sessionsAre(DutySession.open(RIDER, Instant.parse("2026-08-27T06:00:00Z")));
            lastSeenAt(null);

            assertThat(service.aggregate(RIDER, 7, NOW).days()).isEmpty();
        }

        @Test
        void two_shifts_on_one_day_are_summed_and_both_counted() {
            sessionsAre(
                    closed(Instant.parse("2026-08-27T07:00:00Z"),
                            Instant.parse("2026-08-27T08:00:00Z")),
                    closed(Instant.parse("2026-08-27T09:00:00Z"),
                            Instant.parse("2026-08-27T09:30:00Z")));

            HoursOnline result = service.aggregate(RIDER, 7, NOW);

            assertThat(result.days()).singleElement().satisfies(day -> {
                assertThat(day.secondsOnline()).isEqualTo(5400L);
                assertThat(day.sessions()).isEqualTo(2);
            });
        }
    }

    @Nested
    @DisplayName("who may read whose hours")
    class Scope {

        private void employs(String userId, UUID carrierId, CarrierMembership.Kind kind) {
            when(memberships.findById(userId)).thenReturn(Optional.of(new CarrierMembership(
                    userId, carrierId, kind, CarrierMembership.Source.ORDER_EVENT)));
        }

        /** Attach the rider's presence row to a fleet, the linkage the roster filters on. */
        private void riderCarriesFor(UUID carrierId) {
            RiderPresence row = RiderPresence.firstSeen(RIDER, NOW.minus(Duration.ofDays(3)));
            row.attachCarrier(carrierId, NOW.minus(Duration.ofDays(3)));
            when(presenceRows.findById(RIDER)).thenReturn(Optional.of(row));
            when(presenceRows.existsById(RIDER)).thenReturn(true);
        }

        @Test
        void backoffice_may_read_any_riders_hours() {
            riderCarriesFor(CARRIER);

            assertThat(service.riderHours(RIDER, "backoffice-sub", true, 7).riderId())
                    .isEqualTo(RIDER);
        }

        /** "No such rider" and "a rider who has not worked yet" are different answers. */
        @Test
        void backoffice_asking_about_an_unknown_rider_gets_not_found_rather_than_an_empty_history() {
            when(presenceRows.existsById("unknown-rider")).thenReturn(false);

            assertThatThrownBy(() -> service.riderHours("unknown-rider", "backoffice-sub", true, 7))
                    .isInstanceOf(PresenceService.PresenceNotFoundException.class);
        }

        @Test
        void a_carrier_may_read_the_hours_of_their_own_rider() {
            employs(DISPATCHER, CARRIER, CarrierMembership.Kind.STAFF);
            riderCarriesFor(CARRIER);

            assertThat(service.riderHours(RIDER, DISPATCHER, false, 7).riderId()).isEqualTo(RIDER);
        }

        /**
         * A competitor's rider gets the same not-found as a rider who does not exist — hours reveal
         * shift patterns, and this endpoint must not enumerate the fleet any more than the location
         * one may.
         */
        @Test
        void a_carrier_may_not_read_another_fleets_rider_and_cannot_tell_they_exist() {
            employs(DISPATCHER, CARRIER, CarrierMembership.Kind.STAFF);
            riderCarriesFor(OTHER_CARRIER);

            assertThatThrownBy(() -> service.riderHours(RIDER, DISPATCHER, false, 7))
                    .isInstanceOf(PresenceService.PresenceNotFoundException.class);
        }

        /** Same non-enumeration rule for an id that simply does not exist. */
        @Test
        void a_carrier_asking_about_an_unknown_rider_gets_the_same_not_found() {
            employs(DISPATCHER, CARRIER, CarrierMembership.Kind.STAFF);

            assertThatThrownBy(() -> service.riderHours("unknown-rider", DISPATCHER, false, 7))
                    .isInstanceOf(PresenceService.PresenceNotFoundException.class);
        }

        /** A provisioning mistake reads as one, exactly as it does on the roster. */
        @Test
        void a_carrier_who_belongs_to_no_company_is_told_so() {
            assertThatThrownBy(() -> service.riderHours(RIDER, DISPATCHER, false, 7))
                    .isInstanceOf(PresenceService.NoCarrierException.class);
        }
    }

    @Nested
    @DisplayName("expiring abandoned shifts")
    class Expiry {

        /**
         * The honesty rule this sweep exists to enforce. The hours between the last sighting and
         * the sweep run are hours nobody can show the rider was working; closing at discovery time
         * would turn a forgotten "go offline" tap into paid time.
         */
        @Test
        void an_abandoned_shift_is_closed_at_the_last_sighting_not_at_discovery_time() {
            Instant lastSeen = NOW.minus(Duration.ofHours(8));
            DutySession open = DutySession.open(RIDER, NOW.minus(Duration.ofHours(10)));
            when(sessions.findAbandonedBefore(NOW.minus(EXPIRE_AFTER))).thenReturn(List.of(open));
            lastSeenAt(lastSeen);

            int closedCount = service.expireAbandoned(NOW);

            assertThat(closedCount).isEqualTo(1);
            assertThat(open.getEndedAt()).isEqualTo(lastSeen);
            assertThat(open.getEndReason()).isEqualTo(DutySession.EndReason.EXPIRED);
            verify(sessions).save(open);
        }

        /** The expired rider is taken off duty through the ordinary path, attributed to SYSTEM. */
        @Test
        void an_expired_rider_is_declared_off_duty_by_the_system() {
            DutySession open = DutySession.open(RIDER, NOW.minus(Duration.ofHours(10)));
            when(sessions.findAbandonedBefore(any())).thenReturn(List.of(open));
            lastSeenAt(NOW.minus(Duration.ofHours(8)));

            service.expireAbandoned(NOW);

            verify(presence).declare(RIDER, DutyState.OFF_DUTY, RiderDutyEvent.Source.SYSTEM);
        }

        /** A shift with no sighting at all has no evidence behind it; its honest length is zero. */
        @Test
        void a_shift_whose_rider_never_pinged_closes_at_its_own_start() {
            Instant start = NOW.minus(Duration.ofHours(10));
            DutySession open = DutySession.open(RIDER, start);
            when(sessions.findAbandonedBefore(any())).thenReturn(List.of(open));
            lastSeenAt(null);

            service.expireAbandoned(NOW);

            assertThat(open.getEndedAt()).isEqualTo(start);
        }

        /** A sighting from before the shift proves nothing about the shift. Clamped, never negative. */
        @Test
        void a_sighting_from_before_the_shift_clamps_the_close_to_the_shift_start() {
            Instant start = NOW.minus(Duration.ofHours(10));
            DutySession open = DutySession.open(RIDER, start);
            when(sessions.findAbandonedBefore(any())).thenReturn(List.of(open));
            lastSeenAt(start.minus(Duration.ofHours(2)));

            service.expireAbandoned(NOW);

            assertThat(open.getEndedAt()).isEqualTo(start);
        }

        @Test
        void a_quiet_night_expires_nothing_and_declares_nothing() {
            when(sessions.findAbandonedBefore(any())).thenReturn(List.of());

            assertThat(service.expireAbandoned(NOW)).isZero();
            verify(presence, never()).declare(anyString(), any(), any());
        }
    }
}
