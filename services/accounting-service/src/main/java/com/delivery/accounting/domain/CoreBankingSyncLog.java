package com.delivery.accounting.domain;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

/**
 * Exactly what went to the bank and exactly what came back (Section 4).
 *
 * <p>Append-only, and separate from the transaction row on purpose. The transaction's status
 * changes as the saga progresses; this does not. When someone asks "you say you sent it — what did
 * you send", a status column cannot answer and a mutable row cannot be trusted to.
 */
@Entity
@Table(name = "core_banking_sync_log")
public class CoreBankingSyncLog {

    public enum Outcome {
        POSTED,
        /** The bank refused with certainty. */
        REJECTED,
        /** The bank was unavailable or slow; the attempt may be repeated. */
        RETRYABLE,
        /** Our side broke before the bank had a view. */
        ERROR
    }

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "transaction_id", nullable = false, updatable = false)
    private UUID transactionId;

    @Column(name = "provider", length = 32)
    private String provider;

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "request_payload", columnDefinition = "jsonb")
    private String requestPayload;

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "response_payload", columnDefinition = "jsonb")
    private String responsePayload;

    @Enumerated(EnumType.STRING)
    @Column(name = "outcome", nullable = false, length = 16)
    private Outcome outcome;

    @Column(name = "synced_at", nullable = false)
    private Instant syncedAt;

    protected CoreBankingSyncLog() {
        // for JPA
    }

    public CoreBankingSyncLog(UUID transactionId, String provider, String requestPayload,
                              String responsePayload, Outcome outcome) {
        this.id = UUID.randomUUID();
        this.transactionId = transactionId;
        this.provider = provider;
        this.requestPayload = requestPayload;
        this.responsePayload = responsePayload;
        this.outcome = outcome;
        this.syncedAt = Instant.now();
    }

    public UUID getId() {
        return id;
    }

    public UUID getTransactionId() {
        return transactionId;
    }

    public String getProvider() {
        return provider;
    }

    public String getRequestPayload() {
        return requestPayload;
    }

    public String getResponsePayload() {
        return responsePayload;
    }

    public Outcome getOutcome() {
        return outcome;
    }

    public Instant getSyncedAt() {
        return syncedAt;
    }
}
