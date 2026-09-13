package com.delivery.accounting.domain;

import java.time.Instant;
import java.time.LocalDate;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * One delivery company's payroll for one pay period.
 *
 * <p>DRAFT, then APPROVED, then PAID, and only forward. A draft is recomputed as often as the company
 * likes; approving freezes its payslips for good — a mistake found afterwards is an adjustment paid
 * in a later run, never an edit, because a payslip a rider has been shown must still read the same
 * when they ask about it. The transitions throw rather than quietly doing nothing, so a code path
 * that tries to change an approved run fails loudly in a test instead of drifting in production.
 */
@Entity
@Table(name = "carrier_pay_run")
public class CarrierPayRun {

    public enum Status {
        /** Computed and recomputable. Nothing about it is final. */
        DRAFT,
        /** Figures frozen; payments are being recorded. */
        APPROVED,
        /** Every payslip due has a recorded payment. */
        PAID
    }

    /** Whether attendance hours are in this run's figures. */
    public enum Attendance {
        /** The policy pays nothing by the hour and deducts nothing for lateness: never read. */
        NOT_NEEDED,
        /** Read from order-tracking and used. */
        INCLUDED,
        /**
         * The policy needs attendance and it could not be read. The figures leave hours out, the run
         * says so, and approving it has to acknowledge it.
         */
        UNAVAILABLE
    }

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "carrier_ref", nullable = false, updatable = false, length = 64)
    private String carrierRef;

    @Column(name = "period_from", nullable = false, updatable = false)
    private LocalDate periodFrom;

    @Column(name = "period_to", nullable = false, updatable = false)
    private LocalDate periodTo;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false, length = 16)
    private Status status;

    @Column(name = "policy_id", nullable = false)
    private UUID policyId;

    @Column(name = "currency", nullable = false, updatable = false, length = 3)
    private String currency;

    @Enumerated(EnumType.STRING)
    @Column(name = "attendance", nullable = false, length = 16)
    private Attendance attendance;

    @Column(name = "attendance_note", length = 200)
    private String attendanceNote;

    /** When the run's hours were read, or their read was tried. Null when none were needed. */
    @Column(name = "attendance_at")
    private Instant attendanceAt;

    @Column(name = "revision", nullable = false)
    private int revision;

    @Column(name = "computed_at", nullable = false)
    private Instant computedAt;

    @Column(name = "created_by", nullable = false, updatable = false, length = 64)
    private String createdBy;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    @Column(name = "approved_by", length = 64)
    private String approvedBy;

    @Column(name = "approved_at")
    private Instant approvedAt;

    @Column(name = "paid_at")
    private Instant paidAt;

    protected CarrierPayRun() {
        // for JPA
    }

    /** A new draft, not yet computed: {@link #recomputed} gives it its first revision. */
    public static CarrierPayRun draft(String carrierRef, LocalDate from, LocalDate to, UUID policyId,
                                      String currency, String createdBy, Instant now) {
        CarrierPayRun run = new CarrierPayRun();
        run.id = UUID.randomUUID();
        run.carrierRef = carrierRef;
        run.periodFrom = from;
        run.periodTo = to;
        run.status = Status.DRAFT;
        run.policyId = policyId;
        run.currency = currency;
        run.attendance = Attendance.NOT_NEEDED;
        run.revision = 0;
        run.computedAt = now;
        run.createdBy = createdBy;
        run.createdAt = now;
        return run;
    }

    /**
     * The draft's figures were computed again, under {@code policyId}, with hours read at
     * {@code attendanceAt}.
     */
    public void recomputed(UUID policyId, Attendance attendance, String attendanceNote,
                           Instant attendanceAt, Instant at) {
        requireDraft();
        this.policyId = policyId;
        this.attendance = attendance;
        this.attendanceNote = attendanceNote;
        this.attendanceAt = attendanceAt;
        this.revision++;
        this.computedAt = at;
    }

    public void approve(String by, Instant at) {
        requireDraft();
        this.status = Status.APPROVED;
        this.approvedBy = by;
        this.approvedAt = at;
    }

    /** Every payslip due has a recorded payment. */
    public void paid(Instant at) {
        if (status != Status.APPROVED) {
            throw new IllegalStateException("Only an approved pay run can become paid");
        }
        this.status = Status.PAID;
        this.paidAt = at;
    }

    public boolean isDraft() {
        return status == Status.DRAFT;
    }

    private void requireDraft() {
        if (status != Status.DRAFT) {
            throw new IllegalStateException("An approved pay run is never changed; add an adjustment");
        }
    }

    public UUID getId() {
        return id;
    }

    public String getCarrierRef() {
        return carrierRef;
    }

    public LocalDate getPeriodFrom() {
        return periodFrom;
    }

    public LocalDate getPeriodTo() {
        return periodTo;
    }

    public Status getStatus() {
        return status;
    }

    public UUID getPolicyId() {
        return policyId;
    }

    public String getCurrency() {
        return currency;
    }

    public Attendance getAttendance() {
        return attendance;
    }

    public String getAttendanceNote() {
        return attendanceNote;
    }

    public Instant getAttendanceAt() {
        return attendanceAt;
    }

    public int getRevision() {
        return revision;
    }

    public Instant getComputedAt() {
        return computedAt;
    }

    public String getCreatedBy() {
        return createdBy;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public String getApprovedBy() {
        return approvedBy;
    }

    public Instant getApprovedAt() {
        return approvedAt;
    }

    public Instant getPaidAt() {
        return paidAt;
    }
}
