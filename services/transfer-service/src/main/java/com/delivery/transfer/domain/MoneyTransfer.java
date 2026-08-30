package com.delivery.transfer.domain;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;

/**
 * One movement of money through the platform, however it physically travels.
 *
 * <p>Everything is DENOMINATED in USD — that is what prices, settlement and the accounting ledger
 * speak — and the LBP columns record how the customer chose to hand it over: {@code amountLbp} at
 * {@code rateUsed}, the platform rate LOCKED at quote time. The lock is the product promise: the
 * lira figure a customer saw at checkout is the lira figure the rider collects, whatever the rate
 * does in between. That is why the rate lives on the row and not in a lookup at collection time.
 *
 * <p>The split is stored as the pair (splitUsd, splitLbpInUsd): both sides in USD so they sum to
 * {@code amountUsd} exactly and no rounding argument can open between the columns. The lira face
 * value the rider must collect is {@code splitLbpInUsd × rateUsed}, computed, never stored twice.
 */
@Entity
@Table(name = "money_transfers")
public class MoneyTransfer {

    @Id
    private UUID id;

    /** The order this pays for. Unique — a second payment intent for one order REPLACES the row. */
    @Column(name = "order_id", nullable = false)
    private UUID orderId;

    /** Keycloak subject of the payer. Ownership checks run against this. */
    @Column(name = "payer_ref", nullable = false)
    private String payerRef;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private TransferMethod method;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private TransferStatus status;

    /** The whole obligation, USD. */
    @Column(name = "amount_usd", nullable = false, precision = 12, scale = 2)
    private BigDecimal amountUsd;

    /** The part the customer pays in physical USD. */
    @Column(name = "split_usd", nullable = false, precision = 12, scale = 2)
    private BigDecimal splitUsd;

    /** The part the customer pays in lira, expressed in USD so the two splits sum exactly. */
    @Column(name = "split_lbp_in_usd", nullable = false, precision = 12, scale = 2)
    private BigDecimal splitLbpInUsd;

    /** LBP per USD, locked when the quote was issued. */
    @Column(name = "rate_used", nullable = false, precision = 12, scale = 2)
    private BigDecimal rateUsed;

    /** Which connector carried it — the audit answer to "how did this money actually move". */
    @Column(nullable = false)
    private String connector;

    /** The connector's own reference (a Whish/OMT transaction id; null for cash). */
    @Column(name = "connector_ref")
    private String connectorRef;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    protected MoneyTransfer() {
        // JPA
    }

    public MoneyTransfer(UUID orderId, String payerRef, TransferMethod method,
                         BigDecimal amountUsd, BigDecimal splitUsd, BigDecimal splitLbpInUsd,
                         BigDecimal rateUsed) {
        this.id = UUID.randomUUID();
        this.orderId = orderId;
        this.payerRef = payerRef;
        this.method = method;
        this.status = TransferStatus.PENDING;
        this.amountUsd = amountUsd;
        this.splitUsd = splitUsd;
        this.splitLbpInUsd = splitLbpInUsd;
        this.rateUsed = rateUsed;
        this.connector = "";
    }

    @PrePersist
    void onCreate() {
        createdAt = Instant.now();
        updatedAt = createdAt;
    }

    @PreUpdate
    void onUpdate() {
        updatedAt = Instant.now();
    }

    public void carriedBy(String connectorName, String reference, TransferStatus newStatus) {
        this.connector = connectorName;
        this.connectorRef = reference;
        this.status = newStatus;
    }

    /** The lira face value the rider collects (or the wallet debits): split × locked rate. */
    public BigDecimal lbpFaceValue() {
        return splitLbpInUsd.multiply(rateUsed);
    }

    public UUID getId() { return id; }
    public UUID getOrderId() { return orderId; }
    public String getPayerRef() { return payerRef; }
    public TransferMethod getMethod() { return method; }
    public TransferStatus getStatus() { return status; }
    public BigDecimal getAmountUsd() { return amountUsd; }
    public BigDecimal getSplitUsd() { return splitUsd; }
    public BigDecimal getSplitLbpInUsd() { return splitLbpInUsd; }
    public BigDecimal getRateUsed() { return rateUsed; }
    public String getConnector() { return connector; }
    public String getConnectorRef() { return connectorRef; }
    public Instant getCreatedAt() { return createdAt; }
    public Instant getUpdatedAt() { return updatedAt; }
}
