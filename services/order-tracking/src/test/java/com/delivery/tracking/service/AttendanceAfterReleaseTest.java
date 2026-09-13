package com.delivery.tracking.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.assertj.core.api.Assertions.catchThrowable;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.time.Duration;
import java.time.Instant;
import java.time.LocalTime;
import java.time.YearMonth;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

import org.assertj.core.api.ThrowableAssert.ThrowingCallable;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;

import com.delivery.tracking.client.CarrierDirectoryClient;
import com.delivery.tracking.domain.AttendanceEntryRepository;
import com.delivery.tracking.domain.CarrierMembershipPeriod;
import com.delivery.tracking.domain.CarrierMembershipPeriodRepository;
import com.delivery.tracking.domain.DutySession;
import com.delivery.tracking.domain.DutySessionRepository;
import com.delivery.tracking.domain.RiderPresence;
import com.delivery.tracking.domain.RiderPresenceRepository;
import com.delivery.tracking.domain.RiderShiftAssignment;
import com.delivery.tracking.domain.RiderShiftAssignmentRepository;
import com.delivery.tracking.domain.ShiftTemplateRepository;
import com.delivery.tracking.service.AttendanceService.AttendanceDay;
import com.delivery.tracking.service.AttendanceService.FleetAttendance;
import com.delivery.tracking.service.AttendanceService.RiderAttendance;
import com.delivery.tracking.service.AttendanceService.RiderTotals;
import com.delivery.tracking.service.DutySessionService.SessionView;

/**
 * A company's sight of a rider's attendance ends when the rider leaves it, and never reaches into
 * the rider's time with anybody else.
 *
 * <p>One rider, moving from one company to another at 13:00 on the 18th of last month. The real
 * {@link FleetMembershipGuard} decides throughout: Order Manager, through a stubbed directory, says
 * who is on each dispatcher's fleet now, and a membership record held in memory says when the rider
 * was whose. The rider's linkage ({@code rider_presence.carrier_id}) is left pointing wherever each
 * case needs it — for the company left behind, at that company, which is what a late or lost
 * membership event leaves.
 */
@DisplayName("attendance for a rider who changed company")
class AttendanceAfterReleaseTest {

    private static final ZoneId BEIRUT = ZoneId.of("Asia/Beirut");
    private static final String RIDER = "rider-moving";
    private static final String OLD_DISPATCHER = "old-dispatcher";
    private static final String OLD_TOKEN = "old-token";
    private static final String NEW_DISPATCHER = "new-dispatcher";
    private static final String NEW_TOKEN = "new-token";
    private static final String OPERATOR = "op-1";
    private static final UUID OLD_FLEET = UUID.fromString("5857ac51-0000-4000-8000-00000000000a");
    private static final UUID NEW_FLEET = UUID.fromString("5857ac51-0000-4000-8000-00000000000b");

    /** Last month in Beirut: wholly past, and well inside the duty history. */
    private static final YearMonth MONTH = YearMonth.now(BEIRUT).minusMonths(1);
    private static final AttendancePeriod PERIOD =
            new AttendancePeriod(MONTH.atDay(1), MONTH.atEndOfMonth());

    /** When the rider left the old company for the new one. */
    private static final Instant MOVED = at(18, "13:00");

    private final List<DutySession> sessionRows = new ArrayList<>();
    private final List<CarrierMembershipPeriod> periodRows = new ArrayList<>();

    private RiderPresenceRepository presenceRows;
    private RiderShiftAssignmentRepository assignments;
    private AttendanceEntryRepository entries;
    private AttendanceService attendance;

    private static Instant at(int day, String time) {
        return MONTH.atDay(day).atTime(LocalTime.parse(time)).atZone(BEIRUT).toInstant();
    }

    @BeforeEach
    void setUp() {
        DutySessionRepository sessions = mock(DutySessionRepository.class);
        CarrierMembershipPeriodRepository periods = mock(CarrierMembershipPeriodRepository.class);
        CarrierDirectoryClient directory = mock(CarrierDirectoryClient.class);
        CarrierScopeResolver carrierScope = mock(CarrierScopeResolver.class);
        presenceRows = mock(RiderPresenceRepository.class);
        assignments = mock(RiderShiftAssignmentRepository.class);
        entries = mock(AttendanceEntryRepository.class);

        // Four hours on the 5th for the old company; 09:00-17:00 on the 18th, across the move; and
        // two hours on the 25th for the new one. Fourteen hours in all.
        worked(5, "08:00", "12:00");
        worked(18, "09:00", "17:00");
        worked(25, "08:00", "10:00");
        when(sessions.findOverlapping(eq(RIDER), any(), any())).thenAnswer(call -> {
            Instant from = call.getArgument(1);
            Instant until = call.getArgument(2);
            return sessionRows.stream()
                    .filter(s -> s.getStartedAt().isBefore(until) && s.getEndedAt().isAfter(from))
                    .toList();
        });

        // The record: on the old fleet for months, then the new one from the move. And a second
        // rider who left the old company the day before the month began.
        CarrierMembershipPeriod oldSpell = CarrierMembershipPeriod.open(RIDER, OLD_FLEET,
                at(1, "09:00").minus(Duration.ofDays(180)));
        oldSpell.endAt(MOVED);
        periodRows.add(oldSpell);
        periodRows.add(CarrierMembershipPeriod.open(RIDER, NEW_FLEET, MOVED));
        CarrierMembershipPeriod gone = CarrierMembershipPeriod.open("rider-gone", OLD_FLEET,
                at(1, "09:00").minus(Duration.ofDays(90)));
        gone.endAt(at(1, "12:00").minus(Duration.ofDays(1)));
        periodRows.add(gone);
        when(periods.overlappingForRider(any(), anyString(), any(), any())).thenAnswer(call ->
                periodRows.stream()
                        .filter(p -> p.getCarrierId().equals(call.getArgument(0))
                                && p.getRiderId().equals(call.getArgument(1))
                                && overlaps(p, call.getArgument(2), call.getArgument(3)))
                        .sorted(Comparator.comparing(CarrierMembershipPeriod::getJoinedAt))
                        .toList());
        when(periods.overlappingForCarrier(any(), any(), any())).thenAnswer(call ->
                periodRows.stream()
                        .filter(p -> p.getCarrierId().equals(call.getArgument(0))
                                && overlaps(p, call.getArgument(1), call.getArgument(2)))
                        .sorted(Comparator.comparing(CarrierMembershipPeriod::getRiderId)
                                .thenComparing(CarrierMembershipPeriod::getJoinedAt))
                        .toList());
        when(periods.findByRiderIdAndLeftAtIsNull(anyString())).thenAnswer(call ->
                periodRows.stream()
                        .filter(p -> p.getRiderId().equals(call.getArgument(0)) && p.isOpen())
                        .findFirst());

        // Order Manager, asked with each dispatcher's own token: the rider is the new company's now.
        when(directory.ridersFor(OLD_TOKEN)).thenReturn(Set.of());
        when(directory.ridersFor(NEW_TOKEN)).thenReturn(Set.of(RIDER));
        when(carrierScope.requireScopeFor(OLD_DISPATCHER)).thenReturn(OLD_FLEET);
        when(carrierScope.requireScopeFor(NEW_DISPATCHER)).thenReturn(NEW_FLEET);

        FleetMembershipGuard guard = new FleetMembershipGuard(directory, periods, Duration.ofSeconds(30));
        DutySessionService duty = new DutySessionService(sessions, presenceRows, carrierScope,
                mock(PresenceService.class), "Asia/Beirut", Duration.ofMinutes(2),
                Duration.ofHours(4), guard);
        attendance = new AttendanceService(duty, carrierScope, mock(ShiftTemplateRepository.class),
                assignments, entries, guard, 400);
    }

    @AfterEach
    void tearDown() {
        SecurityContextHolder.clearContext();
    }

    private static boolean overlaps(CarrierMembershipPeriod period, Instant from, Instant to) {
        return period.getJoinedAt().isBefore(to)
                && (period.getLeftAt() == null || period.getLeftAt().isAfter(from));
    }

    private void worked(int day, String from, String to) {
        DutySession session = DutySession.open(RIDER, at(day, from));
        session.close(at(day, to), DutySession.EndReason.RIDER);
        sessionRows.add(session);
    }

    /** The rider's presence row, linked to {@code fleet}. */
    private void linkedTo(UUID fleet) {
        RiderPresence row = RiderPresence.firstSeen(RIDER, at(1, "08:00"));
        row.attachCarrier(fleet, at(1, "08:00"));
        when(presenceRows.findById(RIDER)).thenReturn(Optional.of(row));
    }

    private static void signedInAs(String subject, String token, String role) {
        Jwt jwt = Jwt.withTokenValue(token).header("alg", "none").subject(subject).build();
        SecurityContextHolder.getContext().setAuthentication(
                new JwtAuthenticationToken(jwt, List.of(new SimpleGrantedAuthority("ROLE_" + role))));
    }

    /** The row a late departure event has not ended yet. */
    private void staleScheduleRowOn(UUID fleet) {
        RiderShiftAssignment stale = RiderShiftAssignment.start(RIDER, fleet, UUID.randomUUID(),
                MONTH.atDay(1), OLD_DISPATCHER, at(1, "08:00"));
        when(assignments.findCurrentAndUpcoming(eq(fleet), any())).thenReturn(List.of(stale));
    }

    private static long workedSeconds(FleetAttendance fleet) {
        return fleet.riders().stream().mapToLong(rider -> rider.totals().workedSeconds()).sum();
    }

    private static AttendanceDay dayOf(RiderAttendance month, int day) {
        return month.days().stream()
                .filter(d -> d.date().equals(MONTH.atDay(day)))
                .findFirst()
                .orElseThrow();
    }

    @Test
    @DisplayName("the company left behind is refused every read and write about the rider, as for a stranger")
    void the_company_left_behind_is_refused_everything_about_the_rider() {
        linkedTo(OLD_FLEET);
        signedInAs(OLD_DISPATCHER, OLD_TOKEN, "CARRIER");
        staleScheduleRowOn(OLD_FLEET);
        String day = MONTH.atDay(5).toString();
        String stranger = catchThrowable(() ->
                attendance.riderAttendance("nobody", OLD_DISPATCHER, false, PERIOD)).getMessage();

        List<ThrowingCallable> everything = List.of(
                () -> attendance.riderAttendance(RIDER, OLD_DISPATCHER, false, PERIOD),
                () -> attendance.riderSessions(RIDER, OLD_DISPATCHER, false, PERIOD),
                () -> attendance.assign(RIDER, OLD_DISPATCHER, null, null),
                () -> attendance.recordEntry(RIDER, OLD_DISPATCHER, day, "SICK", null, null, null),
                () -> attendance.withdrawEntry(RIDER, OLD_DISPATCHER, day));
        for (ThrowingCallable call : everything) {
            assertThatThrownBy(call)
                    .isInstanceOf(PresenceService.PresenceNotFoundException.class)
                    .hasMessage(stranger);
        }
        verify(assignments, never()).save(any());
        verify(assignments, never()).delete(any());
        verify(entries, never()).save(any());
        // Its schedule listing leaves the rider out, though their row outlived them.
        assertThat(attendance.fleetAssignments(OLD_DISPATCHER, false, null)).isEmpty();
    }

    @Test
    @DisplayName("the company left behind keeps the rider's hours up to the departure in its pay run, and nothing after")
    void the_company_left_behind_keeps_the_hours_up_to_the_departure() {
        signedInAs(OLD_DISPATCHER, OLD_TOKEN, "CARRIER");

        FleetAttendance fleet = attendance.fleetAttendance(OLD_DISPATCHER, false, null, PERIOD);

        // Not the rider who left before the month began, whatever the record around it holds.
        assertThat(fleet.riders()).extracting(RiderTotals::riderId).containsExactly(RIDER);
        // Four hours on the 5th, and 09:00-13:00 on the 18th: the afternoon was the new company's.
        assertThat(workedSeconds(fleet)).isEqualTo(8 * 3600);
    }

    @Test
    @DisplayName("the company a rider joined never sees a session from before it hired them")
    void the_new_company_sees_nothing_from_before_the_hire() {
        linkedTo(NEW_FLEET);
        signedInAs(NEW_DISPATCHER, NEW_TOKEN, "CARRIER");

        List<SessionView> sessions =
                attendance.riderSessions(RIDER, NEW_DISPATCHER, false, PERIOD).sessions();
        assertThat(sessions).allSatisfy(s -> assertThat(s.startedAt()).isAfterOrEqualTo(MOVED));
        assertThat(sessions).extracting(SessionView::countedSeconds)
                .containsExactly(4 * 3600L, 2 * 3600L);

        RiderAttendance month = attendance.riderAttendance(RIDER, NEW_DISPATCHER, false, PERIOD);
        assertThat(dayOf(month, 5).sessions()).isEmpty();
        assertThat(dayOf(month, 5).workedSeconds()).isZero();
        assertThat(dayOf(month, 18).clockIn()).isEqualTo(MOVED);
        assertThat(month.totals().workedSeconds()).isEqualTo(6 * 3600);

        // The pay-run read says exactly what the rider's own month says.
        assertThat(attendance.fleetAttendance(NEW_DISPATCHER, false, null, PERIOD).riders())
                .singleElement()
                .satisfies(rider -> assertThat(rider.totals()).isEqualTo(month.totals()));
    }

    @Test
    @DisplayName("Backoffice sees each company's own part of a rider who moved, and the rider's whole record")
    void backoffice_reads_each_company_clipped_the_same_way() {
        linkedTo(NEW_FLEET);
        signedInAs(OPERATOR, "operator-token", "BACKOFFICE");

        long left = workedSeconds(attendance.fleetAttendance(OPERATOR, true, OLD_FLEET, PERIOD));
        long joined = workedSeconds(attendance.fleetAttendance(OPERATOR, true, NEW_FLEET, PERIOD));
        assertThat(left).isEqualTo(8 * 3600);
        assertThat(joined).isEqualTo(6 * 3600);
        // Between the two companies, every hour exactly once.
        assertThat(left + joined).isEqualTo(14 * 3600);

        // One rider's month is their current company's view of it; their sessions are their own.
        assertThat(attendance.riderAttendance(RIDER, OPERATOR, true, PERIOD).totals().workedSeconds())
                .isEqualTo(6 * 3600);
        assertThat(attendance.riderSessions(RIDER, OPERATOR, true, PERIOD).sessions()).hasSize(3);

        // Who is on a shift now goes by the record: nobody, for the company the rider left.
        staleScheduleRowOn(OLD_FLEET);
        assertThat(attendance.fleetAssignments(OPERATOR, true, OLD_FLEET)).isEmpty();
    }
}
