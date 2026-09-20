package com.delivery.product.domain;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * One photo read for one account: who, which kind, and when. Nothing else (V38).
 *
 * <p>Exists only so the photo reader's limits can be counted ({@code PhotoQuota}). Deliberately holds
 * nothing about the photo — no bytes, no key, no description, no search terms, no location — so there
 * is nothing here to leak, and nothing that ties an account to what it photographed.
 */
@Entity
@Table(name = "photo_search_uses")
public class PhotoSearchUse {

    /** What the photo was read for. Each kind has limits of its own. */
    public enum Kind {
        /** A customer searching the shops by photo. */
        CUSTOMER_SEARCH,
        /** A merchant finding a product in their own catalogue by photo. */
        MERCHANT_FIND
    }

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "account_id", nullable = false, length = 64, updatable = false)
    private String accountId;

    @Enumerated(EnumType.STRING)
    @Column(name = "kind", nullable = false, length = 16, updatable = false)
    private Kind kind;

    /**
     * The service's clock, not the database's: the windows the limits count over are measured from
     * the same clock, so a test with a fixed clock sees exactly the rows it expects.
     */
    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    protected PhotoSearchUse() {
    }

    public PhotoSearchUse(String accountId, Kind kind, Instant createdAt) {
        this.id = UUID.randomUUID();
        this.accountId = accountId;
        this.kind = kind;
        this.createdAt = createdAt;
    }

    public UUID getId() {
        return id;
    }

    public String getAccountId() {
        return accountId;
    }

    public Kind getKind() {
        return kind;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }
}
