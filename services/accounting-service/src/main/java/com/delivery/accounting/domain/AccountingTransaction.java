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
 * One leg of one order's settlement.
 *
 * <p>Its id is the idempotency key all the way to the bank's ledger, which is why it is assigned
 * here and never regenerated: a retried posting carries the same id, and the bank recognises it.
 */
@Entity
@Table(name = "transactions")
public class AccountingTransaction {

    /** Which part of a settlement this row is. */
    public enum Leg {
        /** The customer pays the order total, from a bank account. */
        CUSTOMER_DEBIT,
        /**
         * The customer paid in cash, at the door.
         *
         * <p>Not a movement between accounts — nobody's balance changed. It records that whoever
         * took the notes now owes them to the platform, and the matching {@link CashFloatEntry} is
         * what tracks that until they bank it. Never sent to the bank, which is the entire point:
         * asking a bank to post cash it never saw is what broke the first attempt at this.
         */
        CASH_COLLECTED,
        /** The merchant receives the total less commission. */
        MERCHANT_CREDIT,
        /**
         * The rider is paid for an errand.
         *
         * <p>On a Butler BUY this is a reimbursement for goods they bought with their own money
         * plus their share of the fee — not a bonus on top of somebody else's payout. Its own leg
         * rather than a merchant credit pointed at a rider, so a report can say who was paid and
         * why without decoding an account number.
         */
        RIDER_CREDIT,
        /**
         * The delivery company that carried it.
         *
         * <p>The delivery fee less the platform's take rate on it. Absent when the platform's own
         * riders carried the order, because the platform is not paid twice.
         */
        PROVIDER_CREDIT,
        /** The platform's cut. */
        PLATFORM_COMMISSION,
        /**
         * The platform paying into an order rather than taking out of it.
         *
         * <p>Free delivery on a small basket costs more than the commission it earns, so what the
         * platform keeps goes negative and the difference has to come from somewhere. That is the
         * offer working as intended — the platform is buying the order — but it is money leaving,
         * and it is posted rather than dropped so the books still balance.
         *
         * <p>Its own leg rather than a negative commission: amounts on this table are positive by
         * constraint, the direction says which way it went, and a report that must read the sign of
         * a "commission" to notice a loss is one nobody trusts.
         */
        PLATFORM_SUBSIDY,
        /**
         * Takings banked, clearing a cash holder's outstanding float.
         *
         * <p>This one <em>is</em> a real posting: handing over the day's notes genuinely moves
         * money into the platform's account. It belongs to no single order, which is why it carries
         * a synthetic order id — the remittance's own.
         */
        CASH_REMITTANCE,
        /** Compensation: money returned when a settlement could not be completed. */
        CUSTOMER_REFUND
    }

    public enum Direction { DEBIT, CREDIT }

    public enum Status {
        /** Created, not yet confirmed by the bank. */
        PENDING,
        /** The bank moved the money. */
        POSTED,
        /**
         * Discharged in cash, with no bank involved.
         *
         * <p>Distinct from POSTED on purpose. Both mean "this leg is done", but only one of them
         * means a bank can be asked to prove it — and reconciliation against a bank statement has
         * to know which rows it should expect to find there.
         */
        SETTLED_IN_CASH,
        /** The bank refused, or we gave up. Still recoverable by an operator. */
        FAILED,
        /** Was posted, then reversed because the rest of the settlement could not complete. */
        COMPENSATED,
        /** Never posted and never will be — the settlement was unwound around it. */
        ABANDONED
    }

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "order_id", nullable = false, updatable = false)
    private UUID orderId;

    @Enumerated(EnumType.STRING)
    @Column(name = "leg", nullable = false, updatable = false, length = 24)
    private Leg leg;

    @Column(name = "account_ref", nullable = false, length = 64)
    private String accountRef;

    @Column(name = "amount", nullable = false, precision = 12, scale = 2)
    private BigDecimal amount;

    @Column(name = "currency", nullable = false, length = 3)
    private String currency;

    @Enumerated(EnumType.STRING)
    @Column(name = "direction", nullable = false, length = 8)
    private Direction direction;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false, length = 16)
    private Status status = Status.PENDING;

    @Column(name = "core_banking_ref", length = 64)
    private String coreBankingRef;

    @Column(name = "failure_reason", columnDefinition = "text")
    private String failureReason;

    @Column(name = "attempts", nullable = false)
    private int attempts;

    @Column(name = "correlation_id", length = 64)
    private String correlationId;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    @Column(name = "posted_at")
    private Instant postedAt;

    /**
     * Whether this leg represents money moving between bank accounts.
     *
     * <p>False for a leg that records an obligation instead — cash taken at the door moves no
     * account anywhere, and asking the bank to post it is what made the first attempt at this fail:
     * every posting was refused for want of funds, because a rider holds notes and not a balance.
     * Such a leg is never sent, never waits, and never blocks the legs behind it.
     */
    @Column(name = "posting_required", nullable = false)
    private boolean postingRequired = true;

    protected AccountingTransaction() {
        // for JPA
    }

    public AccountingTransaction(UUID orderId, Leg leg, String accountRef, BigDecimal amount,
                                 String currency, Direction direction, String correlationId) {
        this.id = UUID.randomUUID();
        this.orderId = orderId;
        this.leg = leg;
        this.accountRef = accountRef;
        this.amount = amount;
        this.currency = currency;
        this.direction = direction;
        this.correlationId = correlationId;
        this.status = Status.PENDING;
        this.createdAt = Instant.now();
    }

    /**
     * A leg that records an obligation rather than a bank movement.
     *
     * <p>Marked SETTLED at birth: there is nothing to wait for, and leaving it PENDING would stall
     * every sequenced leg behind it on an answer the bank is never going to give.
     */
    public static AccountingTransaction obligation(UUID orderId, Leg leg, String accountRef,
                                                   BigDecimal amount, String currency,
                                                   Direction direction, String correlationId) {
        AccountingTransaction entry = new AccountingTransaction(
                orderId, leg, accountRef, amount, currency, direction, correlationId);
        entry.postingRequired = false;
        entry.status = Status.SETTLED_IN_CASH;
        entry.postedAt = Instant.now();
        return entry;
    }

    /**
     * Turns an already-built leg into one that records the obligation and asks no bank.
     *
     * <p>What {@code LEDGER_ONLY} settlement is made of. The platform runs cash-on-delivery and
     * pays merchants and riders in points rather than bank transfers, so every leg is discharged
     * outside any bank — the customer handed over notes, and what the platform owes from there is
     * a points balance, not a payment instruction.
     *
     * <p>A mutator rather than a second factory because the legs are built once, by rules that have
     * nothing to do with how they will be discharged. Duplicating that construction for two
     * settlement modes is how the two drift apart.
     *
     * <p>Reuses {@link Status#SETTLED_IN_CASH} rather than inventing a status: its whole purpose is
     * to mark a leg that is done and that no bank statement will ever show, which is exactly this.
     */
    public void recordWithoutBank() {
        this.postingRequired = false;
        this.status = Status.SETTLED_IN_CASH;
        this.postedAt = Instant.now();
    }

    public boolean isPostingRequired() {
        return postingRequired;
    }

    public void markPosted(String coreBankingRef) {
        this.status = Status.POSTED;
        this.coreBankingRef = coreBankingRef;
        this.postedAt = Instant.now();
        this.failureReason = null;
        this.attempts++;
    }

    public void markFailed(String reason) {
        this.status = Status.FAILED;
        this.failureReason = reason;
        this.attempts++;
    }

    /** Still in flight: the connector will retry, so this must not look like a terminal failure. */
    public void markRetrying(String reason) {
        this.status = Status.PENDING;
        this.failureReason = reason;
        this.attempts++;
    }

    public void markCompensated() {
        this.status = Status.COMPENSATED;
    }

    public void markAbandoned(String reason) {
        this.status = Status.ABANDONED;
        this.failureReason = reason;
    }

    public boolean isTerminal() {
        return status == Status.POSTED || status == Status.SETTLED_IN_CASH
                || status == Status.COMPENSATED || status == Status.ABANDONED;
    }

    /**
     * Done, and done successfully — however it was discharged.
     *
     * <p>Distinct from {@link #isTerminal()}, which also covers the unhappy endings. Cash counts
     * here: the obligation was met at the door, and a settlement whose collection leg is cash is
     * every bit as complete as one the bank confirmed.
     */
    public boolean isSettled() {
        return status == Status.POSTED || status == Status.SETTLED_IN_CASH;
    }

    public UUID getId() {
        return id;
    }

    public UUID getOrderId() {
        return orderId;
    }

    public Leg getLeg() {
        return leg;
    }

    public String getAccountRef() {
        return accountRef;
    }

    public BigDecimal getAmount() {
        return amount;
    }

    public String getCurrency() {
        return currency;
    }

    public Direction getDirection() {
        return direction;
    }

    public Status getStatus() {
        return status;
    }

    public String getCoreBankingRef() {
        return coreBankingRef;
    }

    public String getFailureReason() {
        return failureReason;
    }

    public int getAttempts() {
        return attempts;
    }

    public String getCorrelationId() {
        return correlationId;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public Instant getPostedAt() {
        return postedAt;
    }
}
