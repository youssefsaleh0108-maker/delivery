package com.delivery.product.domain;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * "This merchant has already been told about this week" (V40).
 *
 * <p>One row per merchant per week, and the unique constraint on the pair is the whole mechanism: the
 * job inserts before it raises anything, so a second run, a restarted pod or a second replica loses
 * the insert and sends nothing. A message per shop per term — the thing a merchant with four shops
 * would never forgive — is impossible by shape, because there is nowhere to put a second row.
 */
@Entity
@Table(name = "search_demand_digest")
public class SearchDemandDigest {

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "week_start", nullable = false, updatable = false)
    private Instant weekStart;

    /** Keycloak sub of the merchant the message was addressed to. */
    @Column(name = "merchant_id", nullable = false, length = 64, updatable = false)
    private String merchantId;

    /** How many unmet terms the message named. */
    @Column(name = "terms", nullable = false, updatable = false)
    private int terms;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    protected SearchDemandDigest() {
    }

    public SearchDemandDigest(Instant weekStart, String merchantId, int terms, Instant createdAt) {
        this.id = UUID.randomUUID();
        this.weekStart = weekStart;
        this.merchantId = merchantId;
        this.terms = terms;
        this.createdAt = createdAt;
    }

    public UUID getId() {
        return id;
    }

    public Instant getWeekStart() {
        return weekStart;
    }

    public String getMerchantId() {
        return merchantId;
    }

    public int getTerms() {
        return terms;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }
}
