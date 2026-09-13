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

    @Column(name = "worked_seconds", nullable = false, updatable = false)
    private long workedSeconds;

    @Column(name = "manual_seconds", nullable = false, updatable = false)
    private long manualSeconds;

    @Column(name = "overtime_seconds", nullable = false, updatable = false)
    private long overtimeSeconds;

    @Column(name = "lates", nullable = false, updatable = false)
    private int lates;

    @Column(name = "absences", nullable = false, updatable = false)
    private int absences;

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

    public UUID getId() {
        return id;
    }

    public UUID getRunId() {
        return runId;
    }

    public String getRiderRef() {
        return riderRef;
    }

    public long getWorkedSeconds() {
        return workedSeconds;
    }

    public long getManualSeconds() {
        return manualSeconds;
    }

    public long getOvertimeSeconds() {
        return overtimeSeconds;
    }

    public int getLates() {
        return lates;
    }

    public int getAbsences() {
        return absences;
    }
}
