package com.delivery.tracking.domain;

import java.time.DayOfWeek;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalTime;
import java.time.ZoneId;
import java.util.EnumSet;
import java.util.Set;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * A shift a delivery company runs — "Beirut Central Day, 08:00-18:00, Monday to Friday".
 *
 * <p>The hours are wall-clock times in the platform's day zone, never instants, and are turned
 * into an instant per day by {@link #window}. That is the whole of the time-zone handling for
 * schedules, and it is deliberately done through the zone's own rules rather than a fixed offset:
 * Beirut is UTC+3 in summer and UTC+2 in winter, so "08:00" is 05:00Z in July and 06:00Z in
 * January, and a rider who arrives at 08:05 local is five minutes late in both.
 *
 * <p>The hours cannot be edited after creation. See V15: an editable template would silently
 * re-judge every past day worked against it. {@link #archive} retires one without touching the
 * history that still points at it.
 */
@Entity
@Table(name = "shift_templates")
public class ShiftTemplate {

    /** Bounds from the V15 check constraints, restated so a refusal is a 400 and not a 500. */
    public static final int MAX_NAME = 80;
    public static final int MAX_GRACE_MINUTES = 120;

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "carrier_id", nullable = false, updatable = false)
    private UUID carrierId;

    @Column(name = "name", nullable = false, length = MAX_NAME)
    private String name;

    @Column(name = "start_time", nullable = false, updatable = false)
    private LocalTime startTime;

    @Column(name = "end_time", nullable = false, updatable = false)
    private LocalTime endTime;

    @Column(name = "days_mask", nullable = false, updatable = false)
    private short daysMask;

    @Column(name = "late_grace_minutes", nullable = false, updatable = false)
    private short lateGraceMinutes;

    @Column(name = "archived_at")
    private Instant archivedAt;

    @Column(name = "created_by", nullable = false, updatable = false, length = 64)
    private String createdBy;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    protected ShiftTemplate() {
        // for JPA
    }

    /**
     * A new shift, validated against the same rules the table enforces.
     *
     * @throws IllegalArgumentException with a sentence fit for the caller when any rule fails
     */
    public static ShiftTemplate create(UUID carrierId, String name, LocalTime start, LocalTime end,
                                       Set<DayOfWeek> days, int lateGraceMinutes,
                                       String createdBy, Instant now) {
        String trimmed = name == null ? "" : name.trim();
        if (trimmed.isEmpty()) {
            throw new IllegalArgumentException("A shift needs a name.");
        }
        if (trimmed.length() > MAX_NAME) {
            throw new IllegalArgumentException(
                    "A shift name can be at most " + MAX_NAME + " characters.");
        }
        if (start == null || end == null) {
            throw new IllegalArgumentException("A shift needs a start and an end time.");
        }
        if (start.equals(end)) {
            throw new IllegalArgumentException("A shift cannot start and end at the same time.");
        }
        if (days == null || days.isEmpty()) {
            throw new IllegalArgumentException("Choose at least one day the shift runs on.");
        }
        if (lateGraceMinutes < 0 || lateGraceMinutes > MAX_GRACE_MINUTES) {
            throw new IllegalArgumentException(
                    "The grace period must be between 0 and " + MAX_GRACE_MINUTES + " minutes.");
        }

        ShiftTemplate t = new ShiftTemplate();
        t.id = UUID.randomUUID();
        t.carrierId = carrierId;
        t.name = trimmed;
        // Minutes only. Seconds on a schedule are noise nobody typed, and they would make
        // "08:00:30" late-by-thirty-seconds a thing a rider could be.
        t.startTime = start.withSecond(0).withNano(0);
        t.endTime = end.withSecond(0).withNano(0);
        t.daysMask = (short) maskOf(days);
        t.lateGraceMinutes = (short) lateGraceMinutes;
        t.createdBy = createdBy;
        t.createdAt = now;
        return t;
    }

    /** Monday = bit 0 ... Sunday = bit 6, as V15 documents. */
    public static int maskOf(Set<DayOfWeek> days) {
        int mask = 0;
        for (DayOfWeek day : days) {
            mask |= 1 << (day.getValue() - 1);
        }
        return mask;
    }

    public Set<DayOfWeek> days() {
        EnumSet<DayOfWeek> days = EnumSet.noneOf(DayOfWeek.class);
        for (DayOfWeek day : DayOfWeek.values()) {
            if (runsOn(day)) {
                days.add(day);
            }
        }
        return days;
    }

    public boolean runsOn(DayOfWeek day) {
        return (daysMask & (1 << (day.getValue() - 1))) != 0;
    }

    /** Ends the next morning. The shift still belongs to the day it starts on. */
    public boolean isOvernight() {
        return !endTime.isAfter(startTime);
    }

    /**
     * The instants this shift covers on {@code day}, through the zone's own rules.
     *
     * <p>A start inside a spring-forward gap is moved forward by the gap, which is what
     * {@link java.time.ZonedDateTime#of} does and what a wall clock does too; a start inside the
     * autumn overlap takes the earlier offset. Either way the length of the window is the real
     * elapsed time, so a night shift on the night the clocks go back is genuinely an hour longer.
     */
    public Window window(LocalDate day, ZoneId zone) {
        Instant start = day.atTime(startTime).atZone(zone).toInstant();
        LocalDate endDay = isOvernight() ? day.plusDays(1) : day;
        Instant end = endDay.atTime(endTime).atZone(zone).toInstant();
        return new Window(start, end);
    }

    /** Retires the shift for new assignments. History that points at it keeps reading. */
    public void archive(Instant at) {
        if (archivedAt == null) {
            archivedAt = at;
        }
    }

    public boolean isArchived() {
        return archivedAt != null;
    }

    public UUID getId() {
        return id;
    }

    public UUID getCarrierId() {
        return carrierId;
    }

    public String getName() {
        return name;
    }

    public LocalTime getStartTime() {
        return startTime;
    }

    public LocalTime getEndTime() {
        return endTime;
    }

    public int getLateGraceMinutes() {
        return lateGraceMinutes;
    }

    public Instant getArchivedAt() {
        return archivedAt;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    /**
     * One day's scheduled interval, half-open {@code [start, end)}.
     */
    public record Window(Instant start, Instant end) {

        public long lengthSeconds() {
            return Duration.between(start, end).getSeconds();
        }

        /** Whether {@code [from, until)} shares any time with this window. */
        public boolean overlaps(Instant from, Instant until) {
            return from.isBefore(end) && until.isAfter(start);
        }
    }
}
