package com.delivery.appnotification.domain;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * The merchant Product Service last confirmed as a shop's owner, and when.
 *
 * <p>A cache with a short shelf life and a delivery hint — see V24 and {@code ShopOwnership} for how
 * little it is trusted. Written only by an upsert after Product Service answered for the merchant's
 * own token.
 */
@Entity
@Table(name = "chat_store_owners")
public class ChatStoreOwner {

    @Id
    @Column(name = "store_id", nullable = false, updatable = false)
    private UUID storeId;

    @Column(name = "merchant_id", nullable = false, length = 64)
    private String merchantId;

    @Column(name = "confirmed_at", nullable = false)
    private Instant confirmedAt;

    protected ChatStoreOwner() {
        // for JPA
    }

    /** For tests; production writes go through the repository's upsert. */
    public ChatStoreOwner(UUID storeId, String merchantId, Instant confirmedAt) {
        this.storeId = storeId;
        this.merchantId = merchantId;
        this.confirmedAt = confirmedAt;
    }

    public UUID getStoreId() {
        return storeId;
    }

    public String getMerchantId() {
        return merchantId;
    }

    public Instant getConfirmedAt() {
        return confirmedAt;
    }
}
