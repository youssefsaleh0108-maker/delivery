package com.delivery.corebanking.simulator.domain;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * One accepted or rejected movement against an account.
 *
 * <p>Rejections are recorded, not discarded. A bank that keeps no trace of a refused posting makes
 * "we sent it, they say they never got it" unanswerable — and that argument is the reason the
 * accounting layer keeps a sync log of its own on the other side of the wire.
 */
@Entity
@Table(name = "bank_postings")
public class BankPosting {

    public enum Direction { DEBIT, CREDIT }

    public enum Status { POSTED, REJECTED }

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    /** The caller's idempotency key. Unique in the database — see the migration. */
    @Column(name = "client_reference", nullable = false, updatable = false, length = 64)
    private String clientReference;

    @Column(name = "account_ref", nullable = false, length = 64)
    private String accountRef;

    @Enumerated(EnumType.STRING)
    @Column(name = "direction", nullable = false, length = 8)
    private Direction direction;

    @Column(name = "amount_minor", nullable = false)
    private long amountMinor;

    @Column(name = "currency", nullable = false, length = 3)
    private String currency;

    @Column(name = "narrative", length = 255)
    private String narrative;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false, length = 16)
    private Status status;

    @Column(name = "balance_after_minor")
    private Long balanceAfterMinor;

    @Column(name = "rejection_reason", columnDefinition = "text")
    private String rejectionReason;

    @Column(name = "posted_at", nullable = false)
    private Instant postedAt;

    protected BankPosting() {
        // for JPA
    }

    private BankPosting(String clientReference, String accountRef, Direction direction,
                        long amountMinor, String currency, String narrative) {
        this.id = UUID.randomUUID();
        this.clientReference = clientReference;
        this.accountRef = accountRef;
        this.direction = direction;
        this.amountMinor = amountMinor;
        this.currency = currency;
        this.narrative = narrative;
        this.postedAt = Instant.now();
    }

    public static BankPosting posted(String clientReference, String accountRef, Direction direction,
                                     long amountMinor, String currency, String narrative,
                                     long balanceAfterMinor) {
        BankPosting posting = new BankPosting(
                clientReference, accountRef, direction, amountMinor, currency, narrative);
        posting.status = Status.POSTED;
        posting.balanceAfterMinor = balanceAfterMinor;
        return posting;
    }

    public static BankPosting rejected(String clientReference, String accountRef, Direction direction,
                                       long amountMinor, String currency, String narrative,
                                       String reason) {
        BankPosting posting = new BankPosting(
                clientReference, accountRef, direction, amountMinor, currency, narrative);
        posting.status = Status.REJECTED;
        posting.rejectionReason = reason;
        return posting;
    }

    public UUID getId() {
        return id;
    }

    public String getClientReference() {
        return clientReference;
    }

    public String getAccountRef() {
        return accountRef;
    }

    public Direction getDirection() {
        return direction;
    }

    public long getAmountMinor() {
        return amountMinor;
    }

    public String getCurrency() {
        return currency;
    }

    public String getNarrative() {
        return narrative;
    }

    public Status getStatus() {
        return status;
    }

    public Long getBalanceAfterMinor() {
        return balanceAfterMinor;
    }

    public String getRejectionReason() {
        return rejectionReason;
    }

    public Instant getPostedAt() {
        return postedAt;
    }
}
