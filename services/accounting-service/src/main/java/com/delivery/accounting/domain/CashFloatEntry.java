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
 */
@Entity
@Table(name = "cash_float")
public class CashFloatEntry {

    public enum Kind {
        /** Notes taken from a customer. Creates the obligation. */
        COLLECTED,
        /** Takings banked. Discharges some or all of it. */
        REMITTED,
        /** Written off by an operator — theft, loss, a dispute settled the other way. */
        WRITTEN_OFF
    }

    /**
     * Who holds it.
     *
     * <p>{@code PROVIDER} is unused until delivery companies collect their own COD, and is here
     * from the start because adding a discriminator to a table that already has rows means deciding
     * what every existing row meant.
     */
    public enum HolderKind { RIDER, PROVIDER }

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "holder_ref", nullable = false, updatable = false, length = 64)
    private String holderRef;

    @Enumerated(EnumType.STRING)
    @Column(name = "holder_kind", nullable = false, updatable = false, length = 16)
    private HolderKind holderKind;

    /** Null on a remittance, which settles many orders at once rather than belonging to one. */
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

    @Column(name = "created_at", nullable = false, insertable = false, updatable = false)
    private Instant createdAt;

    protected CashFloatEntry() {
        // for JPA
    }

    private CashFloatEntry(String holderRef, HolderKind holderKind, UUID orderId,
                           BigDecimal amount, String currency, Kind entryKind) {
        this.id = UUID.randomUUID();
        this.holderRef = holderRef;
        this.holderKind = holderKind;
        this.orderId = orderId;
        this.amount = amount;
        this.currency = currency;
        this.entryKind = entryKind;
    }

    /** Notes taken at the door for one order. */
    public static CashFloatEntry collected(String holderRef, HolderKind holderKind, UUID orderId,
                                           BigDecimal amount, String currency) {
        return new CashFloatEntry(holderRef, holderKind, orderId, amount, currency, Kind.COLLECTED);
    }

    /** Takings banked. Belongs to no single order, which is why {@code orderId} is null. */
    public static CashFloatEntry remitted(String holderRef, HolderKind holderKind,
                                          BigDecimal amount, String currency) {
        return new CashFloatEntry(holderRef, holderKind, null, amount, currency, Kind.REMITTED);
    }

    /** Marks this collection as discharged by the given remittance. */
    public void clearedBy(UUID remittanceId) {
        this.clearedBy = remittanceId;
    }

    public boolean isOutstanding() {
        return entryKind == Kind.COLLECTED && clearedBy == null;
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

    public Instant getCreatedAt() {
        return createdAt;
    }
}
