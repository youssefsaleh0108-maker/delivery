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
 * Cash somebody is physically holding on the platform's behalf.
 *
 * <p>This is a record of custody, not of a bank movement. When a rider takes notes at the door no
 * account anywhere changes — but an obligation is created, and it is real enough that the platform
 * pays the merchant against it. Recording that obligation is what stops the ledger claiming a
 * customer's bank account was debited when it never was.
 *
 * <p>An outstanding balance is the sum of {@code COLLECTED} rows with no {@code clearedBy}. Kept as
 * append-only rows rather than a mutable balance column: a balance that disagrees with its history
 * cannot be argued with, and this is the number a rider will eventually dispute.
 *
 * <h2>Delivery companies</h2>
 * <p>A delivery company's rider owes the door cash to their COMPANY, not to the platform, and the
 * company then owes the platform (V50). That is three rows here rather than a new table: the rider's
 * {@code COLLECTED} row carries the company in {@link #getCarrierRef()}; a {@code TRANSFERRED} row
 * records the rider handing it over and clears those rows; and one custody copy per order —
 * {@code COLLECTED}, held by the {@code PROVIDER}, pointing at the transfer through
 * {@link #getHandoverId()} — is what the company now owes. The platform's own riders never produce
 * the last two and read exactly as they did.
 */
@Entity
@Table(name = "cash_float")
public class CashFloatEntry {

    public enum Kind {
        /**
         * Notes taken from a customer — or, on a company's custody copy, the same notes after its
         * rider handed them over. Creates the obligation either way.
         */
        COLLECTED,
        /** Takings banked with the platform. Discharges some or all of it. */
        REMITTED,
        /**
         * A delivery company's rider handing the cash to their company.
         *
         * <p>Discharges the rider's rows the way {@link #REMITTED} does, but the money has not
         * reached the platform: it moved to the company, whose custody copies say so. Its own kind
         * rather than a REMITTED row with a flag, because "banked" is exactly the claim this must
         * never be mistaken for — a platform statement that counted it would report cash as arrived
         * that is still in a hub's safe.
         */
        TRANSFERRED,
        /** Written off by an operator — theft, loss, a dispute settled the other way. */
        WRITTEN_OFF
    }

    /**
     * Who holds it.
     *
     * <p>{@code PROVIDER} is the delivery company, once its rider has handed the cash over. It was
     * here from the start for exactly that, because adding a discriminator to a table that already
     * has rows means deciding what every existing row meant; it maps to
     * {@code CounterpartyKind.CARRIER} on the ledger.
     */
    public enum HolderKind { RIDER, PROVIDER }

    /**
     * How a hand-over or a remittance was made. Recorded, never acted on: nothing in this service
     * moves money because of it.
     */
    public enum Method {
        /** Notes across a counter. */
        CASH,
        /** Paid into a bank account and the slip shown. */
        BANK_DEPOSIT,
        /** A money-transfer or wallet app. */
        WALLET;

        /** Parses a request value case-insensitively; null for anything that is not one. */
        public static Method parse(String value) {
            if (value == null || value.isBlank()) {
                return null;
            }
            for (Method method : values()) {
                if (method.name().equalsIgnoreCase(value.trim())) {
                    return method;
                }
            }
            return null;
        }
    }

    /**
     * Who recorded a hand-over or a remittance, how, and the key that makes a double submit
     * harmless.
     *
     * @param by         the recorder's Keycloak subject. Never a name typed into a form
     * @param method     how the money moved; null when the caller did not say
     * @param note       free text, already trimmed and bounded by the caller
     * @param requestKey the client's idempotency key, or null
     */
    public record Recorded(String by, Method method, String note, String requestKey) {

        /** Nothing known — the shape of every remittance recorded before V50. */
        public static Recorded nobody() {
            return new Recorded(null, null, null, null);
        }
    }

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "holder_ref", nullable = false, updatable = false, length = 64)
    private String holderRef;

    @Enumerated(EnumType.STRING)
    @Column(name = "holder_kind", nullable = false, updatable = false, length = 16)
    private HolderKind holderKind;

    /** Null on a remittance or a transfer, which settle many orders at once. */
    @Column(name = "order_id", updatable = false)
    private UUID orderId;

    @Column(name = "amount", nullable = false, updatable = false, precision = 12, scale = 2)
    private BigDecimal amount;

    @Column(name = "currency", nullable = false, updatable = false, length = 3)
    private String currency;

    @Enumerated(EnumType.STRING)
    @Column(name = "entry_kind", nullable = false, updatable = false, length = 16)
    private Kind entryKind;

    @Column(name = "cleared_by")
    private UUID clearedBy;

    /**
     * The delivery company this cash belongs to, or null on the platform's own fleet. Decided when
     * the cash was collected and never re-read: a rider who changes fleet leaves old cash with the
     * old company.
     */
    @Column(name = "carrier_ref", updatable = false, length = 64)
    private String carrierRef;

    /** On a company's custody copy, the transfer that created it. Null everywhere else. */
    @Column(name = "handover_id", updatable = false)
    private UUID handoverId;

    @Column(name = "recorded_by", updatable = false, length = 64)
    private String recordedBy;

    @Enumerated(EnumType.STRING)
    @Column(name = "method", updatable = false, length = 24)
    private Method method;

    @Column(name = "note", updatable = false, columnDefinition = "text")
    private String note;

    @Column(name = "request_key", updatable = false, length = 64)
    private String requestKey;

    @Column(name = "created_at", nullable = false, insertable = false, updatable = false)
    private Instant createdAt;

    protected CashFloatEntry() {
        // for JPA
    }

    private CashFloatEntry(String holderRef, HolderKind holderKind, UUID orderId,
                           BigDecimal amount, String currency, Kind entryKind,
                           String carrierRef) {
        this.id = UUID.randomUUID();
        this.holderRef = holderRef;
        this.holderKind = holderKind;
        this.orderId = orderId;
        this.amount = amount;
        this.currency = currency;
        this.entryKind = entryKind;
        // A company's own rows always name the company: see chk_float_provider_carrier.
        this.carrierRef = holderKind == HolderKind.PROVIDER ? holderRef : carrierRef;
    }

    /** Notes taken at the door for one order, on the platform's own fleet. */
    public static CashFloatEntry collected(String holderRef, HolderKind holderKind, UUID orderId,
                                           BigDecimal amount, String currency) {
        return collected(holderRef, holderKind, orderId, amount, currency, null);
    }

    /**
     * Notes taken at the door for one order.
     *
     * @param carrierRef the delivery company the job was carried for, or null on the platform's own
     *                   fleet — which is what decides whether the rider owes the company or the
     *                   platform
     */
    public static CashFloatEntry collected(String holderRef, HolderKind holderKind, UUID orderId,
                                           BigDecimal amount, String currency, String carrierRef) {
        return new CashFloatEntry(holderRef, holderKind, orderId, amount, currency, Kind.COLLECTED,
                carrierRef);
    }

    /** Takings banked. Belongs to no single order, which is why {@code orderId} is null. */
    public static CashFloatEntry remitted(String holderRef, HolderKind holderKind,
                                          BigDecimal amount, String currency) {
        return remitted(holderRef, holderKind, amount, currency, Recorded.nobody());
    }

    /** Takings banked, with who recorded it and how. */
    public static CashFloatEntry remitted(String holderRef, HolderKind holderKind,
                                          BigDecimal amount, String currency, Recorded recorded) {
        CashFloatEntry entry = new CashFloatEntry(holderRef, holderKind, null, amount, currency,
                Kind.REMITTED, null);
        entry.record(recorded);
        return entry;
    }

    /**
     * A delivery company's rider handing their cash to the company.
     *
     * <p>Held by the RIDER, because it is the rider's rows it clears; it names the company that
     * took the money, which the company's custody copies then carry.
     */
    public static CashFloatEntry transferred(String riderRef, String carrierRef, BigDecimal amount,
                                             String currency, Recorded recorded) {
        CashFloatEntry entry = new CashFloatEntry(riderRef, HolderKind.RIDER, null, amount,
                currency, Kind.TRANSFERRED, carrierRef);
        entry.record(recorded);
        return entry;
    }

    /**
     * One order's cash, now in a delivery company's custody.
     *
     * <p>The same order and amount as the rider's row the transfer cleared, so custody moves
     * without a cent appearing or vanishing. Remitted exactly as a rider's collection is.
     */
    public static CashFloatEntry custodyOf(String carrierRef, UUID orderId, BigDecimal amount,
                                           String currency, UUID handoverId) {
        CashFloatEntry entry = new CashFloatEntry(carrierRef, HolderKind.PROVIDER, orderId, amount,
                currency, Kind.COLLECTED, carrierRef);
        entry.handoverId = handoverId;
        return entry;
    }

    private void record(Recorded recorded) {
        Recorded r = recorded == null ? Recorded.nobody() : recorded;
        this.recordedBy = r.by();
        this.method = r.method();
        this.note = r.note();
        this.requestKey = r.requestKey();
    }

    /** Marks this collection as discharged by the given remittance or transfer. */
    public void clearedBy(UUID remittanceId) {
        this.clearedBy = remittanceId;
    }

    public boolean isOutstanding() {
        return entryKind == Kind.COLLECTED && clearedBy == null;
    }

    /** Whether this is a company's custody copy rather than notes taken at a door. */
    public boolean isCustodyCopy() {
        return handoverId != null;
    }

    public UUID getId() {
        return id;
    }

    public String getHolderRef() {
        return holderRef;
    }

    public HolderKind getHolderKind() {
        return holderKind;
    }

    public UUID getOrderId() {
        return orderId;
    }

    public BigDecimal getAmount() {
        return amount;
    }

    public String getCurrency() {
        return currency;
    }

    public Kind getEntryKind() {
        return entryKind;
    }

    public UUID getClearedBy() {
        return clearedBy;
    }

    public String getCarrierRef() {
        return carrierRef;
    }

    public UUID getHandoverId() {
        return handoverId;
    }

    public String getRecordedBy() {
        return recordedBy;
    }

    public Method getMethod() {
        return method;
    }

    public String getNote() {
        return note;
    }

    public String getRequestKey() {
        return requestKey;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }
}
