package com.delivery.accounting.domain;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.UUID;

import com.delivery.accounting.domain.PointsEntry.OwnerKind;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * A request to turn points into money.
 *
 * <p><strong>Nothing here moves money.</strong> The platform pays these by hand — an operator
 * approves, hands over cash or makes a transfer outside this system, and records that they did.
 * Modelling it as a request-and-decision rather than an automatic payout is the honest shape while
 * there is no payment integration, and it is also what a finance function would want anyway.
 */
@Entity
@Table(name = "points_redemption")
public class PointsRedemption {

    public enum Status {
        /** Requested, points held, waiting on Backoffice. */
        PENDING,
        /**
         * Approved, money not yet handed over.
         *
         * <p>A real state rather than a step on the way to PAID. Approval is a decision and payment
         * is an errand; collapsing them loses track of what the platform owes right now, which is
         * the one number a finance function asks for.
         */
        APPROVED,
        /** Money handed over. Terminal. */
        PAID,
        /** Refused. The held points go back. */
        REJECTED,
        /** Withdrawn before a decision. The held points go back. */
        CANCELLED
    }

    @Id
    private UUID id;

    @Enumerated(EnumType.STRING)
    @Column(name = "owner_kind", nullable = false, length = 16)
    private OwnerKind ownerKind;

    @Column(name = "owner_ref", nullable = false, length = 64)
    private String ownerRef;

    @Column(name = "points", nullable = false)
    private long points;

    /**
     * What those points were worth when the request was made.
     *
     * <p>Captured at request time, not at payout. The rate is a setting somebody can change, and a
     * change between request and approval would otherwise pay a different number from the one the
     * requester saw — a cheap way to lose trust.
     */
    @Column(name = "amount", nullable = false, precision = 12, scale = 2)
    private BigDecimal amount;

    @Column(name = "currency", nullable = false, length = 3)
    private String currency;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false, length = 16)
    private Status status;

    @Column(name = "payout_note")
    private String payoutNote;

    @Column(name = "requested_by", nullable = false, length = 64)
    private String requestedBy;

    @Column(name = "requested_at", nullable = false)
    private Instant requestedAt;

    @Column(name = "decided_by", length = 64)
    private String decidedBy;

    @Column(name = "decided_at")
    private Instant decidedAt;

    @Column(name = "decision_note")
    private String decisionNote;

    protected PointsRedemption() {
    }

    public PointsRedemption(OwnerKind ownerKind, String ownerRef, long points, BigDecimal amount,
                            String currency, String payoutNote, String requestedBy) {
        this.id = UUID.randomUUID();
        this.ownerKind = ownerKind;
        this.ownerRef = ownerRef;
        this.points = points;
        this.amount = amount;
        this.currency = currency;
        this.payoutNote = payoutNote;
        this.requestedBy = requestedBy;
        this.status = Status.PENDING;
        this.requestedAt = Instant.now();
    }

    /** True while the points are still held — the states that keep the balance reduced. */
    public boolean isOpen() {
        return status == Status.PENDING || status == Status.APPROVED;
    }

    public void approve(String by, String note) {
        requireStatus(Status.PENDING, "approve");
        this.status = Status.APPROVED;
        decide(by, note);
    }

    public void reject(String by, String note) {
        requireStatus(Status.PENDING, "reject");
        this.status = Status.REJECTED;
        decide(by, note);
    }

    /**
     * Records that the money was handed over.
     *
     * <p>Only from APPROVED. Paying something nobody approved is the transition worth making
     * impossible here rather than catching in a review later.
     */
    public void markPaid(String by, String reference) {
        requireStatus(Status.APPROVED, "pay");
        this.status = Status.PAID;
        decide(by, reference);
    }

    public void cancel(String by) {
        requireStatus(Status.PENDING, "cancel");
        this.status = Status.CANCELLED;
        decide(by, "withdrawn by the requester");
    }

    private void decide(String by, String note) {
        this.decidedBy = by;
        this.decidedAt = Instant.now();
        this.decisionNote = note;
    }

    private void requireStatus(Status required, String action) {
        if (this.status != required) {
            throw new IllegalStateException(
                    "Cannot " + action + " a redemption that is " + this.status);
        }
    }

    public UUID getId() {
        return id;
    }

    public OwnerKind getOwnerKind() {
        return ownerKind;
    }

    public String getOwnerRef() {
        return ownerRef;
    }

    public long getPoints() {
        return points;
    }

    public BigDecimal getAmount() {
        return amount;
    }

    public String getCurrency() {
        return currency;
    }

    public Status getStatus() {
        return status;
    }

    public String getPayoutNote() {
        return payoutNote;
    }

    public String getRequestedBy() {
        return requestedBy;
    }

    public Instant getRequestedAt() {
        return requestedAt;
    }

    public String getDecidedBy() {
        return decidedBy;
    }

    public Instant getDecidedAt() {
        return decidedAt;
    }

    public String getDecisionNote() {
        return decisionNote;
    }
}
