package com.delivery.tracking.domain;

import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalTime;
import java.time.ZoneId;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * One line of the Manual Attendance Log: what the office asserts about a rider's day.
 *
 * <p>A claim, not evidence, and kept apart from it. The duty sessions say what the rider's phone
 * showed; this says what a person at the company decided. Attendance reads both and reports which
 * one a figure came from, so payroll can pay manual hours or not as its own rule says.
 *
 * <p>Append-only: an edit revokes this row and a new one takes its place (see V15), so the record
 * of who changed a day, and from what, survives every correction.
 */
@Entity
@Table(name = "attendance_entries")
public class AttendanceEntry {

    public static final int MAX_NOTE = 500;

    /** What the office says happened. */
    public enum Kind {
        /** Worked, though the duty evidence does not show it. May carry manual clock times. */
        PRESENT,
        /** Arrived late for a reason the company accepts. Not counted as a late. */
        LATE_EXCUSED,
        /** Did not work, and is excused. */
        ABSENT_EXCUSED,
        /** Did not work: sick. */
        SICK,
        /** Did not work: on leave. */
        LEAVE
    }

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "rider_id", nullable = false, updatable = false, length = 64)
    private String riderId;

    @Column(name = "carrier_id", nullable = false, updatable = false)
    private UUID carrierId;

    @Column(name = "work_date", nullable = false, updatable = false)
    private LocalDate workDate;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false, updatable = false, length = 16)
    private Kind status;

    @Column(name = "clock_in", updatable = false)
    private LocalTime clockIn;

    @Column(name = "clock_out", updatable = false)
    private LocalTime clockOut;

    @Column(name = "note", updatable = false, length = MAX_NOTE)
    private String note;

    @Column(name = "recorded_by", nullable = false, updatable = false, length = 64)
    private String recordedBy;

    @Column(name = "recorded_at", nullable = false, updatable = false)
    private Instant recordedAt;

    @Column(name = "revoked_by", length = 64)
    private String revokedBy;

    @Column(name = "revoked_at")
    private Instant revokedAt;

    protected AttendanceEntry() {
        // for JPA
    }

    /**
     * A new entry, validated against the same rules the table enforces.
     *
     * @throws IllegalArgumentException with a sentence fit for the caller when any rule fails
     */
    public static AttendanceEntry record(String riderId, UUID carrierId, LocalDate day, Kind status,
                                         LocalTime clockIn, LocalTime clockOut, String note,
                                         String recordedBy, Instant now) {
        if (status == null) {
            throw new IllegalArgumentException("Choose what happened on the day.");
        }
        if ((clockIn == null) != (clockOut == null)) {
            throw new IllegalArgumentException("Give both a clock-in and a clock-out time, or neither.");
        }
        if (clockIn != null && status != Kind.PRESENT) {
            throw new IllegalArgumentException(
                    "Clock times can only be recorded on a day marked present.");
        }
        if (clockIn != null && clockIn.withSecond(0).withNano(0)
                .equals(clockOut.withSecond(0).withNano(0))) {
            throw new IllegalArgumentException("Clock-in and clock-out cannot be the same time.");
        }
        String trimmed = note == null ? null : note.trim();
        if (trimmed != null && trimmed.length() > MAX_NOTE) {
            throw new IllegalArgumentException(
                    "A note can be at most " + MAX_NOTE + " characters.");
        }

        AttendanceEntry e = new AttendanceEntry();
        e.id = UUID.randomUUID();
        e.riderId = riderId;
        e.carrierId = carrierId;
        e.workDate = day;
        e.status = status;
        e.clockIn = clockIn == null ? null : clockIn.withSecond(0).withNano(0);
        e.clockOut = clockOut == null ? null : clockOut.withSecond(0).withNano(0);
        e.note = trimmed == null || trimmed.isEmpty() ? null : trimmed;
        e.recordedBy = recordedBy;
        e.recordedAt = now;
        return e;
    }

    /** Replaced or withdrawn. The row stays, as history. */
    public void revoke(String by, Instant at) {
        if (revokedAt == null) {
            revokedBy = by;
            revokedAt = at;
        }
    }

    /**
     * The hours the office typed, as real elapsed time in {@code zone} — zero when none were typed.
     * A clock-out at or before the clock-in ends the next morning.
     */
    public long manualSeconds(ZoneId zone) {
        if (clockIn == null || clockOut == null) {
            return 0;
        }
        Instant in = workDate.atTime(clockIn).atZone(zone).toInstant();
        LocalDate outDay = clockOut.isAfter(clockIn) ? workDate : workDate.plusDays(1);
        Instant out = outDay.atTime(clockOut).atZone(zone).toInstant();
        return Math.max(0, Duration.between(in, out).getSeconds());
    }

    public UUID getId() {
        return id;
    }

    public String getRiderId() {
        return riderId;
    }

    public UUID getCarrierId() {
        return carrierId;
    }

    public LocalDate getWorkDate() {
        return workDate;
    }

    public Kind getStatus() {
        return status;
    }

    public LocalTime getClockIn() {
        return clockIn;
    }

    public LocalTime getClockOut() {
        return clockOut;
    }

    public String getNote() {
        return note;
    }

    public String getRecordedBy() {
        return recordedBy;
    }

    public Instant getRecordedAt() {
        return recordedAt;
    }

    public Instant getRevokedAt() {
        return revokedAt;
    }
}
