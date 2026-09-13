package com.delivery.tracking.service;

import java.time.DayOfWeek;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.Collection;
import java.util.EnumSet;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Optional;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.InOrder;

import com.delivery.tracking.domain.AttendanceEntry;
import com.delivery.tracking.domain.AttendanceEntryRepository;
import com.delivery.tracking.domain.DutySession;
import com.delivery.tracking.domain.DutySessionRepository;
import com.delivery.tracking.domain.RiderPresence;
import com.delivery.tracking.domain.RiderPresenceRepository;
import com.delivery.tracking.domain.RiderShiftAssignment;
import com.delivery.tracking.domain.RiderShiftAssignmentRepository;
import com.delivery.tracking.domain.ShiftTemplate;
import com.delivery.tracking.domain.ShiftTemplateRepository;
import com.delivery.tracking.service.AttendanceService.AttendanceDay;
import com.delivery.tracking.service.AttendanceService.ConflictException;
import com.delivery.tracking.service.AttendanceService.InvalidRequestException;
import com.delivery.tracking.service.AttendanceService.RiderAttendance;
import com.delivery.tracking.service.AttendanceService.Status;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.argThat;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.inOrder;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Attendance: duty evidence judged against the shifts a company scheduled.
 *
 * <p>Every figure here can change what somebody is paid, so the tests are organised around the ways
 * it could be wrong about a person: calling a freelancer absent, calling a Beirut rider late because
 * the platform was thinking in UTC, crediting a phone that never showed up, paying an office's typed
 * hours on top of the phone's, or letting a schedule written today reach back into days already
 * worked.
 *
 * <p>The zone is Asia/Beirut throughout, as configured. October 2026 is used because it contains
 * the night the clocks go back (24/25 October, when that Saturday is 25 hours long); March 2027
 * supplies the night they go forward. The dates' weekdays: 1 October 2026 is a Thursday, so the 5th
 * and 12th are Mondays and the 10th and 24th are Saturdays.
 */
class AttendanceServiceTest {

    private static final ZoneId BEIRUT = ZoneId.of("Asia/Beirut");
    private static final String RIDER = "rider-sub";
    private static final String DISPATCHER = "dispatcher-sub";
    private static final UUID CARRIER = UUID.fromString("5857ac51-0000-4000-8000-000000000001");
    private static final UUID OTHER_CARRIER = UUID.fromString("5857ac51-0000-4000-8000-000000000002");

    /** Monday 12 October 2026, 20:00 in Beirut — every weekday shift that day is over. */
    private static final Instant NOW = local("2026-10-12T20:00");
    private static final AttendancePeriod OCTOBER =
            new AttendancePeriod(LocalDate.of(2026, 10, 1), LocalDate.of(2026, 10, 31));
    private static final DayOfWeek[] WEEKDAYS = {DayOfWeek.MONDAY, DayOfWeek.TUESDAY,
            DayOfWeek.WEDNESDAY, DayOfWeek.THURSDAY, DayOfWeek.FRIDAY};

    private DutySessionRepository sessions;
    private RiderPresenceRepository presenceRows;
    private CarrierScopeResolver carrierScope;
    private ShiftTemplateRepository templates;
    private RiderShiftAssignmentRepository assignments;
    private AttendanceEntryRepository entries;
    private AttendanceService service;

    private final List<DutySession> sessionRows = new ArrayList<>();
    private final List<RiderShiftAssignment> assignmentRows = new ArrayList<>();
    private final Map<UUID, ShiftTemplate> shiftRows = new HashMap<>();
    private final List<AttendanceEntry> entryRows = new ArrayList<>();

    private static Instant local(String wallClock) {
        return LocalDateTime.parse(wallClock).atZone(BEIRUT).toInstant();
    }

    @BeforeEach
    void setUp() {
        sessions = mock(DutySessionRepository.class);
        presenceRows = mock(RiderPresenceRepository.class);
        carrierScope = mock(CarrierScopeResolver.class);
        templates = mock(ShiftTemplateRepository.class);
        assignments = mock(RiderShiftAssignmentRepository.class);
        entries = mock(AttendanceEntryRepository.class);

        when(sessions.findOverlapping(eq(RIDER), any(), any())).thenAnswer(call -> {
            Instant from = call.getArgument(1);
            Instant until = call.getArgument(2);
            return sessionRows.stream()
                    .filter(s -> s.getStartedAt().isBefore(until)
                            && (s.getEndedAt() == null || s.getEndedAt().isAfter(from)))
                    .sorted((a, b) -> a.getStartedAt().compareTo(b.getStartedAt()))
                    .toList();
        });
        riderSeenAt(NOW.minusSeconds(30), CARRIER);

        when(carrierScope.requireScopeFor(DISPATCHER)).thenReturn(CARRIER);
        when(carrierScope.scopeFor(DISPATCHER)).thenReturn(Optional.of(CARRIER));

        when(assignments.findTouching(eq(RIDER), eq(CARRIER), any(), any())).thenAnswer(call -> {
            LocalDate from = call.getArgument(2);
            LocalDate to = call.getArgument(3);
            return assignmentRows.stream()
                    .filter(a -> !a.getEffectiveFrom().isAfter(to)
                            && (a.getEffectiveTo() == null || !a.getEffectiveTo().isBefore(from)))
                    .toList();
        });
        when(assignments.findFrom(eq(RIDER), eq(CARRIER), any())).thenAnswer(call -> {
            LocalDate day = call.getArgument(2);
            return assignmentRows.stream()
                    .filter(a -> a.getEffectiveTo() == null || !a.getEffectiveTo().isBefore(day))
                    .toList();
        });
        when(templates.findByIdIn(any())).thenAnswer(call -> {
            Collection<UUID> ids = call.getArgument(0);
            return ids.stream().map(shiftRows::get).filter(Objects::nonNull).toList();
        });
        when(templates.findByIdAndCarrierId(any(), any())).thenAnswer(call -> Optional
                .ofNullable(shiftRows.get(call.<UUID>getArgument(0)))
                .filter(t -> t.getCarrierId().equals(call.getArgument(1))));
        when(entries.findLive(eq(RIDER), eq(CARRIER), any(), any())).thenAnswer(call -> {
            LocalDate from = call.getArgument(2);
            LocalDate to = call.getArgument(3);
            return entryRows.stream()
                    .filter(e -> e.getRevokedAt() == null
                            && !e.getWorkDate().isBefore(from) && !e.getWorkDate().isAfter(to))
                    .toList();
        });
        when(entries.findByRiderIdAndCarrierIdAndWorkDateAndRevokedAtIsNull(anyString(), any(),
                any())).thenReturn(Optional.empty());

        PresenceService presence = mock(PresenceService.class);
        DutySessionService duty = new DutySessionService(sessions, presenceRows, carrierScope,
                presence, "Asia/Beirut", Duration.ofMinutes(2), Duration.ofHours(4));
        service = new AttendanceService(duty, carrierScope, presenceRows, templates, assignments,
                entries, 400);
    }

    // ------------------------------------------------------------------------------- helpers

    /** The rider's presence row: which fleet they ride for, and when they were last sighted. */
    private RiderPresence riderRow;

    private void riderSeenAt(Instant lastSeen, UUID carrier) {
        RiderPresence row = RiderPresence.firstSeen(RIDER, NOW.minus(Duration.ofDays(60)));
        row.attachCarrier(carrier, NOW.minus(Duration.ofDays(60)));
        if (lastSeen != null) {
            row.sighted(33.89, 35.50, 5.0f, lastSeen);
        }
        riderRow = row;
        when(presenceRows.findById(RIDER)).thenReturn(Optional.of(row));
        when(presenceRows.existsById(RIDER)).thenReturn(true);
    }

    private ShiftTemplate shift(String name, String start, String end, DayOfWeek... days) {
        ShiftTemplate t = ShiftTemplate.create(CARRIER, name, LocalTime.parse(start),
                LocalTime.parse(end), EnumSet.copyOf(List.of(days)), 10, DISPATCHER, NOW);
        shiftRows.put(t.getId(), t);
        return t;
    }

    private RiderShiftAssignment onShift(ShiftTemplate shift, LocalDate from, LocalDate to) {
        RiderShiftAssignment a = RiderShiftAssignment.start(RIDER, CARRIER, shift.getId(), from,
                DISPATCHER, NOW);
        if (to != null) {
            a.endOn(to);
        }
        assignmentRows.add(a);
        return a;
    }

    /** The design's shift: Beirut Central Day, 08:00-18:00, weekdays, from 1 October. */
    private ShiftTemplate onDayShiftAllMonth() {
        ShiftTemplate day = shift("Beirut Central Day", "08:00", "18:00", WEEKDAYS);
        onShift(day, LocalDate.of(2026, 10, 1), null);
        return day;
    }

    private ShiftTemplate onNightShiftAllMonth() {
        ShiftTemplate night = shift("Night", "22:00", "06:00", DayOfWeek.values());
        onShift(night, LocalDate.of(2026, 10, 1), null);
        return night;
    }

    private DutySession worked(String fromLocal, String toLocal) {
        return session(local(fromLocal), local(toLocal), DutySession.EndReason.RIDER);
    }

    private DutySession session(Instant from, Instant to, DutySession.EndReason reason) {
        DutySession s = DutySession.open(RIDER, from);
        s.close(to, reason);
        sessionRows.add(s);
        return s;
    }

    private AttendanceEntry entry(String date, AttendanceEntry.Kind kind, String in, String out) {
        AttendanceEntry e = AttendanceEntry.record(RIDER, CARRIER, LocalDate.parse(date), kind,
                in == null ? null : LocalTime.parse(in), out == null ? null : LocalTime.parse(out),
                null, DISPATCHER, NOW);
        entryRows.add(e);
        return e;
    }

    private RiderAttendance october() {
        return service.compute(RIDER, CARRIER, OCTOBER, NOW);
    }

    private static AttendanceDay day(RiderAttendance month, String date) {
        return month.days().stream()
                .filter(d -> d.date().equals(LocalDate.parse(date)))
                .findFirst()
                .orElseThrow();
    }

    // ------------------------------------------------------------------------------ freelancers

    @Nested
    @DisplayName("a rider with no schedule")
    class Freelancers {

        /** The owner's rule: a freelancer chooses when to work, so nothing can make them late. */
        @Test
        void is_never_late_or_absent_whenever_they_work() {
            worked("2026-10-05T11:40", "2026-10-05T15:40");

            RiderAttendance month = october();

            assertThat(month.hasSchedule()).isFalse();
            assertThat(day(month, "2026-10-05").status()).isEqualTo(Status.WORKED);
            assertThat(day(month, "2026-10-05").lateBySeconds()).isNull();
            assertThat(day(month, "2026-10-06").status()).isEqualTo(Status.NO_DUTY);
            assertThat(month.days()).extracting(AttendanceDay::status)
                    .doesNotContain(Status.LATE, Status.ABSENT, Status.PENDING);
            assertThat(month.totals().absences()).isZero();
            assertThat(month.totals().lates()).isZero();
            assertThat(month.totals().overtimeSeconds()).isZero();
            assertThat(month.totals().daysWorked()).isEqualTo(1);
            assertThat(month.totals().workedSeconds()).isEqualTo(4 * 3600L);
        }

        /** Backoffice reading one of the platform's own riders: no fleet, so no schedule to read. */
        @Test
        void a_platform_rider_has_no_schedule_to_be_judged_against() {
            onDayShiftAllMonth();

            RiderAttendance month = service.compute(RIDER, null, OCTOBER, NOW);

            assertThat(month.hasSchedule()).isFalse();
            assertThat(day(month, "2026-10-06").status()).isEqualTo(Status.NO_DUTY);
            verify(assignments, never()).findTouching(anyString(), any(), any(), any());
        }
    }

    // ---------------------------------------------------------------------------- scheduled days

    @Nested
    @DisplayName("a scheduled day")
    class ScheduledDays {

        @Test
        void arriving_within_the_grace_is_on_time() {
            onDayShiftAllMonth();
            worked("2026-10-05T08:08", "2026-10-05T18:00");

            AttendanceDay monday = day(october(), "2026-10-05");

            assertThat(monday.status()).isEqualTo(Status.PRESENT);
            assertThat(monday.lateBySeconds()).isEqualTo(8 * 60L);
        }

        @Test
        void arriving_after_the_grace_is_late() {
            onDayShiftAllMonth();
            worked("2026-10-05T08:14", "2026-10-05T18:00");

            RiderAttendance month = october();

            assertThat(day(month, "2026-10-05").status()).isEqualTo(Status.LATE);
            assertThat(day(month, "2026-10-05").lateBySeconds()).isEqualTo(14 * 60L);
            assertThat(month.totals().lates()).isEqualTo(1);
        }

        @Test
        void with_no_duty_at_all_is_absent_once_the_shift_is_over() {
            onDayShiftAllMonth();

            AttendanceDay tuesday = day(october(), "2026-10-06");

            assertThat(tuesday.status()).isEqualTo(Status.ABSENT);
            assertThat(tuesday.scheduled().name()).isEqualTo("Beirut Central Day");
            assertThat(tuesday.clockIn()).isNull();
        }

        /** A rider is not absent at 08:01. Only a finished shift can have been missed. */
        @Test
        void today_before_the_shift_ends_is_pending_not_absent() {
            onDayShiftAllMonth();

            RiderAttendance month = service.compute(RIDER, CARRIER, OCTOBER,
                    local("2026-10-12T09:30"));

            assertThat(day(month, "2026-10-12").status()).isEqualTo(Status.PENDING);
            // 1, 2, 5, 6, 7, 8 and 9 October — and not the 12th.
            assertThat(month.totals().absences()).isEqualTo(7);
        }

        @Test
        void days_after_today_are_upcoming_and_never_absences() {
            onDayShiftAllMonth();

            RiderAttendance month = october();

            assertThat(day(month, "2026-10-13").status()).isEqualTo(Status.UPCOMING);
            assertThat(day(month, "2026-10-13").scheduled()).isNotNull();
            // October 2026 has 22 weekdays; eight of them are past with nobody there.
            assertThat(month.totals().scheduledDays()).isEqualTo(22);
            assertThat(month.totals().scheduledSeconds()).isEqualTo(22 * 36_000L);
            assertThat(month.totals().absences()).isEqualTo(8);
        }

        @Test
        void overtime_is_the_credited_time_beyond_the_scheduled_length() {
            onDayShiftAllMonth();
            worked("2026-10-05T07:50", "2026-10-05T18:15");

            AttendanceDay monday = day(october(), "2026-10-05");

            assertThat(monday.status()).isEqualTo(Status.PRESENT);
            assertThat(monday.lateBySeconds()).isZero();
            assertThat(monday.overtimeSeconds()).isEqualTo(25 * 60L);
        }

        @Test
        void a_day_off_is_a_day_off_and_working_it_is_all_overtime() {
            onDayShiftAllMonth();
            worked("2026-10-10T10:00", "2026-10-10T13:00");

            RiderAttendance month = october();

            assertThat(day(month, "2026-10-10").status()).isEqualTo(Status.EXTRA);
            assertThat(day(month, "2026-10-10").overtimeSeconds()).isEqualTo(3 * 3600L);
            assertThat(day(month, "2026-10-11").status()).isEqualTo(Status.DAY_OFF);
            assertThat(day(month, "2026-10-11").scheduled()).isNull();
        }

        /** A shift with no sighting behind it is worth nothing, and proves nobody was there. */
        @Test
        void a_session_closed_with_no_sighting_proves_nothing() {
            onDayShiftAllMonth();
            session(local("2026-10-06T08:00"), local("2026-10-06T08:00"),
                    DutySession.EndReason.EXPIRED);

            AttendanceDay tuesday = day(october(), "2026-10-06");

            assertThat(tuesday.status()).isEqualTo(Status.ABSENT);
            assertThat(tuesday.workedSeconds()).isZero();
            // Still listed, so the office can see the rider tapped on and vanished.
            assertThat(tuesday.sessions()).hasSize(1);
        }

        /** Auto-closed at the last sighting: credited to that point, and marked as such. */
        @Test
        void an_expired_session_counts_only_to_the_last_sighting() {
            onDayShiftAllMonth();
            session(local("2026-10-06T08:00"), local("2026-10-06T11:00"),
                    DutySession.EndReason.EXPIRED);

            AttendanceDay tuesday = day(october(), "2026-10-06");

            assertThat(tuesday.status()).isEqualTo(Status.PRESENT);
            assertThat(tuesday.workedSeconds()).isEqualTo(3 * 3600L);
            assertThat(tuesday.clockOut()).isEqualTo(local("2026-10-06T11:00"));
            assertThat(tuesday.clockOutReason()).isEqualTo(DutySession.EndReason.EXPIRED);
        }

        @Test
        void a_running_session_is_on_shift_now_with_no_clock_out() {
            onDayShiftAllMonth();
            sessionRows.add(DutySession.open(RIDER, local("2026-10-12T08:00")));

            AttendanceDay today = day(october(), "2026-10-12");

            assertThat(today.status()).isEqualTo(Status.PRESENT);
            assertThat(today.onShiftNow()).isTrue();
            assertThat(today.clockOut()).isNull();
            assertThat(today.workedSeconds()).isEqualTo(12 * 3600L);
        }

        /** A schedule is a history: each day is judged against the shift that applied on it. */
        @Test
        void a_mid_month_move_judges_each_day_against_the_shift_that_applied_then() {
            ShiftTemplate early = shift("Day", "08:00", "18:00", WEEKDAYS);
            ShiftTemplate late = shift("Late", "12:00", "20:00", WEEKDAYS);
            onShift(early, LocalDate.of(2026, 10, 1), LocalDate.of(2026, 10, 7));
            onShift(late, LocalDate.of(2026, 10, 8), null);
            worked("2026-10-07T12:00", "2026-10-07T20:00");
            worked("2026-10-08T12:00", "2026-10-08T20:00");

            RiderAttendance month = october();

            assertThat(day(month, "2026-10-07").scheduled().name()).isEqualTo("Day");
            assertThat(day(month, "2026-10-07").status()).isEqualTo(Status.LATE);
            assertThat(day(month, "2026-10-08").scheduled().name()).isEqualTo("Late");
            assertThat(day(month, "2026-10-08").status()).isEqualTo(Status.PRESENT);
        }

        /** Two hours at dawn that end before an 08:00 start are not an arrival: the shift was missed. */
        @Test
        void a_stint_that_ends_before_the_shift_starts_is_not_an_arrival() {
            onDayShiftAllMonth();
            worked("2026-10-05T05:00", "2026-10-05T07:00");

            RiderAttendance month = october();

            AttendanceDay monday = day(month, "2026-10-05");
            assertThat(monday.status()).isEqualTo(Status.ABSENT);
            assertThat(monday.lateBySeconds()).isNull();
            // Still evidence, still printed, and every second of it beyond the schedule.
            assertThat(monday.workedSeconds()).isEqualTo(2 * 3600L);
            assertThat(monday.overtimeSeconds()).isEqualTo(2 * 3600L);
            assertThat(monday.clockInLocal()).isEqualTo("2026-10-05T05:00");
            // 1, 2, 5, 6, 7, 8, 9 and 12 October.
            assertThat(month.totals().absences()).isEqualTo(8);
        }

        /** The same dawn stint, read before the shift is over, is not a verdict of any kind yet. */
        @Test
        void a_stint_before_todays_shift_leaves_the_day_pending() {
            onDayShiftAllMonth();
            worked("2026-10-12T05:00", "2026-10-12T07:00");

            AttendanceDay today = day(service.compute(RIDER, CARRIER, OCTOBER,
                    local("2026-10-12T07:30")), "2026-10-12");

            assertThat(today.status()).isEqualTo(Status.PENDING);
            assertThat(today.lateBySeconds()).isNull();
        }

        /** A day's work before a 23:00 night shift says nothing about the night shift. */
        @Test
        void daytime_duty_does_not_make_a_night_shift_present() {
            ShiftTemplate night = shift("Late night", "23:00", "07:00", DayOfWeek.values());
            onShift(night, LocalDate.of(2026, 10, 1), null);
            worked("2026-10-05T10:00", "2026-10-05T14:00");

            AttendanceDay thatAfternoon = day(service.compute(RIDER, CARRIER, OCTOBER,
                    local("2026-10-05T15:00")), "2026-10-05");
            AttendanceDay aWeekLater = day(october(), "2026-10-05");

            assertThat(thatAfternoon.status()).isEqualTo(Status.PENDING);
            assertThat(aWeekLater.status()).isEqualTo(Status.ABSENT);
            assertThat(aWeekLater.lateBySeconds()).isNull();
            assertThat(aWeekLater.overtimeSeconds()).isEqualTo(4 * 3600L);
        }

        /** Going on duty at 19:00 after an 08:00-18:00 shift is a missed shift, not 660 min late. */
        @Test
        void duty_after_the_shift_ended_is_an_absence_not_a_late() {
            onDayShiftAllMonth();
            worked("2026-10-05T19:00", "2026-10-05T21:00");

            RiderAttendance month = october();

            AttendanceDay monday = day(month, "2026-10-05");
            assertThat(monday.status()).isEqualTo(Status.ABSENT);
            assertThat(monday.lateBySeconds()).isNull();
            assertThat(monday.overtimeSeconds()).isEqualTo(2 * 3600L);
            assertThat(month.totals().lates()).isZero();
        }

        /** Judged to the minute the log prints: 08:10:40 against ten minutes' grace is 08:10. */
        @Test
        void lateness_is_judged_to_the_minute_the_log_prints() {
            onDayShiftAllMonth();
            worked("2026-10-05T08:10:40", "2026-10-05T18:00");
            worked("2026-10-06T08:11:05", "2026-10-06T18:00");

            RiderAttendance month = october();

            assertThat(day(month, "2026-10-05").clockInLocal()).isEqualTo("2026-10-05T08:10");
            assertThat(day(month, "2026-10-05").status()).isEqualTo(Status.PRESENT);
            assertThat(day(month, "2026-10-05").lateBySeconds()).isEqualTo(10 * 60L);
            assertThat(day(month, "2026-10-06").status()).isEqualTo(Status.LATE);
            assertThat(day(month, "2026-10-06").lateBySeconds()).isEqualTo(11 * 60L);
        }
    }

    // ------------------------------------------------------------------------------- time zones

    @Nested
    @DisplayName("time in Beirut")
    class Zones {

        /** 08:05 in Beirut in October is 05:05Z. Thinking in UTC would call it three hours early. */
        @Test
        void a_beirut_morning_is_judged_in_beirut_not_in_utc() {
            onDayShiftAllMonth();
            session(Instant.parse("2026-10-05T05:05:00Z"), Instant.parse("2026-10-05T15:00:00Z"),
                    DutySession.EndReason.RIDER);
            // 08:05Z is 11:05 in Beirut: on time by a UTC clock, three hours late by the rider's.
            session(Instant.parse("2026-10-06T08:05:00Z"), Instant.parse("2026-10-06T15:00:00Z"),
                    DutySession.EndReason.RIDER);

            RiderAttendance month = october();

            assertThat(month.zone()).isEqualTo("Asia/Beirut");
            assertThat(day(month, "2026-10-05").status()).isEqualTo(Status.PRESENT);
            assertThat(day(month, "2026-10-05").lateBySeconds()).isEqualTo(300L);
            assertThat(day(month, "2026-10-06").status()).isEqualTo(Status.LATE);
            // What the console prints is Beirut's clock, whatever zone the browser is in.
            assertThat(day(month, "2026-10-05").clockInLocal()).isEqualTo("2026-10-05T08:05");
            assertThat(day(month, "2026-10-05").clockOutLocal()).isEqualTo("2026-10-05T18:00");
            assertThat(day(month, "2026-10-05").sessions().get(0).startedAtLocal())
                    .isEqualTo("2026-10-05T08:05");
        }

        /**
         * The same wall-clock shift through both of Beirut's offsets: 08:05 is five minutes late in
         * July (UTC+3, 05:05Z) and in January (UTC+2, 06:05Z) alike — never a fixed offset.
         */
        @Test
        void the_same_shift_is_judged_by_each_seasons_own_offset() {
            ShiftTemplate day = shift("Day", "08:00", "18:00", WEEKDAYS);
            onShift(day, LocalDate.of(2026, 7, 1), null);
            session(Instant.parse("2026-07-15T05:05:00Z"), Instant.parse("2026-07-15T15:00:00Z"),
                    DutySession.EndReason.RIDER);
            session(Instant.parse("2027-01-15T06:05:00Z"), Instant.parse("2027-01-15T16:00:00Z"),
                    DutySession.EndReason.RIDER);
            Instant now = Instant.parse("2027-01-20T12:00:00Z");

            AttendanceDay july = day(service.compute(RIDER, CARRIER,
                    new AttendancePeriod(LocalDate.of(2026, 7, 1), LocalDate.of(2026, 7, 31)), now),
                    "2026-07-15");
            AttendanceDay january = day(service.compute(RIDER, CARRIER,
                    new AttendancePeriod(LocalDate.of(2027, 1, 1), LocalDate.of(2027, 1, 31)), now),
                    "2027-01-15");

            assertThat(july.lateBySeconds()).isEqualTo(300L);
            assertThat(january.lateBySeconds()).isEqualTo(300L);
            assertThat(july.scheduled().startsAt()).isEqualTo(Instant.parse("2026-07-15T05:00:00Z"));
            assertThat(january.scheduled().startsAt())
                    .isEqualTo(Instant.parse("2027-01-15T06:00:00Z"));
        }

        /** 22:30Z on the 5th is 01:30 on the 6th in Beirut, and that is the rider's day. */
        @Test
        void a_session_after_beirut_midnight_belongs_to_the_next_beirut_day() {
            session(Instant.parse("2026-10-05T22:30:00Z"), Instant.parse("2026-10-05T23:30:00Z"),
                    DutySession.EndReason.RIDER);

            RiderAttendance month = october();

            assertThat(day(month, "2026-10-05").status()).isEqualTo(Status.NO_DUTY);
            assertThat(day(month, "2026-10-06").status()).isEqualTo(Status.WORKED);
        }

        /**
         * One session, one day: attendance counts a session whole on the day it belongs to, so a
         * period's total can never count the same hour twice.
         */
        @Test
        void a_session_across_midnight_is_counted_whole_on_the_day_it_belongs_to() {
            worked("2026-10-05T22:00", "2026-10-06T02:00");

            RiderAttendance month = october();

            assertThat(day(month, "2026-10-05").workedSeconds()).isEqualTo(4 * 3600L);
            assertThat(day(month, "2026-10-06").workedSeconds()).isZero();
            assertThat(month.totals().workedSeconds()).isEqualTo(4 * 3600L);
        }

        @Test
        void a_night_shift_owns_the_small_hours_of_the_next_morning() {
            onNightShiftAllMonth();
            worked("2026-10-05T21:55", "2026-10-06T06:05");

            RiderAttendance month = october();

            AttendanceDay night = day(month, "2026-10-05");
            assertThat(night.status()).isEqualTo(Status.PRESENT);
            assertThat(night.workedSeconds()).isEqualTo(8 * 3600L + 10 * 60L);
            assertThat(night.overtimeSeconds()).isEqualTo(10 * 60L);
            // The next night is its own shift, and nobody came for it.
            assertThat(day(month, "2026-10-06").status()).isEqualTo(Status.ABSENT);
        }

        /** Arriving at 00:10 for a 22:00 shift is late for it, not absent from it plus "extra". */
        @Test
        void arriving_after_midnight_for_a_night_shift_is_late_for_that_shift() {
            onNightShiftAllMonth();
            worked("2026-10-06T00:10", "2026-10-06T06:00");

            RiderAttendance month = october();

            assertThat(day(month, "2026-10-05").status()).isEqualTo(Status.LATE);
            assertThat(day(month, "2026-10-05").lateBySeconds()).isEqualTo(2 * 3600L + 10 * 60L);
            assertThat(day(month, "2026-10-06").workedSeconds()).isZero();
        }

        /**
         * 24 October 2026: at midnight Beirut goes from UTC+3 back to UTC+2, so 22:00-06:00 that
         * night is nine real hours. Working all of it is not an hour of overtime.
         */
        @Test
        void the_night_the_clocks_go_back_the_shift_is_an_hour_longer() {
            onNightShiftAllMonth();
            worked("2026-10-24T22:00", "2026-10-25T06:00");

            RiderAttendance month = service.compute(RIDER, CARRIER, OCTOBER,
                    local("2026-10-26T12:00"));

            AttendanceDay night = day(month, "2026-10-24");
            assertThat(night.scheduled().scheduledSeconds()).isEqualTo(9 * 3600L);
            assertThat(night.workedSeconds()).isEqualTo(9 * 3600L);
            assertThat(night.overtimeSeconds()).isZero();
            assertThat(day(month, "2026-10-23").scheduled().scheduledSeconds())
                    .isEqualTo(8 * 3600L);
        }

        /** 27 March 2027: the clocks go forward at midnight, so the same shift is seven hours. */
        @Test
        void the_night_the_clocks_go_forward_the_shift_is_an_hour_shorter() {
            ShiftTemplate night = shift("Night", "22:00", "06:00", DayOfWeek.values());
            onShift(night, LocalDate.of(2027, 3, 1), null);
            worked("2027-03-27T22:00", "2027-03-28T06:00");

            RiderAttendance march = service.compute(RIDER, CARRIER,
                    new AttendancePeriod(LocalDate.of(2027, 3, 1), LocalDate.of(2027, 3, 31)),
                    Instant.parse("2027-04-10T09:00:00Z"));

            AttendanceDay saturday = day(march, "2027-03-27");
            assertThat(saturday.scheduled().scheduledSeconds()).isEqualTo(7 * 3600L);
            assertThat(saturday.workedSeconds()).isEqualTo(7 * 3600L);
            assertThat(saturday.status()).isEqualTo(Status.PRESENT);
            assertThat(saturday.overtimeSeconds()).isZero();
        }
    }

    // --------------------------------------------------------------------------- manual entries

    @Nested
    @DisplayName("the manual attendance log")
    class ManualEntries {

        @Test
        void sick_leave_replaces_an_absence_and_keeps_what_the_evidence_said() {
            onDayShiftAllMonth();
            entry("2026-10-06", AttendanceEntry.Kind.SICK, null, null);

            RiderAttendance month = october();

            assertThat(day(month, "2026-10-06").status()).isEqualTo(Status.SICK);
            assertThat(day(month, "2026-10-06").derivedStatus()).isEqualTo(Status.ABSENT);
            assertThat(day(month, "2026-10-06").entry().status())
                    .isEqualTo(AttendanceEntry.Kind.SICK);
            assertThat(month.totals().absences()).isEqualTo(7);
            assertThat(month.totals().sickDays()).isEqualTo(1);
        }

        /** Typed hours are a claim, reported as manual — never passed off as the phone's. */
        @Test
        void a_manual_present_with_times_is_manual_hours_never_evidence() {
            onDayShiftAllMonth();
            entry("2026-10-06", AttendanceEntry.Kind.PRESENT, "08:00", "18:00");

            RiderAttendance month = october();

            AttendanceDay tuesday = day(month, "2026-10-06");
            assertThat(tuesday.status()).isEqualTo(Status.PRESENT);
            assertThat(tuesday.worked()).isTrue();
            assertThat(tuesday.workedSeconds()).isZero();
            assertThat(tuesday.manualSeconds()).isEqualTo(10 * 3600L);
            assertThat(month.totals().workedSeconds()).isZero();
            assertThat(month.totals().manualSeconds()).isEqualTo(10 * 3600L);
        }

        /** Where the phone shows the day, the phone wins; adding the typed hours would pay twice. */
        @Test
        void typed_hours_do_not_add_to_a_day_the_evidence_already_shows() {
            onDayShiftAllMonth();
            worked("2026-10-05T08:00", "2026-10-05T12:00");
            entry("2026-10-05", AttendanceEntry.Kind.PRESENT, "08:00", "18:00");

            AttendanceDay monday = day(october(), "2026-10-05");

            assertThat(monday.manualSeconds()).isZero();
            assertThat(monday.workedSeconds()).isEqualTo(4 * 3600L);
        }

        @Test
        void an_excused_late_is_not_counted_as_a_late() {
            onDayShiftAllMonth();
            worked("2026-10-05T08:30", "2026-10-05T18:00");
            entry("2026-10-05", AttendanceEntry.Kind.LATE_EXCUSED, null, null);

            RiderAttendance month = october();

            assertThat(day(month, "2026-10-05").status()).isEqualTo(Status.LATE_EXCUSED);
            assertThat(month.totals().lates()).isZero();
            assertThat(month.totals().excusedLates()).isEqualTo(1);
        }

        /** "Present" says they came, not that coming late was fine — that is LATE_EXCUSED. */
        @Test
        void a_present_entry_does_not_excuse_lateness() {
            assertThat(AttendanceService.overridden(Status.LATE, AttendanceEntry.Kind.PRESENT))
                    .isEqualTo(Status.LATE);
            assertThat(AttendanceService.overridden(Status.DAY_OFF, AttendanceEntry.Kind.PRESENT))
                    .isEqualTo(Status.EXTRA);
            assertThat(AttendanceService.overridden(Status.NO_DUTY, AttendanceEntry.Kind.PRESENT))
                    .isEqualTo(Status.WORKED);
        }

        @Test
        void replacing_an_entry_revokes_the_old_one_before_writing_the_new() {
            LocalDate yesterday = LocalDate.now(BEIRUT).minusDays(1);
            AttendanceEntry previous = AttendanceEntry.record(RIDER, CARRIER, yesterday,
                    AttendanceEntry.Kind.SICK, null, null, "flu", "someone-else", NOW);
            when(entries.findByRiderIdAndCarrierIdAndWorkDateAndRevokedAtIsNull(RIDER, CARRIER,
                    yesterday)).thenReturn(Optional.of(previous));

            service.recordEntry(RIDER, DISPATCHER, yesterday.toString(), "LEAVE", null, null,
                    "annual leave");

            assertThat(previous.getRevokedAt()).isNotNull();
            InOrder order = inOrder(entries);
            order.verify(entries).save(previous);
            order.verify(entries).flush();
            order.verify(entries).save(argThat((AttendanceEntry e) ->
                    e != previous && e.getStatus() == AttendanceEntry.Kind.LEAVE
                            && e.getCarrierId().equals(CARRIER)));
        }

        @Test
        void a_note_longer_than_five_hundred_characters_is_refused() {
            String today = LocalDate.now(BEIRUT).toString();

            assertThatThrownBy(() -> service.recordEntry(RIDER, DISPATCHER, today, "SICK", null,
                    null, "x".repeat(501)))
                    .isInstanceOf(InvalidRequestException.class)
                    .hasMessageContaining("500");
            verify(entries, never()).save(any());
        }

        @Test
        void presence_cannot_be_recorded_for_a_day_that_has_not_happened() {
            String tomorrow = LocalDate.now(BEIRUT).plusDays(1).toString();

            assertThatThrownBy(() -> service.recordEntry(RIDER, DISPATCHER, tomorrow, "PRESENT",
                    null, null, null))
                    .isInstanceOf(InvalidRequestException.class);
            // Leave, though, is planned ahead.
            assertThat(service.recordEntry(RIDER, DISPATCHER, tomorrow, "LEAVE", null, null, null)
                    .status()).isEqualTo(AttendanceEntry.Kind.LEAVE);
        }

        @Test
        void clock_times_belong_only_on_a_present_day() {
            String today = LocalDate.now(BEIRUT).toString();

            assertThatThrownBy(() -> service.recordEntry(RIDER, DISPATCHER, today, "SICK",
                    "08:00", "12:00", null))
                    .isInstanceOf(InvalidRequestException.class);
        }

        @Test
        void a_carrier_cannot_write_for_another_fleets_rider() {
            riderSeenAt(NOW, OTHER_CARRIER);

            assertThatThrownBy(() -> service.recordEntry(RIDER, DISPATCHER,
                    LocalDate.now(BEIRUT).toString(), "SICK", null, null, null))
                    .isInstanceOf(PresenceService.PresenceNotFoundException.class);
            verify(entries, never()).save(any());
        }
    }

    // --------------------------------------------------------------------------- scheduling

    @Nested
    @DisplayName("scheduling")
    class Scheduling {

        private final LocalDate today = LocalDate.now(BEIRUT);

        /** A schedule set today must not reach back and mark days already worked as absences. */
        @Test
        void a_schedule_cannot_be_backdated() {
            ShiftTemplate day = shift("Day", "08:00", "18:00", WEEKDAYS);

            assertThatThrownBy(() -> service.assign(RIDER, DISPATCHER, day.getId(),
                    today.minusDays(1).toString()))
                    .isInstanceOf(InvalidRequestException.class);
            verify(assignments, never()).save(any());
        }

        @Test
        void moving_a_rider_closes_the_old_shift_the_day_before_and_flushes_first() {
            ShiftTemplate day = shift("Day", "08:00", "18:00", WEEKDAYS);
            ShiftTemplate late = shift("Late", "12:00", "20:00", WEEKDAYS);
            RiderShiftAssignment old = onShift(day, today.minusDays(20), null);
            LocalDate from = today.plusDays(3);

            service.assign(RIDER, DISPATCHER, late.getId(), from.toString());

            assertThat(old.getEffectiveTo()).isEqualTo(from.minusDays(1));
            InOrder order = inOrder(assignments);
            order.verify(assignments).save(old);
            order.verify(assignments).flush();
            order.verify(assignments).save(argThat((RiderShiftAssignment a) -> a != old
                    && a.getTemplateId().equals(late.getId())
                    && a.getEffectiveFrom().equals(from)
                    && a.getCarrierId().equals(CARRIER)));
        }

        @Test
        void a_schedule_that_had_not_started_yet_is_replaced_not_closed() {
            ShiftTemplate day = shift("Day", "08:00", "18:00", WEEKDAYS);
            ShiftTemplate late = shift("Late", "12:00", "20:00", WEEKDAYS);
            RiderShiftAssignment upcoming = onShift(day, today.plusDays(5), null);

            service.assign(RIDER, DISPATCHER, late.getId(), today.plusDays(2).toString());

            verify(assignments).delete(upcoming);
        }

        /** Taking a rider off their schedule makes them a freelancer from that day: nothing new. */
        @Test
        void no_shift_ends_the_schedule_without_starting_another() {
            ShiftTemplate day = shift("Day", "08:00", "18:00", WEEKDAYS);
            RiderShiftAssignment current = onShift(day, today.minusDays(3), null);

            service.assign(RIDER, DISPATCHER, null, today.plusDays(1).toString());

            assertThat(current.getEffectiveTo()).isEqualTo(today);
            verify(assignments).save(current);
            verify(assignments, never()).save(argThat((RiderShiftAssignment a) -> a != current));
        }

        @Test
        void putting_a_rider_on_the_shift_they_are_on_changes_nothing() {
            ShiftTemplate day = shift("Day", "08:00", "18:00", WEEKDAYS);
            onShift(day, today.minusDays(3), null);

            service.assign(RIDER, DISPATCHER, day.getId(), null);

            verify(assignments, never()).save(any());
            verify(assignments, never()).delete(any());
        }

        /** Scoped in the query: a competitor's shift id is simply not a shift. */
        @Test
        void another_companys_shift_cannot_be_assigned() {
            ShiftTemplate theirs = ShiftTemplate.create(OTHER_CARRIER, "Theirs",
                    LocalTime.of(8, 0), LocalTime.of(16, 0), EnumSet.of(DayOfWeek.MONDAY), 10,
                    "them", NOW);
            shiftRows.put(theirs.getId(), theirs);

            assertThatThrownBy(() -> service.assign(RIDER, DISPATCHER, theirs.getId(), null))
                    .isInstanceOf(AttendanceService.ShiftNotFoundException.class);
            verify(assignments, never()).save(any());
        }

        @Test
        void a_carrier_cannot_schedule_another_fleets_rider() {
            ShiftTemplate day = shift("Day", "08:00", "18:00", WEEKDAYS);
            riderSeenAt(NOW, OTHER_CARRIER);

            assertThatThrownBy(() -> service.assign(RIDER, DISPATCHER, day.getId(), null))
                    .isInstanceOf(PresenceService.PresenceNotFoundException.class);
            verify(assignments, never()).save(any());
        }

        @Test
        void a_retired_shift_cannot_be_assigned() {
            ShiftTemplate day = shift("Day", "08:00", "18:00", WEEKDAYS);
            day.archive(NOW);

            assertThatThrownBy(() -> service.assign(RIDER, DISPATCHER, day.getId(), null))
                    .isInstanceOf(ConflictException.class);
        }

        @Test
        void a_shift_with_riders_on_it_cannot_be_archived() {
            ShiftTemplate day = shift("Day", "08:00", "18:00", WEEKDAYS);
            when(assignments.countActiveOrUpcoming(eq(day.getId()), any())).thenReturn(2L);

            assertThatThrownBy(() -> service.archiveShift(DISPATCHER, day.getId()))
                    .isInstanceOfSatisfying(ConflictException.class,
                            e -> assertThat(e.riders()).isEqualTo(2L));
            assertThat(day.isArchived()).isFalse();
        }

        @Test
        void a_new_shift_belongs_to_the_callers_own_fleet() {
            service.createShift(DISPATCHER, " Night ", "22:00", "06:00",
                    List.of("monday", "TUESDAY"), null);

            ArgumentCaptor<ShiftTemplate> saved = ArgumentCaptor.forClass(ShiftTemplate.class);
            verify(templates).save(saved.capture());
            assertThat(saved.getValue().getCarrierId()).isEqualTo(CARRIER);
            assertThat(saved.getValue().getName()).isEqualTo("Night");
            assertThat(saved.getValue().isOvernight()).isTrue();
            assertThat(saved.getValue().getLateGraceMinutes()).isEqualTo(10);
            assertThat(saved.getValue().days())
                    .containsExactly(DayOfWeek.MONDAY, DayOfWeek.TUESDAY);
        }

        @Test
        void a_shift_that_runs_on_no_day_or_no_time_is_refused() {
            assertThatThrownBy(() -> service.createShift(DISPATCHER, "Day", "08:00", "18:00",
                    List.of(), null)).isInstanceOf(InvalidRequestException.class);
            assertThatThrownBy(() -> service.createShift(DISPATCHER, "Day", "08:00", "08:00",
                    List.of("MONDAY"), null)).isInstanceOf(InvalidRequestException.class);
            assertThatThrownBy(() -> service.createShift(DISPATCHER, "Day", "8 o'clock", "18:00",
                    List.of("MONDAY"), null)).isInstanceOf(InvalidRequestException.class);
            verify(templates, never()).save(any());
        }

        // ------------------------------------------ a change asked for today, once it is under way

        /** Monday 12 October 2026, when the Day shift runs 08:00-18:00. */
        private final LocalDate monday = LocalDate.of(2026, 10, 12);

        /** Keeps what the service saves and deletes, so a test can read the schedule it left. */
        private void keepWrites() {
            when(assignments.save(any(RiderShiftAssignment.class))).thenAnswer(call -> {
                RiderShiftAssignment row = call.getArgument(0);
                if (!assignmentRows.contains(row)) {
                    assignmentRows.add(row);
                }
                return row;
            });
            doAnswer(call -> assignmentRows.remove(call.<RiderShiftAssignment>getArgument(0)))
                    .when(assignments).delete(any(RiderShiftAssignment.class));
        }

        /** An 08:00-18:00 shift assigned at 19:00 must not turn the day just gone into an absence. */
        @Test
        void a_shift_assigned_after_its_window_began_today_starts_tomorrow() {
            ShiftTemplate day = shift("Day", "08:00", "18:00", WEEKDAYS);
            keepWrites();
            Instant sevenPm = local("2026-10-12T19:00");

            service.assign(RIDER, DISPATCHER, day.getId(), null, sevenPm);

            assertThat(assignmentRows).extracting(RiderShiftAssignment::getEffectiveFrom)
                    .containsExactly(monday.plusDays(1));
            RiderAttendance month = service.compute(RIDER, CARRIER, OCTOBER, sevenPm);
            assertThat(day(month, "2026-10-12").status()).isEqualTo(Status.NO_DUTY);
            assertThat(month.totals().absences()).isZero();
        }

        /** Once today's shift has begun, a move keeps today on it, and its late stays a late. */
        @Test
        void moving_a_rider_once_todays_shift_began_keeps_today_on_the_old_shift() {
            ShiftTemplate day = shift("Day", "08:00", "18:00", WEEKDAYS);
            ShiftTemplate late = shift("Late", "12:00", "20:00", WEEKDAYS);
            RiderShiftAssignment old = onShift(day, LocalDate.of(2026, 10, 1), null);
            worked("2026-10-12T08:30", "2026-10-12T09:30");
            keepWrites();
            Instant tenAm = local("2026-10-12T10:00");

            service.assign(RIDER, DISPATCHER, late.getId(), null, tenAm);

            assertThat(old.getEffectiveTo()).isEqualTo(monday);
            assertThat(assignmentRows).filteredOn(a -> a != old)
                    .extracting(RiderShiftAssignment::getEffectiveFrom)
                    .containsExactly(monday.plusDays(1));
            AttendanceDay judged = day(service.compute(RIDER, CARRIER, OCTOBER, tenAm), "2026-10-12");
            assertThat(judged.scheduled().name()).isEqualTo("Day");
            assertThat(judged.status()).isEqualTo(Status.LATE);
        }

        /** Taking a rider off their schedule at 19:00 keeps the absence the day already earned. */
        @Test
        void freeing_a_rider_once_todays_shift_began_keeps_todays_absence() {
            ShiftTemplate day = shift("Day", "08:00", "18:00", WEEKDAYS);
            RiderShiftAssignment current = onShift(day, LocalDate.of(2026, 10, 1), null);
            keepWrites();
            Instant sevenPm = local("2026-10-12T19:00");

            service.assign(RIDER, DISPATCHER, null, null, sevenPm);

            assertThat(current.getEffectiveTo()).isEqualTo(monday);
            assertThat(day(service.compute(RIDER, CARRIER, OCTOBER, sevenPm), "2026-10-12")
                    .status()).isEqualTo(Status.ABSENT);
        }

        /** A schedule that began today, with its shift under way, is ended — never erased. */
        @Test
        void a_schedule_that_began_today_is_ended_not_deleted_once_its_shift_began() {
            ShiftTemplate day = shift("Day", "08:00", "18:00", WEEKDAYS);
            ShiftTemplate late = shift("Late", "12:00", "20:00", WEEKDAYS);
            RiderShiftAssignment startedToday = onShift(day, monday, null);
            keepWrites();

            service.assign(RIDER, DISPATCHER, late.getId(), null, local("2026-10-12T09:00"));

            verify(assignments, never()).delete(any());
            assertThat(startedToday.getEffectiveTo()).isEqualTo(monday);
            assertThat(assignmentRows).extracting(RiderShiftAssignment::getEffectiveFrom)
                    .containsExactly(monday, monday.plusDays(1));
        }

        /** Before either shift has begun today, a change for today still applies to today. */
        @Test
        void before_todays_shifts_begin_a_change_for_today_applies_today() {
            ShiftTemplate day = shift("Day", "08:00", "18:00", WEEKDAYS);
            ShiftTemplate late = shift("Late", "12:00", "20:00", WEEKDAYS);
            RiderShiftAssignment old = onShift(day, LocalDate.of(2026, 10, 1), null);
            keepWrites();

            service.assign(RIDER, DISPATCHER, late.getId(), monday.toString(),
                    local("2026-10-12T07:00"));

            assertThat(old.getEffectiveTo()).isEqualTo(monday.minusDays(1));
            assertThat(assignmentRows).filteredOn(a -> a != old)
                    .extracting(RiderShiftAssignment::getEffectiveFrom)
                    .containsExactly(monday);
        }
    }

    // ------------------------------------------------------------------------ the whole fleet

    @Nested
    @DisplayName("a pay run's read")
    class Fleet {

        @Test
        void a_carrier_reads_only_its_own_fleet_whatever_it_names() {
            when(presenceRows.findByCarrierIdOrderByLastSeenAtDesc(CARRIER))
                    .thenReturn(List.of(riderRow));

            AttendanceService.FleetAttendance fleet = service.fleetAttendance(DISPATCHER, false,
                    OTHER_CARRIER, OCTOBER);

            assertThat(fleet.carrierId()).isEqualTo(CARRIER);
            assertThat(fleet.riders()).extracting(AttendanceService.RiderTotals::riderId)
                    .containsExactly(RIDER);
            verify(presenceRows, never()).findByCarrierIdOrderByLastSeenAtDesc(OTHER_CARRIER);
        }

        /** Figures are never final, so every read says when it was computed — one instant a fleet. */
        @Test
        void every_read_says_the_instant_its_figures_were_computed() {
            when(presenceRows.findByCarrierIdOrderByLastSeenAtDesc(CARRIER))
                    .thenReturn(List.of(riderRow));
            Instant before = Instant.now();

            AttendanceService.FleetAttendance fleet = service.fleetAttendance(DISPATCHER, false,
                    null, OCTOBER);

            assertThat(fleet.asOf()).isBetween(before, Instant.now());
            assertThat(october().asOf()).isEqualTo(NOW);
        }

        @Test
        void backoffice_must_name_the_fleet() {
            assertThatThrownBy(() -> service.fleetAttendance("op-1", true, null, OCTOBER))
                    .isInstanceOf(InvalidRequestException.class);
        }

        /** Sessions are deleted after the retention window; judging past it would invent absences. */
        @Test
        void a_period_older_than_the_duty_history_is_refused() {
            assertThatThrownBy(() -> service.compute(RIDER, CARRIER,
                    new AttendancePeriod(LocalDate.of(2025, 8, 1), LocalDate.of(2025, 8, 31)), NOW))
                    .isInstanceOf(InvalidRequestException.class);
        }
    }
}
