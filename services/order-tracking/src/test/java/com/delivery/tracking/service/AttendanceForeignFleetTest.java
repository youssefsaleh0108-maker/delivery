package com.delivery.tracking.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.assertj.core.api.Assertions.catchThrowable;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.time.DayOfWeek;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalTime;
import java.time.YearMonth;
import java.time.ZoneId;
import java.util.EnumSet;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;

import com.delivery.tracking.client.CarrierDirectoryClient;
import com.delivery.tracking.domain.AttendanceEntry;
import com.delivery.tracking.domain.AttendanceEntryRepository;
import com.delivery.tracking.domain.CarrierMembershipPeriod;
import com.delivery.tracking.domain.CarrierMembershipPeriodRepository;
import com.delivery.tracking.domain.DutySession;
import com.delivery.tracking.domain.DutySessionRepository;
import com.delivery.tracking.domain.RiderPresence;
import com.delivery.tracking.domain.RiderPresenceRepository;
import com.delivery.tracking.domain.RiderShiftAssignment;
import com.delivery.tracking.domain.RiderShiftAssignmentRepository;
import com.delivery.tracking.domain.ShiftTemplate;
import com.delivery.tracking.domain.ShiftTemplateRepository;

/**
 * Nothing of a rival company's riders or schedule reaches a carrier, however it asks.
 *
 * <p>{@code AttendanceControllerAccessTest} proves how a refusal is answered; these prove the
 * refusals happen, in the service every request goes through, with the real
 * {@link FleetMembershipGuard} deciding who is on whose fleet. The rival's rider rides for the rival
 * in every source — the linkage, Order Manager and the membership record — and the rival's shift and
 * schedule sit in the same tables as the caller's own, where a lookup that forgot its company would
 * find them. Each case first shows the caller's own rider or shift going through, so a refusal can
 * only be the company check, never a broken fixture.
 */
@DisplayName("a rival company's riders and schedule")
class AttendanceForeignFleetTest {

    private static final ZoneId BEIRUT = ZoneId.of("Asia/Beirut");
    private static final String DISPATCHER = "dispatcher-sub";
    private static final String TOKEN = "dispatcher-token";
    private static final String OURS = "rider-ours";
    private static final String THEIRS = "rider-theirs";
    private static final UUID CARRIER = UUID.fromString("5857ac51-0000-4000-8000-000000000001");
    private static final UUID RIVAL = UUID.fromString("5857ac51-0000-4000-8000-000000000002");

    /** Last month in Beirut: wholly past, and well inside the duty history. */
    private static final YearMonth MONTH = YearMonth.now(BEIRUT).minusMonths(1);
    private static final AttendancePeriod PERIOD =
            new AttendancePeriod(MONTH.atDay(1), MONTH.atEndOfMonth());

    private final Map<UUID, ShiftTemplate> shiftRows = new HashMap<>();

    private ShiftTemplateRepository templates;
    private AttendanceEntryRepository entries;
    private AttendanceService attendance;

    @BeforeEach
    void setUp() {
        DutySessionRepository sessions = mock(DutySessionRepository.class);
        RiderPresenceRepository presenceRows = mock(RiderPresenceRepository.class);
        CarrierMembershipPeriodRepository periods = mock(CarrierMembershipPeriodRepository.class);
        CarrierDirectoryClient directory = mock(CarrierDirectoryClient.class);
        CarrierScopeResolver carrierScope = mock(CarrierScopeResolver.class);
        RiderShiftAssignmentRepository assignments = mock(RiderShiftAssignmentRepository.class);
        templates = mock(ShiftTemplateRepository.class);
        entries = mock(AttendanceEntryRepository.class);

        // Each rider linked to their own company, on its record for months, with a shift last month.
        Instant longAgo = MONTH.atDay(1).atStartOfDay(BEIRUT).toInstant().minus(Duration.ofDays(90));
        for (Map.Entry<String, UUID> rider : Map.of(OURS, CARRIER, THEIRS, RIVAL).entrySet()) {
            RiderPresence row = RiderPresence.firstSeen(rider.getKey(), longAgo);
            row.attachCarrier(rider.getValue(), longAgo);
            when(presenceRows.findById(rider.getKey())).thenReturn(Optional.of(row));

            DutySession worked = DutySession.open(rider.getKey(),
                    MONTH.atDay(5).atTime(8, 0).atZone(BEIRUT).toInstant());
            worked.close(MONTH.atDay(5).atTime(16, 0).atZone(BEIRUT).toInstant(),
                    DutySession.EndReason.RIDER);
            when(sessions.findOverlapping(eq(rider.getKey()), any(), any()))
                    .thenReturn(List.of(worked));

            when(periods.overlappingForRider(eq(rider.getValue()), eq(rider.getKey()), any(), any()))
                    .thenReturn(List.of(CarrierMembershipPeriod.open(rider.getKey(), rider.getValue(),
                            longAgo)));
        }
        // Order Manager, asked with the dispatcher's own token.
        when(directory.ridersFor(TOKEN)).thenReturn(Set.of(OURS));
        when(carrierScope.requireScopeFor(DISPATCHER)).thenReturn(CARRIER);

        // Both companies' shifts in one table — findable by id alone, or by id within a company.
        ShiftTemplate ours = shift(CARRIER, "Ours");
        ShiftTemplate theirs = shift(RIVAL, "Theirs");
        when(templates.findById(any())).thenAnswer(call ->
                Optional.ofNullable(shiftRows.get(call.<UUID>getArgument(0))));
        when(templates.findByIdAndCarrierId(any(), any())).thenAnswer(call ->
                Optional.ofNullable(shiftRows.get(call.<UUID>getArgument(0)))
                        .filter(shift -> shift.getCarrierId().equals(call.getArgument(1))));
        when(templates.findByCarrierIdOrderByCreatedAt(any())).thenAnswer(call ->
                shiftRows.values().stream()
                        .filter(shift -> shift.getCarrierId().equals(call.getArgument(0)))
                        .toList());
        // ...and both companies' schedules.
        when(assignments.findCurrentAndUpcoming(eq(CARRIER), any())).thenReturn(List.of(
                RiderShiftAssignment.start(OURS, CARRIER, ours.getId(), MONTH.atDay(1), DISPATCHER,
                        longAgo)));
        when(assignments.findCurrentAndUpcoming(eq(RIVAL), any())).thenReturn(List.of(
                RiderShiftAssignment.start(THEIRS, RIVAL, theirs.getId(), MONTH.atDay(1), "them",
                        longAgo)));

        FleetMembershipGuard guard =
                new FleetMembershipGuard(directory, periods, Duration.ofSeconds(30));
        DutySessionService duty = new DutySessionService(sessions, presenceRows, carrierScope,
                mock(PresenceService.class), "Asia/Beirut", Duration.ofMinutes(2),
                Duration.ofHours(4), guard);
        attendance = new AttendanceService(duty, carrierScope, templates, assignments, entries,
                guard, 400);

        Jwt jwt = Jwt.withTokenValue(TOKEN).header("alg", "none").subject(DISPATCHER).build();
        SecurityContextHolder.getContext().setAuthentication(new JwtAuthenticationToken(jwt,
                List.of(new SimpleGrantedAuthority("ROLE_CARRIER"))));
    }

    @AfterEach
    void tearDown() {
        SecurityContextHolder.clearContext();
    }

    private ShiftTemplate shift(UUID fleet, String name) {
        ShiftTemplate shift = ShiftTemplate.create(fleet, name, LocalTime.of(8, 0),
                LocalTime.of(16, 0), EnumSet.of(DayOfWeek.MONDAY), 10, "someone",
                MONTH.atDay(1).atStartOfDay(BEIRUT).toInstant());
        shiftRows.put(shift.getId(), shift);
        return shift;
    }

    private ShiftTemplate shiftNamed(String name) {
        return shiftRows.values().stream().filter(s -> s.getName().equals(name)).findFirst()
                .orElseThrow();
    }

    @Test
    @DisplayName("a rival's rider's attendance month is the same not-found as a stranger's")
    void a_rivals_riders_month_is_not_found() {
        assertThat(attendance.riderAttendance(OURS, DISPATCHER, false, PERIOD).totals()
                .workedSeconds()).isEqualTo(8 * 3600);
        String stranger = catchThrowable(() ->
                attendance.riderAttendance("nobody", DISPATCHER, false, PERIOD)).getMessage();

        assertThatThrownBy(() -> attendance.riderAttendance(THEIRS, DISPATCHER, false, PERIOD))
                .isInstanceOf(PresenceService.PresenceNotFoundException.class)
                .hasMessage(stranger);
    }

    @Test
    @DisplayName("a rival's rider's sessions are the same not-found as a stranger's")
    void a_rivals_riders_sessions_are_not_found() {
        assertThat(attendance.riderSessions(OURS, DISPATCHER, false, PERIOD).sessions()).hasSize(1);
        String stranger = catchThrowable(() ->
                attendance.riderSessions("nobody", DISPATCHER, false, PERIOD)).getMessage();

        assertThatThrownBy(() -> attendance.riderSessions(THEIRS, DISPATCHER, false, PERIOD))
                .isInstanceOf(PresenceService.PresenceNotFoundException.class)
                .hasMessage(stranger);
    }

    /** The company's own entry, from when the rider rode for it: the rider rides for a rival now. */
    @Test
    @DisplayName("an entry for a rider who now rides for a rival cannot be withdrawn")
    void an_entry_for_a_rivals_rider_cannot_be_withdrawn() {
        LocalDate day = MONTH.atDay(5);
        AttendanceEntry entry = AttendanceEntry.record(THEIRS, CARRIER, day,
                AttendanceEntry.Kind.SICK, null, null, null, DISPATCHER,
                day.atStartOfDay(BEIRUT).toInstant());
        when(entries.findByRiderIdAndCarrierIdAndWorkDateAndRevokedAtIsNull(THEIRS, CARRIER, day))
                .thenReturn(Optional.of(entry));

        assertThatThrownBy(() -> attendance.withdrawEntry(THEIRS, DISPATCHER, day.toString()))
                .isInstanceOf(PresenceService.PresenceNotFoundException.class);
        assertThat(entry.getRevokedAt()).isNull();
        verify(entries, never()).save(any());
    }

    @Test
    @DisplayName("naming a rival company still lists only the caller's own shifts")
    void naming_a_rival_lists_only_the_callers_shifts() {
        assertThat(attendance.shifts(DISPATCHER, false, RIVAL))
                .extracting(AttendanceService.ShiftView::name)
                .containsExactly("Ours");
    }

    @Test
    @DisplayName("naming a rival company still lists only the caller's own schedule")
    void naming_a_rival_lists_only_the_callers_schedule() {
        assertThat(attendance.fleetAssignments(DISPATCHER, false, RIVAL))
                .extracting(AttendanceService.AssignmentView::riderId)
                .containsExactly(OURS);
    }

    @Test
    @DisplayName("a rival's shift cannot be retired: to the caller it is no shift at all")
    void a_rivals_shift_cannot_be_retired() {
        ShiftTemplate theirs = shiftNamed("Theirs");

        assertThatThrownBy(() -> attendance.archiveShift(DISPATCHER, theirs.getId()))
                .isInstanceOf(AttendanceService.ShiftNotFoundException.class);
        assertThat(theirs.isArchived()).isFalse();
        verify(templates, never()).save(any());

        // The caller's own goes through the same door.
        assertThat(attendance.archiveShift(DISPATCHER, shiftNamed("Ours").getId()).archived())
                .isTrue();
    }
}
