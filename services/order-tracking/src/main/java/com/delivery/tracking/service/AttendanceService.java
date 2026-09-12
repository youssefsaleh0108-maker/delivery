package com.delivery.tracking.service;

import java.math.BigDecimal;
import java.time.DayOfWeek;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalTime;
import java.time.ZoneId;
import java.time.format.DateTimeParseException;
import java.util.ArrayList;
import java.util.EnumSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;
import java.util.UUID;
import java.util.function.Function;
import java.util.stream.Collectors;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.tracking.domain.AttendanceEntry;
import com.delivery.tracking.domain.AttendanceEntryRepository;
import com.delivery.tracking.domain.DutySession;
import com.delivery.tracking.domain.RiderPresence;
import com.delivery.tracking.domain.RiderPresenceRepository;
import com.delivery.tracking.domain.RiderShiftAssignment;
import com.delivery.tracking.domain.RiderShiftAssignmentRepository;
import com.delivery.tracking.domain.ShiftTemplate;
import com.delivery.tracking.domain.ShiftTemplateRepository;
import com.delivery.tracking.service.DutySessionService.DutySessions;
import com.delivery.tracking.service.DutySessionService.ReadAccess;
import com.delivery.tracking.service.DutySessionService.SessionView;

/**
 * Attendance: the duty evidence set against the shifts a delivery company scheduled.
 *
 * <p>{@link DutySessionService} knows how long a rider was on duty. This knows whether that was
 * when they were supposed to be — which needs the schedule (V15's shift templates and rider
 * assignments) and the office's corrections (the Manual Attendance Log). It writes nothing to the
 * duty record, ever; everything it says about a day is derived on read from three sources, and it
 * reports which one each figure came from.
 *
 * <h2>How a day is judged</h2>
 *
 * <ul>
 *   <li><strong>No schedule, no verdict.</strong> A rider with no assignment covering a day is a
 *       freelancer on it: they worked ({@link Status#WORKED}) or they did not
 *       ({@link Status#NO_DUTY}). Nothing here may call a freelancer late or absent — they were
 *       never expected.</li>
 *   <li><strong>A scheduled day</strong> with credited duty time is {@link Status#PRESENT}, or
 *       {@link Status#LATE} when the first session that touches the shift began more than the
 *       shift's grace after its start. With none it is {@link Status#ABSENT} once the shift is
 *       over and {@link Status#PENDING} until then — a rider is not absent at 08:01.</li>
 *   <li><strong>A day off</strong> in an assigned rider's week is {@link Status#DAY_OFF}, or
 *       {@link Status#EXTRA} if they worked it anyway, all of which is overtime.</li>
 *   <li><strong>A manual entry</strong> overrides the verdict (sick, leave, excused, present) but
 *       never the evidence: the credited seconds stay what the sessions say, and hours the office
 *       typed are reported separately as manual seconds.</li>
 * </ul>
 *
 * <h2>Which day a session belongs to</h2>
 *
 * <p>A session belongs to the scheduled day whose shift window it overlaps — so a night shift that
 * starts at 22:00 and runs past midnight is one day's work, and a rider who arrives at 00:10 for
 * that 22:00 shift is late for it rather than absent from it and "extra" the next day. A session
 * that touches no shift window belongs to the date it started on. Each session is attributed to
 * exactly one day and counted whole there, so a period's total is never double-counted; this is the
 * deliberate difference from {@code /duty/hours}, which splits a session at every midnight.
 *
 * <p>Every date and wall-clock time is in the platform day zone
 * ({@code delivery.tracking.duty-session.day-zone}), and every conversion to an instant goes through
 * that zone's own rules — Beirut's summer and winter offsets included — never a fixed offset.
 */
@Service
public class AttendanceService {

    /** A schedule may be set up this far ahead, and no further. */
    static final int MAX_DAYS_AHEAD_FOR_SCHEDULE = 90;

    /** Leave and sickness may be recorded this far ahead — planned leave is a real thing. */
    static final int MAX_DAYS_AHEAD_FOR_ENTRY = 180;

    private final DutySessionService dutySessions;
    private final CarrierScopeResolver carrierScope;
    private final RiderPresenceRepository presenceRows;
    private final ShiftTemplateRepository templates;
    private final RiderShiftAssignmentRepository assignments;
    private final AttendanceEntryRepository entries;
    private final int retentionDays;

    public AttendanceService(DutySessionService dutySessions,
                             CarrierScopeResolver carrierScope,
                             RiderPresenceRepository presenceRows,
                             ShiftTemplateRepository templates,
                             RiderShiftAssignmentRepository assignments,
                             AttendanceEntryRepository entries,
                             // Duty sessions are deleted after this many days
                             // (TrackingPartitionMaintenance). A period older than that would read
                             // every scheduled day as ABSENT, which is a lie about somebody's pay.
                             @Value("${delivery.tracking.duty-event-retention-days:400}") int retentionDays) {
        this.dutySessions = dutySessions;
        this.carrierScope = carrierScope;
        this.presenceRows = presenceRows;
        this.templates = templates;
        this.assignments = assignments;
        this.entries = entries;
        this.retentionDays = retentionDays;
    }

    // -----------------------------------------------------------------------------------------
    // Reading
    // -----------------------------------------------------------------------------------------

    /** One rider's sessions over a period, whole. Scoped exactly as {@code /duty/hours} is. */
    @Transactional(readOnly = true)
    public DutySessions riderSessions(String riderId, String callerId, boolean isBackoffice,
                                      AttendancePeriod period) {
        dutySessions.requireReadable(riderId, callerId, isBackoffice);
        Instant now = Instant.now();
        requireWithinHistory(period, today(now));
        return dutySessions.sessionsIn(riderId, period, now);
    }

    /**
     * One rider's attendance for a period: every day judged, and the totals payroll consumes.
     *
     * <p>Scoped exactly as {@code /duty/hours} is — see {@link DutySessionService#requireReadable}.
     * Backoffice reads the rider against their current fleet's schedule.
     */
    @Transactional(readOnly = true)
    public RiderAttendance riderAttendance(String riderId, String callerId, boolean isBackoffice,
                                           AttendancePeriod period) {
        ReadAccess access = dutySessions.requireReadable(riderId, callerId, isBackoffice);
        return compute(riderId, access.carrierId(), period, Instant.now());
    }

    /**
     * Every rider in a fleet, totals only — the one call a pay run makes.
     *
     * <p>The fleet is the one this service can see: riders whose presence row carries the fleet,
     * the same set the roster and every per-rider read are scoped to. One computation per rider;
     * a fleet is tens of riders, and the per-rider read is what this must agree with exactly.
     */
    @Transactional(readOnly = true)
    public FleetAttendance fleetAttendance(String callerId, boolean isBackoffice, UUID requested,
                                           AttendancePeriod period) {
        UUID carrier = fleetOf(callerId, isBackoffice, requested);
        Instant now = Instant.now();
        requireWithinHistory(period, today(now));
        List<RiderTotals> riders = presenceRows.findByCarrierIdOrderByLastSeenAtDesc(carrier)
                .stream()
                .map(RiderPresence::getRiderId)
                .sorted()
                .map(riderId -> {
                    RiderAttendance month = compute(riderId, carrier, period, now);
                    return new RiderTotals(riderId, month.hasSchedule(), month.totals());
                })
                .toList();
        return new FleetAttendance(carrier, zone().getId(), period.from(), period.to(), riders);
    }

    /** The whole derivation. Package-private with an explicit clock for the tests. */
    RiderAttendance compute(String riderId, UUID carrierId, AttendancePeriod period, Instant now) {
        ZoneId zone = zone();
        LocalDate today = LocalDate.ofInstant(now, zone);
        requireWithinHistory(period, today);

        Schedule schedule = scheduleFor(riderId, carrierId, period);
        Map<LocalDate, AttendanceEntry> manual = carrierId == null
                ? Map.of()
                : entries.findLive(riderId, carrierId, period.from(), period.to()).stream()
                        .collect(Collectors.toMap(AttendanceEntry::getWorkDate, Function.identity(),
                                (a, b) -> b));

        // A day either side: a night shift that started the evening before the period, or an
        // early start just before midnight, can own a session that lies partly outside it.
        Instant fetchFrom = period.from().minusDays(1).atStartOfDay(zone).toInstant();
        Instant fetchUntil = period.to().plusDays(2).atStartOfDay(zone).toInstant();
        Map<LocalDate, List<SessionView>> byDay = new TreeMap<>();
        for (SessionView session : dutySessions.views(riderId, fetchFrom, fetchUntil, now)) {
            LocalDate day = attribute(session, schedule, zone);
            if (period.contains(day)) {
                byDay.computeIfAbsent(day, d -> new ArrayList<>()).add(session);
            }
        }

        List<AttendanceDay> days = new ArrayList<>();
        for (LocalDate day : period.dates()) {
            days.add(judge(day, schedule, byDay.getOrDefault(day, List.of()), manual.get(day),
                    zone, today, now));
        }
        return new RiderAttendance(riderId, carrierId, zone.getId(), period.from(), period.to(),
                today, schedule.touches(period), days, AttendanceTotals.of(days));
    }

    /**
     * The day a session belongs to: the earliest scheduled day whose shift window it overlaps,
     * otherwise the date it started on. Only the day before, the day of, and the day after its
     * start can have such a window — a shift is shorter than a day.
     */
    static LocalDate attribute(SessionView session, Schedule schedule, ZoneId zone) {
        LocalDate startDay = LocalDate.ofInstant(session.startedAt(), zone);
        for (LocalDate candidate = startDay.minusDays(1);
             !candidate.isAfter(startDay.plusDays(1));
             candidate = candidate.plusDays(1)) {
            ShiftTemplate shift = schedule.shiftOn(candidate);
            if (shift != null && touches(shift.window(candidate, zone), session)) {
                return candidate;
            }
        }
        return startDay;
    }

    /** Overlap, or — for a session with nothing credited — starting inside the window. */
    private static boolean touches(ShiftTemplate.Window window, SessionView session) {
        if (session.countedUntil().isAfter(session.startedAt())) {
            return window.overlaps(session.startedAt(), session.countedUntil());
        }
        return !session.startedAt().isBefore(window.start())
                && session.startedAt().isBefore(window.end());
    }

    private AttendanceDay judge(LocalDate day, Schedule schedule, List<SessionView> sessions,
                                AttendanceEntry entry, ZoneId zone, LocalDate today, Instant now) {
        ShiftTemplate shift = schedule.shiftOn(day);
        ShiftTemplate.Window window = shift == null ? null : shift.window(day, zone);

        // Evidence is a session with credited time. A session with none — declared on duty and
        // never sighted, or expired with no fix — shows in the log, and proves nothing.
        List<SessionView> evidence = sessions.stream().filter(s -> s.countedSeconds() > 0).toList();
        long worked = evidence.stream().mapToLong(SessionView::countedSeconds).sum();
        Instant clockIn = evidence.isEmpty() ? null : evidence.get(0).startedAt();
        SessionView last = evidence.isEmpty() ? null : evidence.get(evidence.size() - 1);

        Status derived;
        Long lateBy = null;
        long overtime = 0;
        if (day.isAfter(today)) {
            derived = Status.UPCOMING;
        } else if (shift != null) {
            if (!evidence.isEmpty()) {
                // Arrival is the first session that touches the shift; an earlier, separate stint
                // (on for an hour at dawn, off, back at nine) does not make a late rider on time.
                Instant arrived = evidence.stream()
                        .filter(s -> window.overlaps(s.startedAt(), s.countedUntil()))
                        .map(SessionView::startedAt)
                        .findFirst()
                        .orElse(clockIn);
                long secondsAfterStart = Duration.between(window.start(), arrived).getSeconds();
                lateBy = Math.max(0, secondsAfterStart);
                derived = secondsAfterStart > shift.getLateGraceMinutes() * 60L
                        ? Status.LATE
                        : Status.PRESENT;
                overtime = Math.max(0, worked - window.lengthSeconds());
            } else {
                derived = now.isBefore(window.end()) ? Status.PENDING : Status.ABSENT;
            }
        } else if (schedule.assignedOn(day)) {
            derived = evidence.isEmpty() ? Status.DAY_OFF : Status.EXTRA;
            // Every minute on a scheduled day off is beyond the schedule.
            overtime = worked;
        } else {
            derived = evidence.isEmpty() ? Status.NO_DUTY : Status.WORKED;
        }

        Status status = entry == null ? derived : overridden(derived, entry.getStatus());

        // Typed hours count only where there is no evidence. Where the phone shows the day, the
        // phone wins; adding the office's figure on top would pay the day twice.
        long manualSeconds = entry != null && entry.getStatus() == AttendanceEntry.Kind.PRESENT
                && evidence.isEmpty() ? entry.manualSeconds(zone) : 0;
        boolean workedDay = !day.isAfter(today) && (!evidence.isEmpty()
                || (entry != null && entry.getStatus() == AttendanceEntry.Kind.PRESENT));
        Instant clockOut = last == null || last.open() ? null : last.endedAt();

        return new AttendanceDay(
                day,
                status,
                derived,
                shift == null ? null : ScheduledShift.of(shift, window),
                clockIn,
                clockOut,
                DutySessionService.localStamp(clockIn, zone),
                DutySessionService.localStamp(clockOut, zone),
                last == null ? null : last.endReason(),
                sessions.stream().anyMatch(SessionView::open),
                workedDay,
                worked,
                DutySessionService.hours(worked),
                manualSeconds,
                lateBy,
                overtime,
                sessions,
                entry == null ? null : ManualEntry.of(entry, zone));
    }

    /** What a manual entry makes of a derived verdict. */
    static Status overridden(Status derived, AttendanceEntry.Kind kind) {
        return switch (kind) {
            case PRESENT -> switch (derived) {
                case ABSENT, PENDING -> Status.PRESENT;
                case DAY_OFF -> Status.EXTRA;
                case NO_DUTY -> Status.WORKED;
                // Already present by the evidence — including LATE, which a "present" entry does
                // not excuse; LATE_EXCUSED is the entry that does.
                default -> derived;
            };
            // Excusing a late only means something on a late day.
            case LATE_EXCUSED -> derived == Status.LATE ? Status.LATE_EXCUSED : derived;
            case ABSENT_EXCUSED -> Status.EXCUSED;
            case SICK -> Status.SICK;
            case LEAVE -> Status.LEAVE;
        };
    }

    // -----------------------------------------------------------------------------------------
    // Shifts
    // -----------------------------------------------------------------------------------------

    /** A fleet's shifts, archived included and marked, each with how many riders are on it. */
    @Transactional(readOnly = true)
    public List<ShiftView> shifts(String callerId, boolean isBackoffice, UUID requested) {
        UUID carrier = fleetOf(callerId, isBackoffice, requested);
        LocalDate today = today(Instant.now());
        return templates.findByCarrierIdOrderByCreatedAt(carrier).stream()
                .map(t -> ShiftView.of(t, assignments.countActiveOrUpcoming(t.getId(), today)))
                .toList();
    }

    /** A new shift in the caller's own fleet. The fleet is the caller's token's, never a field. */
    @Transactional
    public ShiftView createShift(String callerId, String name, String startTime, String endTime,
                                 List<String> days, Integer lateGraceMinutes) {
        UUID carrier = carrierScope.requireScopeFor(callerId);
        ShiftTemplate shift;
        try {
            shift = ShiftTemplate.create(carrier, name, time(startTime, "startTime"),
                    time(endTime, "endTime"), daysOf(days),
                    lateGraceMinutes == null ? 10 : lateGraceMinutes, callerId, Instant.now());
        } catch (IllegalArgumentException e) {
            throw new InvalidRequestException(e.getMessage());
        }
        templates.save(shift);
        return ShiftView.of(shift, 0);
    }

    /**
     * Retires a shift for new assignments.
     *
     * <p>Refused while anybody is on it or about to start it: archiving would otherwise leave
     * riders on a shift the page no longer lists, with nothing to tell the office they are there.
     */
    @Transactional
    public ShiftView archiveShift(String callerId, UUID shiftId) {
        UUID carrier = carrierScope.requireScopeFor(callerId);
        ShiftTemplate shift = templates.findByIdAndCarrierId(shiftId, carrier)
                .orElseThrow(ShiftNotFoundException::new);
        long riders = assignments.countActiveOrUpcoming(shift.getId(), today(Instant.now()));
        if (riders > 0) {
            throw new ConflictException("Move the riders on this shift to another one first.",
                    riders);
        }
        shift.archive(Instant.now());
        templates.save(shift);
        return ShiftView.of(shift, 0);
    }

    /** Who in the fleet is on which shift, today and from later dates. */
    @Transactional(readOnly = true)
    public List<AssignmentView> fleetAssignments(String callerId, boolean isBackoffice,
                                                 UUID requested) {
        UUID carrier = fleetOf(callerId, isBackoffice, requested);
        return views(assignments.findCurrentAndUpcoming(carrier, today(Instant.now())));
    }

    /**
     * Puts a rider on a shift from a date — or, with no shift, takes them off their schedule, which
     * makes them a freelancer again from that date.
     *
     * <p>Never backdated. A schedule set on the 15th must not reach back and mark the 1st to the
     * 14th absent, least of all after those days were paid. The row that was running is closed the
     * day before, and anything that had been set up to start later is replaced.
     *
     * <p>Idempotent: putting a rider on the shift they are already on changes nothing.
     */
    @Transactional
    public List<AssignmentView> assign(String riderId, String callerId, UUID shiftId,
                                       String effectiveFrom) {
        UUID carrier = dutySessions.requireOwnFleet(riderId, callerId);
        Instant now = Instant.now();
        LocalDate today = today(now);
        LocalDate from = effectiveFrom == null || effectiveFrom.isBlank()
                ? today
                : AttendancePeriod.date(effectiveFrom, "effectiveFrom");
        if (from.isBefore(today)) {
            throw new InvalidRequestException(
                    "A schedule can start today or later. Past days keep the schedule they were "
                            + "worked against.");
        }
        if (from.isAfter(today.plusDays(MAX_DAYS_AHEAD_FOR_SCHEDULE))) {
            throw new InvalidRequestException("A schedule can be set up at most "
                    + MAX_DAYS_AHEAD_FOR_SCHEDULE + " days ahead.");
        }

        ShiftTemplate shift = null;
        if (shiftId != null) {
            shift = templates.findByIdAndCarrierId(shiftId, carrier)
                    .orElseThrow(ShiftNotFoundException::new);
            if (shift.isArchived()) {
                throw new ConflictException("That shift has been retired. Choose a current one.", 0);
            }
        }

        List<RiderShiftAssignment> fromThen = assignments.findFrom(riderId, carrier, from);
        if (shift != null && fromThen.size() == 1
                && fromThen.get(0).getTemplateId().equals(shift.getId())
                && fromThen.get(0).getEffectiveTo() == null
                && !fromThen.get(0).getEffectiveFrom().isAfter(from)) {
            return views(assignments.findFrom(riderId, carrier, today));
        }

        for (RiderShiftAssignment row : fromThen) {
            if (row.getEffectiveFrom().isBefore(from)) {
                row.endOn(from.minusDays(1));
                assignments.save(row);
            } else {
                // Had not started by the new date, so it never applied to anything that is kept.
                assignments.delete(row);
            }
        }
        // Flushed before the insert on purpose. Hibernate runs inserts ahead of updates and
        // deletes when it flushes, so without this the new open row would reach the partial
        // unique index while the old open row was still open, and the reassignment would fail.
        assignments.flush();
        if (shift != null) {
            assignments.save(RiderShiftAssignment.start(riderId, carrier, shift.getId(), from,
                    callerId, now));
        }
        return views(assignments.findFrom(riderId, carrier, today));
    }

    private List<AssignmentView> views(List<RiderShiftAssignment> rows) {
        Map<UUID, ShiftTemplate> shifts = templates.findByIdIn(rows.stream()
                        .map(RiderShiftAssignment::getTemplateId)
                        .collect(Collectors.toSet()))
                .stream()
                .collect(Collectors.toMap(ShiftTemplate::getId, Function.identity()));
        return rows.stream().map(row -> AssignmentView.of(row, shifts.get(row.getTemplateId())))
                .toList();
    }

    // -----------------------------------------------------------------------------------------
    // The Manual Attendance Log
    // -----------------------------------------------------------------------------------------

    /**
     * Records — or replaces — what the office says about one day.
     *
     * <p>A replacement revokes the previous entry rather than editing it, so the record of who
     * changed a day, and from what, survives. Duty sessions are never touched.
     */
    @Transactional
    public ManualEntry recordEntry(String riderId, String callerId, String date, String status,
                                   String clockIn, String clockOut, String note) {
        UUID carrier = dutySessions.requireOwnFleet(riderId, callerId);
        Instant now = Instant.now();
        ZoneId zone = zone();
        LocalDate today = LocalDate.ofInstant(now, zone);
        LocalDate day = AttendancePeriod.date(date, "date");
        AttendanceEntry.Kind kind = kindOf(status);

        if (day.isBefore(today.minusDays(retentionDays))) {
            throw new InvalidRequestException("That day is older than the " + retentionDays
                    + " days of duty history the platform keeps.");
        }
        if (day.isAfter(today.plusDays(MAX_DAYS_AHEAD_FOR_ENTRY))) {
            throw new InvalidRequestException("Leave can be recorded at most "
                    + MAX_DAYS_AHEAD_FOR_ENTRY + " days ahead.");
        }
        if (day.isAfter(today) && (kind == AttendanceEntry.Kind.PRESENT
                || kind == AttendanceEntry.Kind.LATE_EXCUSED)) {
            throw new InvalidRequestException(
                    "A day that has not happened yet can only be marked as leave, sick or excused.");
        }

        AttendanceEntry fresh;
        try {
            fresh = AttendanceEntry.record(riderId, carrier, day, kind,
                    clockIn == null || clockIn.isBlank() ? null : time(clockIn, "clockIn"),
                    clockOut == null || clockOut.isBlank() ? null : time(clockOut, "clockOut"),
                    note, callerId, now);
        } catch (IllegalArgumentException e) {
            throw new InvalidRequestException(e.getMessage());
        }

        entries.findByRiderIdAndCarrierIdAndWorkDateAndRevokedAtIsNull(riderId, carrier, day)
                .ifPresent(previous -> {
                    previous.revoke(callerId, now);
                    entries.save(previous);
                });
        // Same reason as in assign: the revocation must reach the partial unique index before
        // the replacement does.
        entries.flush();
        entries.save(fresh);
        return ManualEntry.of(fresh, zone);
    }

    /** Withdraws the office's entry for a day. The day goes back to what the evidence says. */
    @Transactional
    public void withdrawEntry(String riderId, String callerId, String date) {
        UUID carrier = dutySessions.requireOwnFleet(riderId, callerId);
        LocalDate day = AttendancePeriod.date(date, "date");
        AttendanceEntry live = entries
                .findByRiderIdAndCarrierIdAndWorkDateAndRevokedAtIsNull(riderId, carrier, day)
                .orElseThrow(EntryNotFoundException::new);
        live.revoke(callerId, Instant.now());
        entries.save(live);
    }

    // -----------------------------------------------------------------------------------------
    // Plumbing
    // -----------------------------------------------------------------------------------------

    public ZoneId zone() {
        return dutySessions.zone();
    }

    private LocalDate today(Instant now) {
        return LocalDate.ofInstant(now, zone());
    }

    /**
     * Backoffice names the fleet; a carrier's is their own, and any fleet they name is ignored —
     * there is no request shape in which a carrier reads a competitor's schedule.
     */
    private UUID fleetOf(String callerId, boolean isBackoffice, UUID requested) {
        if (isBackoffice) {
            if (requested == null) {
                throw new InvalidRequestException("Name the delivery company (carrierId).");
            }
            return requested;
        }
        return carrierScope.requireScopeFor(callerId);
    }

    private void requireWithinHistory(AttendancePeriod period, LocalDate today) {
        if (period.from().isBefore(today.minusDays(retentionDays))) {
            throw new InvalidRequestException("Duty history is kept for " + retentionDays
                    + " days, so a period that old can no longer be judged.");
        }
    }

    private Schedule scheduleFor(String riderId, UUID carrierId, AttendancePeriod period) {
        if (carrierId == null) {
            return Schedule.NONE;
        }
        List<RiderShiftAssignment> rows = assignments.findTouching(riderId, carrierId,
                period.from().minusDays(1), period.to().plusDays(1));
        if (rows.isEmpty()) {
            return Schedule.NONE;
        }
        Map<UUID, ShiftTemplate> shifts = templates.findByIdIn(rows.stream()
                        .map(RiderShiftAssignment::getTemplateId)
                        .collect(Collectors.toSet()))
                .stream()
                .collect(Collectors.toMap(ShiftTemplate::getId, Function.identity()));
        return new Schedule(rows, shifts);
    }

    static LocalTime time(String value, String field) {
        if (value == null || value.isBlank()) {
            throw new InvalidRequestException(field + " is required, as HH:mm.");
        }
        try {
            return LocalTime.parse(value.trim());
        } catch (DateTimeParseException e) {
            throw new InvalidRequestException(field + " must be a time such as 08:00.");
        }
    }

    static Set<DayOfWeek> daysOf(List<String> days) {
        if (days == null || days.isEmpty()) {
            throw new InvalidRequestException("Choose at least one day the shift runs on.");
        }
        EnumSet<DayOfWeek> set = EnumSet.noneOf(DayOfWeek.class);
        for (String day : days) {
            try {
                set.add(DayOfWeek.valueOf(day.trim().toUpperCase(Locale.ROOT)));
            } catch (IllegalArgumentException | NullPointerException e) {
                throw new InvalidRequestException("days must be weekday names such as MONDAY.");
            }
        }
        return set;
    }

    private static AttendanceEntry.Kind kindOf(String status) {
        if (status == null || status.isBlank()) {
            throw new InvalidRequestException("Choose what happened on the day.");
        }
        try {
            return AttendanceEntry.Kind.valueOf(status.trim().toUpperCase(Locale.ROOT));
        } catch (IllegalArgumentException e) {
            throw new InvalidRequestException(
                    "status must be one of PRESENT, LATE_EXCUSED, ABSENT_EXCUSED, SICK or LEAVE.");
        }
    }

    /** The schedule that applies to one rider in one fleet over a period. */
    static final class Schedule {

        static final Schedule NONE = new Schedule(List.of(), Map.of());

        private final List<RiderShiftAssignment> rows;
        private final Map<UUID, ShiftTemplate> shifts;

        Schedule(List<RiderShiftAssignment> rows, Map<UUID, ShiftTemplate> shifts) {
            this.rows = rows;
            this.shifts = shifts;
        }

        boolean assignedOn(LocalDate day) {
            return rows.stream().anyMatch(row -> row.covers(day));
        }

        /** The shift the rider works on {@code day}, or null for a day off or no schedule. */
        ShiftTemplate shiftOn(LocalDate day) {
            for (RiderShiftAssignment row : rows) {
                if (row.covers(day)) {
                    ShiftTemplate shift = shifts.get(row.getTemplateId());
                    return shift != null && shift.runsOn(day.getDayOfWeek()) ? shift : null;
                }
            }
            return null;
        }

        boolean touches(AttendancePeriod period) {
            return period.dates().stream().anyMatch(this::assignedOn);
        }
    }

    // -----------------------------------------------------------------------------------------
    // Types — the payroll contract. See docs/rider-attendance-contract.md.
    // -----------------------------------------------------------------------------------------

    /** What a day comes to. */
    public enum Status {
        /** Scheduled, and on time. */
        PRESENT,
        /** Scheduled, and the first session touching the shift began after start plus grace. */
        LATE,
        /** Scheduled, the shift is over, and there is no credited duty time and no entry. */
        ABSENT,
        /** Scheduled today, not yet in, and the shift is not over — not absent yet. */
        PENDING,
        /** An assigned rider's scheduled day off. */
        DAY_OFF,
        /** Worked on a scheduled day off. All of it is overtime. */
        EXTRA,
        /** No schedule (a freelancer) and worked. */
        WORKED,
        /** No schedule and did not work. Never an absence. */
        NO_DUTY,
        /** After today. */
        UPCOMING,
        /** Late, and the office excused it. Not counted as a late. */
        LATE_EXCUSED,
        /** Did not work, excused by the office. Not counted as an absence. */
        EXCUSED,
        SICK,
        LEAVE
    }

    /**
     * One rider over one period.
     *
     * @param carrierId   the fleet whose schedule applied — null for a platform rider
     * @param today       today in {@code zone}; days after it are {@link Status#UPCOMING}
     * @param hasSchedule whether any shift assignment touches the period. False means a freelancer
     *                    for the whole period: the client should show time on duty only, with no
     *                    late or absent legend at all.
     */
    public record RiderAttendance(
            String riderId,
            UUID carrierId,
            String zone,
            LocalDate from,
            LocalDate to,
            LocalDate today,
            boolean hasSchedule,
            List<AttendanceDay> days,
            AttendanceTotals totals) {
    }

    /**
     * One judged day.
     *
     * @param status          the verdict, after any manual entry
     * @param derivedStatus   what the evidence and schedule alone say — kept so a corrected day
     *                        still shows what the office corrected
     * @param scheduled       the shift worked against, or null for a day off or no schedule
     * @param clockIn         the first credited session's start, or null
     * @param clockOut        the last credited session's close; null when there is none or it is
     *                        still open
     * @param clockInLocal    {@code clockIn} as wall-clock time in the zone, yyyy-MM-ddTHH:mm —
     *                        what a console prints, whatever zone its browser is in
     * @param clockOutLocal   {@code clockOut} the same way; its date is the next day after a night
     * @param clockOutReason  who closed that last session; EXPIRED means the platform closed it at
     *                        the rider's last sighting, not a tap
     * @param onShiftNow      a session attributed to this day is still open
     * @param worked          counts as a day worked (credited time, or a manual PRESENT)
     * @param workedSeconds   credited duty time of the sessions attributed to this day — evidence
     * @param manualSeconds   hours the office typed, only on a day with no evidence
     * @param lateBySeconds   seconds between the shift start and arrival (0 when early); null when
     *                        the day was not scheduled or nobody arrived
     * @param overtimeSeconds credited time beyond the scheduled length; all of it on a day off;
     *                        never anything for a freelancer
     */
    public record AttendanceDay(
            LocalDate date,
            Status status,
            Status derivedStatus,
            ScheduledShift scheduled,
            Instant clockIn,
            Instant clockOut,
            String clockInLocal,
            String clockOutLocal,
            DutySession.EndReason clockOutReason,
            boolean onShiftNow,
            boolean worked,
            long workedSeconds,
            BigDecimal workedHours,
            long manualSeconds,
            Long lateBySeconds,
            long overtimeSeconds,
            List<SessionView> sessions,
            ManualEntry entry) {
    }

    /**
     * The shift a day was judged against, with its real instants that day.
     *
     * @param startTime        wall-clock HH:mm in the zone
     * @param scheduledSeconds the window's real length that day — an hour more or less on the
     *                         nights the clocks change
     */
    public record ScheduledShift(
            UUID shiftId,
            String name,
            String startTime,
            String endTime,
            boolean overnight,
            Instant startsAt,
            Instant endsAt,
            long scheduledSeconds,
            int lateGraceMinutes) {

        static ScheduledShift of(ShiftTemplate shift, ShiftTemplate.Window window) {
            return new ScheduledShift(shift.getId(), shift.getName(), hhmm(shift.getStartTime()),
                    hhmm(shift.getEndTime()), shift.isOvernight(), window.start(), window.end(),
                    window.lengthSeconds(), shift.getLateGraceMinutes());
        }
    }

    /** The office's live entry for a day. {@code recordedBy} is the staff member's subject. */
    public record ManualEntry(
            UUID id,
            LocalDate date,
            AttendanceEntry.Kind status,
            String clockIn,
            String clockOut,
            long manualSeconds,
            String note,
            String recordedBy,
            Instant recordedAt) {

        static ManualEntry of(AttendanceEntry entry, ZoneId zone) {
            return new ManualEntry(entry.getId(), entry.getWorkDate(), entry.getStatus(),
                    entry.getClockIn() == null ? null : hhmm(entry.getClockIn()),
                    entry.getClockOut() == null ? null : hhmm(entry.getClockOut()),
                    entry.manualSeconds(zone), entry.getNote(), entry.getRecordedBy(),
                    entry.getRecordedAt());
        }
    }

    /**
     * A period's totals — what a payroll module consumes.
     *
     * <p>Seconds are the exact figures and what arithmetic must use; the hour fields are the same
     * over 3600 at two decimals, for display. Evidence ({@code workedSeconds}) and the office's
     * claims ({@code manualSeconds}) are never summed here: whether manual hours are paid is
     * payroll's rule, not this service's.
     *
     * @param scheduledDays    days in the period with a shift, including days still to come
     * @param daysWorked       days up to today with credited time or a manual PRESENT
     * @param absences         unexcused absences only
     * @param lates            unexcused lates only
     * @param scheduledSeconds the real length of every scheduled shift in the period
     * @param overtimeSeconds  credited time beyond each scheduled day's length, plus every credited
     *                         second on a scheduled day off; evidence only
     */
    public record AttendanceTotals(
            int scheduledDays,
            int daysWorked,
            int absences,
            int lates,
            int excusedLates,
            int excusedAbsences,
            int sickDays,
            int leaveDays,
            long workedSeconds,
            long manualSeconds,
            long scheduledSeconds,
            long overtimeSeconds,
            BigDecimal workedHours,
            BigDecimal overtimeHours) {

        static AttendanceTotals of(List<AttendanceDay> days) {
            int scheduled = 0;
            int worked = 0;
            int absences = 0;
            int lates = 0;
            int excusedLates = 0;
            int excused = 0;
            int sick = 0;
            int leave = 0;
            long workedSeconds = 0;
            long manualSeconds = 0;
            long scheduledSeconds = 0;
            long overtime = 0;
            for (AttendanceDay day : days) {
                if (day.scheduled() != null) {
                    scheduled++;
                    scheduledSeconds += day.scheduled().scheduledSeconds();
                }
                if (day.worked()) {
                    worked++;
                }
                switch (day.status()) {
                    case ABSENT -> absences++;
                    case LATE -> lates++;
                    case LATE_EXCUSED -> excusedLates++;
                    case EXCUSED -> excused++;
                    case SICK -> sick++;
                    case LEAVE -> leave++;
                    default -> {
                        // the rest are not counted separately
                    }
                }
                workedSeconds += day.workedSeconds();
                manualSeconds += day.manualSeconds();
                overtime += day.overtimeSeconds();
            }
            return new AttendanceTotals(scheduled, worked, absences, lates, excusedLates, excused,
                    sick, leave, workedSeconds, manualSeconds, scheduledSeconds, overtime,
                    DutySessionService.hours(workedSeconds), DutySessionService.hours(overtime));
        }
    }

    /** One rider's line in a fleet's pay-run read. */
    public record RiderTotals(String riderId, boolean hasSchedule, AttendanceTotals totals) {
    }

    /** A fleet over one period. */
    public record FleetAttendance(
            UUID carrierId,
            String zone,
            LocalDate from,
            LocalDate to,
            List<RiderTotals> riders) {
    }

    /**
     * A shift as the schedule page shows it.
     *
     * @param riders how many riders are on it today or will start it later
     */
    public record ShiftView(
            UUID id,
            String name,
            String startTime,
            String endTime,
            boolean overnight,
            List<DayOfWeek> days,
            int lateGraceMinutes,
            boolean archived,
            long riders) {

        static ShiftView of(ShiftTemplate shift, long riders) {
            return new ShiftView(shift.getId(), shift.getName(), hhmm(shift.getStartTime()),
                    hhmm(shift.getEndTime()), shift.isOvernight(), List.copyOf(shift.days()),
                    shift.getLateGraceMinutes(), shift.isArchived(), riders);
        }
    }

    /** That a rider works a shift from one date to another (inclusive; null = open-ended). */
    public record AssignmentView(
            String riderId,
            UUID shiftId,
            String shiftName,
            LocalDate effectiveFrom,
            LocalDate effectiveTo) {

        static AssignmentView of(RiderShiftAssignment row, ShiftTemplate shift) {
            return new AssignmentView(row.getRiderId(), row.getTemplateId(),
                    shift == null ? null : shift.getName(), row.getEffectiveFrom(),
                    row.getEffectiveTo());
        }
    }

    static String hhmm(LocalTime time) {
        return String.format(Locale.ROOT, "%02d:%02d", time.getHour(), time.getMinute());
    }

    // -----------------------------------------------------------------------------------------
    // Refusals
    // -----------------------------------------------------------------------------------------

    /** A request this service will not act on as asked; the message says why. 400. */
    public static class InvalidRequestException extends RuntimeException {
        public InvalidRequestException(String message) {
            super(message);
        }
    }

    /** No such shift in the caller's fleet — a competitor's shift id reads the same. 404. */
    public static class ShiftNotFoundException extends RuntimeException {
        public ShiftNotFoundException() {
            super("No such shift in your company");
        }
    }

    /** No live entry for that day. 404. */
    public static class EntryNotFoundException extends RuntimeException {
        public EntryNotFoundException() {
            super("There is no attendance entry for that day");
        }
    }

    /** The request is fine but the state forbids it. 409. */
    public static class ConflictException extends RuntimeException {
        private final long riders;

        public ConflictException(String message, long riders) {
            super(message);
            this.riders = riders;
        }

        public long riders() {
            return riders;
        }
    }
}
