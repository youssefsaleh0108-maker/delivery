package com.delivery.accounting.domain;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * A rider asking for their balance in money.
 *
 * <p><strong>Nothing here moves money on its own.</strong> A payout is performed by whatever
 * {@code RiderPayoutProvider} is configured, and the only one that exists today is the manual one:
 * an operator pays outside this system and records that they did. Modelling it as a request and a
 * decision rather than as an automatic transfer is the honest shape while there is no payment
 * processor, and it is what a finance function would want in any case.
 *
 * <p>{@code REQUESTED -> PAID | REJECTED}, and nothing else. Deliberately shorter than
 * {@link PointsRedemption}, which carries a separate {@code APPROVED} state because a merchant
 * redemption is reviewed before anybody is paid. A rider cash-out is the rider asking for money
 * they have already earned, so an extra state on that path is a queue that serves nobody.
 */
@Entity
@Table(name = "rider_cash_out")
public class RiderCashOut {

    public enum Status {
        /** Asked for, money held out of the balance, waiting on a payout. */
        REQUESTED,
        /** Handed over. Terminal. */
        PAID,
        /** Refused. The held money goes back. Terminal. */
        REJECTED
    }

    @Id
    private UUID id;

    @Column(name = "rider_ref", nullable = false, updatable = false, length = 64)
    private String riderRef;

    @Column(name = "amount", nullable = false, updatable = false, precision = 12, scale = 2)
    private BigDecimal amount;

    @Column(name = "currency", nullable = false, updatable = false, length = 3)
    private String currency;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false, length = 16)
    private Status status;

    /**
     * Free text from the rider: which wallet, which account, who to hand it to.
     *
     * <p>Never a bank account number. The account a rider is paid into lives on their profile and
     * is read by the payout provider at the moment of payment; copying it here would put it in the
     * response of every statement query that returns a cash-out.
     */
    @Column(name = "payout_note")
    private String payoutNote;

    @Column(name = "requested_at", nullable = false, updatable = false)
    private Instant requestedAt;

    @Column(name = "decided_by", length = 64)
    private String decidedBy;

    @Column(name = "decided_at")
    private Instant decidedAt;

    @Column(name = "decision_note")
    private String decisionNote;

    /** What the payout provider called it. The number quoted in a dispute. */
    @Column(name = "payment_ref", length = 64)
    private String paymentRef;

    /**
     * Which provider paid it.
     *
     * <p>Recorded so a row can never be mistaken for a real payment when it was the dev path that
     * "paid" it. A PAID row with {@code paid_via = 'MANUAL'} means a human says they handed money
     * over; a PAID row with no provider named at all would mean nothing at all.
     */
    @Column(name = "paid_via", length = 32)
    private String paidVia;

    protected RiderCashOut() {
        // for JPA
    }

    public RiderCashOut(String riderRef, BigDecimal amount, String currency, String payoutNote) {
        this.id = UUID.randomUUID();
        this.riderRef = riderRef;
        this.amount = amount;
        this.currency = currency;
        this.payoutNote = payoutNote;
        this.status = Status.REQUESTED;
        this.requestedAt = Instant.now();
    }

    /** True while the money is still held out of the balance. */
    public boolean isOpen() {
        return status == Status.REQUESTED;
    }

    /**
     * Records that the money was handed over.
     *
     * <p>Only from REQUESTED, so a second payment against an already-paid request is impossible
     * rather than caught in a review later — this is the transition that costs real money when it
     * fires twice.
     */
    public void markPaid(String by, String paidVia, String paymentRef) {
        requireStatus(Status.REQUESTED, "pay");
        this.status = Status.PAID;
        this.paidVia = paidVia;
        this.paymentRef = paymentRef;
        decide(by, paymentRef);
    }

    /** Refuses the request. The caller must give the held money back. */
    public void reject(String by, String note) {
        requireStatus(Status.REQUESTED, "reject");
        this.status = Status.REJECTED;
        decide(by, note);
    }

    private void decide(String by, String note) {
        this.decidedBy = by;
        this.decidedAt = Instant.now();
        this.decisionNote = note;
    }

    private void requireStatus(Status required, String action) {
        if (this.status != required) {
            throw new IllegalStateException(
                    "Cannot " + action + " a cash-out that is " + this.status);
        }
    }

    public UUID getId() {
        return id;
    }

    public String getRiderRef() {
        return riderRef;
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

    public String getPaymentRef() {
        return paymentRef;
    }

    public String getPaidVia() {
        return paidVia;
    }
}
