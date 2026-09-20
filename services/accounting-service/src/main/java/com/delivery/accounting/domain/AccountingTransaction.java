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
         * What wrapping a gift added to the order, paid to the shop that wrapped it.
         *
         * <p>Its own leg rather than more {@link #MERCHANT_CREDIT}: commission is taken on the goods
         * and never on the wrap, and a statement has to be able to say which is which. Never left in
         * the platform's residue either, where it was posted as {@link #PLATFORM_COMMISSION} —
         * commission reported as earned on work the shop did.
         */
        GIFT_WRAP_CREDIT,
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
        /**
         * Money the platform handed over: a points redemption paid, a rider's cash-out paid.
         *
         * <p>A DEBIT against the party that was paid, because that is what reduces what the
         * platform owes them — and what their statement has to show, or it keeps asking for money
         * that has already been sent. It belongs to no single order and carries the payout's own
         * id, as {@link #CASH_REMITTANCE} carries the remittance's, so the unique {@code (order_id,
         * leg)} is what stops one redemption being recorded twice.
         *
         * <p>Never part of an order's arithmetic: the checks that an order's debits equal its
         * credits exclude it for the same reason they exclude a remittance.
         */
        PAYOUT,
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

    /**
     * Which sort of party this leg is about. Null on a leg written before attribution existed, and
     * on {@link Leg#CUSTOMER_DEBIT}, which has no counterparty in this model.
     *
     * @see #attributedTo(CounterpartyKind, String)
     */
    @Enumerated(EnumType.STRING)
    @Column(name = "counterparty_kind", length = 16)
    private CounterpartyKind counterpartyKind;

    /** The party's own identifier. A Keycloak subject, a provider id, or the platform constant. */
    @Column(name = "counterparty_ref", length = 64)
    private String counterpartyRef;

    @Column(name = "amount", nullable = false, precision = 12, scale = 2)
    private BigDecimal amount;

    /**
     * What the platform charged the payee of this leg, out of what they sold or carried (V54).
     *
     * <p>The goods commission on a {@link Leg#MERCHANT_CREDIT}, the delivery cut on a
     * {@link Leg#PROVIDER_CREDIT} or {@link Leg#RIDER_CREDIT}, and zero where a waiver meant
     * nothing was charged. Null on a leg that pays nobody, and on every leg written before V54.
     *
     * <p><strong>Beside the arithmetic, never inside it.</strong> The legs sum to the order total
     * on their own and this changes none of them; it exists because the platform's own leg is a
     * RESIDUE — commission plus the express premium, less any promotion — and a statement that
     * reads a residue cannot say what a shop was charged. Recorded at settlement, where the figure
     * is known exactly, rather than re-derived later from a rate that may since have changed.
     */
    @Column(name = "commission_amount", precision = 12, scale = 2)
    private BigDecimal commissionAmount;

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
     * Money the platform has already handed over, recorded after the fact (RECON-11).
     *
     * <p>Terminal as it is written, for the reason a cash collection is: nothing is waiting on a
     * bank. An operator pays a redemption or a cash-out outside this system and records that they
     * did — see {@code PointsService.markPaid} and {@code RiderEarningsService.payCashOut} — so by
     * the time this row exists the money has moved, and asking a connector to move it again is the
     * one thing that must not happen.
     *
     * <p>Booked against the PLATFORM's account, which is the account it left. Who received it is
     * the counterparty on the leg, not an account number this service has never been told.
     */
    public static AccountingTransaction paidOut(UUID payoutId, String platformAccount,
                                                BigDecimal amount, String currency,
                                                String correlationId) {
        return obligation(payoutId, Leg.PAYOUT, platformAccount, amount, currency,
                Direction.DEBIT, correlationId);
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

    /**
     * Records WHO this leg is about, alongside the account it would post to.
     *
     * <p>Deliberately separate from {@code accountRef}, which is left exactly as it was. That field
     * is what a bank posting would use and it is an omnibus bucket today — every merchant credit in
     * the database points at one account, and every genuinely onboarded merchant resolves to
     * {@code ACC-UNMAPPED}. Both are correct as postings and neither can say which shop sold the
     * goods. Changing account_ref to fix that would break the thing it is right about in order to
     * fix the thing it was never for.
     *
     * <p><strong>Both or neither.</strong> A null ref leaves the kind null too, which is what makes
     * "we could not attribute this" a single, queryable state rather than two half-populated rows
     * that a statement query skips and a reconciliation total counts. A leg whose party the event
     * did not name is honestly unattributed, and the counterparties listing reports it as such.
     *
     * @return this, so it can be chained where the leg is constructed
     */
    public AccountingTransaction attributedTo(CounterpartyKind kind, String ref) {
        if (kind == null || ref == null || ref.isBlank()) {
            this.counterpartyKind = null;
            this.counterpartyRef = null;
            return this;
        }
        this.counterpartyKind = kind;
        this.counterpartyRef = ref;
        return this;
    }

    /**
     * Records what the platform charged this leg's payee (V54, RECON-05).
     *
     * <p>Zero is a real answer — a waived commission is "we charged nothing", which is not the same
     * as the null that means "this leg was written before anybody wrote the figure down".
     *
     * @return this, so it can be chained where the leg is constructed
     */
    public AccountingTransaction commissionCharged(BigDecimal amount) {
        this.commissionAmount = amount == null
                ? null
                : amount.setScale(2, java.math.RoundingMode.HALF_UP);
        return this;
    }

    /** What the platform charged this leg's payee, or null when the leg does not say. */
    public BigDecimal getCommissionAmount() {
        return commissionAmount;
    }

    public CounterpartyKind getCounterpartyKind() {
        return counterpartyKind;
    }

    public String getCounterpartyRef() {
        return counterpartyRef;
    }

    /** Whether this leg can be assigned to somebody. False for every row written before V47. */
    public boolean isAttributed() {
        return counterpartyKind != null;
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
