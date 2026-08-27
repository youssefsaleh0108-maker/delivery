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
 * One movement on one rider's money.
 *
 * <p>Signed, and always a row. A balance is a {@code SUM} over these — there is no balance column,
 * for the same reason {@link PointsEntry} has none: "why is my balance 41.20" has to be answerable,
 * and only the history answers it. This is also the number a rider will eventually dispute, and a
 * figure that cannot be broken down is a figure that cannot be defended.
 *
 * <p><strong>{@link PayableBy} is the column that matters.</strong> Not everything a rider earned
 * is something the platform owes them. A rider employed by a delivery company earned the job, but
 * the platform already paid their COMPANY for it; a cash tip was earned, but the rider is already
 * holding the notes. Both belong in the statement and neither belongs in the balance, and
 * conflating the two is how a platform pays for the same delivery twice.
 *
 * @see RiderCashOut
 */
@Entity
@Table(name = "rider_ledger")
public class RiderLedgerEntry {

    /** What produced this movement. */
    public enum EntryType {
        /** The rider's share of one delivered job. */
        JOB_EARNING,
        /**
         * A customer tip.
         *
         * <p>Never commissioned, and that is the whole point of it being its own type rather than
         * more {@code JOB_EARNING}. A tip is not the platform's revenue and no percentage of it is
         * ever taken; the commission arithmetic in {@code SettlementService} never sees it, because
         * a tip is not part of any order total.
         */
        TIP,
        /**
         * Money the rider fronted on an errand, handed back.
         *
         * <p>Not earnings. The rider paid for the goods and is made square, not better off, so a
         * statement that added it to "what I earned today" would flatter every Butler shift. Its
         * own type so it can be reported beside the earnings rather than inside them — and it is
         * still {@link PayableBy#PLATFORM}, because the platform genuinely owes it.
         */
        REIMBURSEMENT,
        /**
         * Taken out of the balance while a cash-out is open.
         *
         * <p>Negative, and written the moment the request is made rather than when it is paid. A
         * balance that still showed requested money would let the same money be requested again the
         * moment the first request was slow.
         */
        CASHOUT_HELD,
        /** A refused cash-out gives the held money back. */
        CASHOUT_RELEASED,
        /**
         * Records that the money was handed over.
         *
         * <p>Zero on purpose. The balance already fell when the hold was written; subtracting again
         * here would charge the rider twice for one payout. This row exists so the history shows
         * the payment.
         */
        CASHOUT_PAID,
        /** An operator correction, kept apart from anything the system did on its own. */
        ADJUSTMENT
    }

    /**
     * Who owes this money.
     *
     * <p>Only {@link #PLATFORM} counts toward what a rider can cash out. The other two exist so the
     * rider can see work they genuinely did without the platform offering to pay for it a second
     * time.
     */
    public enum PayableBy {
        /** The platform holds it and will hand it over on a cash-out. */
        PLATFORM,
        /**
         * The rider's employer owes it.
         *
         * <p>The platform paid the delivery company for the job. What the company passes on is
         * their employment contract, which the platform has never been shown — so this is shown and
         * never paid.
         */
        CARRIER,
        /** The rider already has the notes. A cash tip, handed over at the door. */
        IN_HAND
    }

    /**
     * Which fleet the rider was on for this job.
     *
     * <p>Stored per row rather than looked up per rider. A rider can move between the platform's
     * own fleet and a company's, and a statement that re-read today's employer would silently
     * restate what they were owed for work they did last month.
     */
    public enum Fleet {
        /** The platform's own riders. The platform pays them directly. */
        PLATFORM,
        /** A delivery company's rider. The company pays them. */
        CARRIER
    }

    @Id
    private UUID id;

    @Column(name = "rider_ref", nullable = false, updatable = false, length = 64)
    private String riderRef;

    /** Null on a cash-out movement, which belongs to no single job. */
    @Column(name = "order_id", updatable = false)
    private UUID orderId;

    @Enumerated(EnumType.STRING)
    @Column(name = "entry_type", nullable = false, updatable = false, length = 24)
    private EntryType entryType;

    @Column(name = "amount", nullable = false, updatable = false, precision = 12, scale = 2)
    private BigDecimal amount;

    @Column(name = "currency", nullable = false, updatable = false, length = 3)
    private String currency;

    @Enumerated(EnumType.STRING)
    @Column(name = "payable_by", nullable = false, updatable = false, length = 16)
    private PayableBy payableBy;

    @Enumerated(EnumType.STRING)
    @Column(name = "fleet", nullable = false, updatable = false, length = 16)
    private Fleet fleet;

    @Column(name = "carrier_ref", updatable = false, length = 64)
    private String carrierRef;

    /**
     * Who paid for the order, on a job earning.
     *
     * <p>The only fact this service holds that can prove the person adding a tip is the person the
     * rider delivered to. Without it the tip endpoint would authorise on role alone and any
     * customer could tip any order. Null on every other kind of row.
     */
    @Column(name = "customer_ref", updatable = false, length = 64)
    private String customerRef;

    @Column(name = "cash_out_id", updatable = false)
    private UUID cashOutId;

    @Column(name = "earned_at", nullable = false, updatable = false)
    private Instant earnedAt;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    protected RiderLedgerEntry() {
        // for JPA
    }

    private RiderLedgerEntry(String riderRef, EntryType entryType, BigDecimal amount,
                             String currency, PayableBy payableBy, Fleet fleet) {
        this.id = UUID.randomUUID();
        this.riderRef = riderRef;
        this.entryType = entryType;
        this.amount = amount;
        this.currency = currency;
        this.payableBy = payableBy;
        this.fleet = fleet;
        this.createdAt = Instant.now();
        this.earnedAt = this.createdAt;
    }

    /**
     * What a rider earned for carrying one order.
     *
     * <p>{@code earnedAt} is the moment the order was DELIVERED, not the moment this row was
     * written. The bus is at-least-once and can be slow; an event that arrives an hour late must
     * still land in the day the rider worked, or their Monday total changes on Tuesday.
     */
    public static RiderLedgerEntry jobEarning(String riderRef, UUID orderId, BigDecimal amount,
                                              String currency, Fleet fleet, String carrierRef,
                                              String customerRef, Instant earnedAt) {
        // A carrier's rider is owed by their carrier, not by the platform: the platform has already
        // paid the company for this delivery through PROVIDER_CREDIT. Deriving the liability from
        // the fleet rather than taking it as a parameter means no caller can get the pair wrong.
        PayableBy payableBy = fleet == Fleet.CARRIER ? PayableBy.CARRIER : PayableBy.PLATFORM;
        RiderLedgerEntry entry = new RiderLedgerEntry(
                riderRef, EntryType.JOB_EARNING, amount, currency, payableBy, fleet);
        entry.orderId = orderId;
        entry.carrierRef = carrierRef;
        entry.customerRef = customerRef;
        entry.earnedAt = earnedAt != null ? earnedAt : entry.createdAt;
        return entry;
    }

    /**
     * Goods the rider bought with their own money on an errand, handed back.
     *
     * <p>Always the platform's debt whatever fleet the rider is on: the rider fronted the money to
     * the PLATFORM's customer on the PLATFORM's instruction, and a delivery company that never saw
     * that transaction cannot be asked to refund it.
     */
    public static RiderLedgerEntry reimbursement(String riderRef, UUID orderId, BigDecimal amount,
                                                 String currency, Fleet fleet, String carrierRef,
                                                 Instant earnedAt) {
        RiderLedgerEntry entry = new RiderLedgerEntry(riderRef, EntryType.REIMBURSEMENT, amount,
                currency, PayableBy.PLATFORM, fleet);
        entry.orderId = orderId;
        entry.carrierRef = carrierRef;
        entry.earnedAt = earnedAt != null ? earnedAt : entry.createdAt;
        return entry;
    }

    /**
     * A customer tip on a delivered order.
     *
     * <p>The tip belongs to the RIDER even when a company employed them: the customer tipped the
     * person who turned up, not their employer, and routing it through the company would be the
     * platform deciding to give somebody else's money away.
     *
     * <p>{@code inHand} says the customer handed over notes at the door. That is earned and shown,
     * but never payable — the rider already has it, and crediting the balance too would pay it a
     * second time.
     */
    public static RiderLedgerEntry tip(String riderRef, UUID orderId, BigDecimal amount,
                                       String currency, Fleet fleet, String carrierRef,
                                       boolean inHand, Instant earnedAt) {
        RiderLedgerEntry entry = new RiderLedgerEntry(riderRef, EntryType.TIP, amount, currency,
                inHand ? PayableBy.IN_HAND : PayableBy.PLATFORM, fleet);
        entry.orderId = orderId;
        entry.carrierRef = carrierRef;
        entry.earnedAt = earnedAt != null ? earnedAt : entry.createdAt;
        return entry;
    }

    /** Takes money out of the balance while a cash-out is open. Negative. */
    public static RiderLedgerEntry cashOutHeld(String riderRef, UUID cashOutId, BigDecimal amount,
                                               String currency) {
        RiderLedgerEntry entry = new RiderLedgerEntry(riderRef, EntryType.CASHOUT_HELD,
                amount.abs().negate(), currency, PayableBy.PLATFORM, Fleet.PLATFORM);
        entry.cashOutId = cashOutId;
        return entry;
    }

    /** Gives held money back when a cash-out is refused. */
    public static RiderLedgerEntry cashOutReleased(String riderRef, UUID cashOutId,
                                                   BigDecimal amount, String currency) {
        RiderLedgerEntry entry = new RiderLedgerEntry(riderRef, EntryType.CASHOUT_RELEASED,
                amount.abs(), currency, PayableBy.PLATFORM, Fleet.PLATFORM);
        entry.cashOutId = cashOutId;
        return entry;
    }

    /**
     * Records that a cash-out was paid.
     *
     * <p>Zero, deliberately. The balance fell when the hold was written and taking it again would
     * charge the rider twice for one payout.
     */
    public static RiderLedgerEntry cashOutPaid(String riderRef, UUID cashOutId, String currency) {
        RiderLedgerEntry entry = new RiderLedgerEntry(riderRef, EntryType.CASHOUT_PAID,
                BigDecimal.ZERO.setScale(2), currency, PayableBy.PLATFORM, Fleet.PLATFORM);
        entry.cashOutId = cashOutId;
        return entry;
    }

    /**
     * Does this row count toward what the rider can actually ask for?
     *
     * <p>Kept on the entity beside the enum it reads rather than only in the repository query, so
     * an in-memory total and a database total cannot answer the question differently.
     */
    public boolean isPayableByPlatform() {
        return payableBy == PayableBy.PLATFORM;
    }

    /** Money the rider earned, as opposed to money handed back to them or moved by a cash-out. */
    public boolean isEarning() {
        return entryType == EntryType.JOB_EARNING || entryType == EntryType.TIP;
    }

    public UUID getId() {
        return id;
    }

    public String getRiderRef() {
        return riderRef;
    }

    public UUID getOrderId() {
        return orderId;
    }

    public EntryType getEntryType() {
        return entryType;
    }

    public BigDecimal getAmount() {
        return amount;
    }

    public String getCurrency() {
        return currency;
    }

    public PayableBy getPayableBy() {
        return payableBy;
    }

    public Fleet getFleet() {
        return fleet;
    }

    public String getCarrierRef() {
        return carrierRef;
    }

    public String getCustomerRef() {
        return customerRef;
    }

    public UUID getCashOutId() {
        return cashOutId;
    }

    public Instant getEarnedAt() {
        return earnedAt;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }
}
