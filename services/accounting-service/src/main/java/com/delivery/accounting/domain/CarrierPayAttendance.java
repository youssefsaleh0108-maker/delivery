package com.delivery.accounting.domain;

import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * One rider's attendance totals as a pay run read them.
 *
 * <p>A copy, on purpose. Order-tracking keeps judging a period after it ends — a night shift's 00:10
 * arrival, a session still open, an office entry made weeks later — so the live figures are not the
 * ones a run was computed with. Only an explicit recompute of a draft replaces these rows; editing a
 * draft and approving it read them, and an approved run keeps them as the hours its approver saw.
 *
 * <p>A rider the read listed whose own figures could not be believed is kept too, with no figures and
 * the reason: their hours are unknown and everyone else's are not, and an edit or the approval still
 * knows why without reading attendance again.
 */
@Entity
@Table(name = "carrier_pay_attendance")
public class CarrierPayAttendance {

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "run_id", nullable = false, updatable = false)
    private UUID runId;

    @Column(name = "rider_ref", nullable = false, updatable = false, length = 64)
    private String riderRef;

    @Column(name = "worked_seconds", updatable = false)
    private Long workedSeconds;

    @Column(name = "manual_seconds", updatable = false)
    private Long manualSeconds;

    @Column(name = "overtime_seconds", updatable = false)
    private Long overtimeSeconds;

    @Column(name = "lates", updatable = false)
    private Integer lates;

    @Column(name = "absences", updatable = false)
    private Integer absences;

    /** Why this rider's figures were not believed, as a code; null when they were. */
    @Column(name = "unavailable_reason", updatable = false, length = 32)
    private String unavailableReason;

    protected CarrierPayAttendance() {
        // for JPA
    }

    public static CarrierPayAttendance of(UUID runId, String riderRef, long workedSeconds,
                                         long manualSeconds, long overtimeSeconds, int lates,
                                         int absences) {
        CarrierPayAttendance row = new CarrierPayAttendance();
        row.id = UUID.randomUUID();
        row.runId = runId;
        row.riderRef = riderRef;
        row.workedSeconds = workedSeconds;
        row.manualSeconds = manualSeconds;
        row.overtimeSeconds = overtimeSeconds;
        row.lates = lates;
        row.absences = absences;
        return row;
    }

    /** A rider the read listed whose figures could not be paid on: no figures, and why. */
    public static CarrierPayAttendance unreadable(UUID runId, String riderRef, String reason) {
        CarrierPayAttendance row = new CarrierPayAttendance();
        row.id = UUID.randomUUID();
        row.runId = runId;
        row.riderRef = riderRef;
        row.unavailableReason = reason;
        return row;
    }

    /** Whether this row carries figures. When false every figure is null and the reason says why. */
    public boolean isReadable() {
        return unavailableReason == null;
    }

    public UUID getId() {
        return id;
    }

    public UUID getRunId() {
        return runId;
    }

    public String getRiderRef() {
        return riderRef;
    }

    public Long getWorkedSeconds() {
        return workedSeconds;
    }

    public Long getManualSeconds() {
        return manualSeconds;
    }

    public Long getOvertimeSeconds() {
        return overtimeSeconds;
    }

    public Integer getLates() {
        return lates;
    }

    public Integer getAbsences() {
        return absences;
    }

    public String getUnavailableReason() {
        return unavailableReason;
    }
}
