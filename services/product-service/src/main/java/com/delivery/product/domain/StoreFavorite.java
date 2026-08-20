package com.delivery.product.domain;

import java.io.Serializable;
import java.time.Instant;
import java.util.Objects;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Embeddable;
import jakarta.persistence.EmbeddedId;
import jakarta.persistence.Entity;
import jakarta.persistence.Table;

/**
 * A customer has starred a store.
 *
 * <p>The natural key is the whole row, which is the point: starring a store twice is not an error
 * to be detected and reported, it is a no-op. Making {@code (user_id, store_id)} the primary key
 * means the database enforces that without any read-then-write race in the service.
 */
@Entity
@Table(name = "store_favorites")
public class StoreFavorite {

    @Embeddable
    public record Id(
            @Column(name = "user_id", nullable = false, length = 64) String userId,
            @Column(name = "store_id", nullable = false) UUID storeId) implements Serializable {

        public Id {
            Objects.requireNonNull(userId, "userId");
            Objects.requireNonNull(storeId, "storeId");
        }
    }

    @EmbeddedId
    private Id id;

    @Column(name = "created_at", nullable = false, insertable = false, updatable = false)
    private Instant createdAt;

    protected StoreFavorite() {
        // for JPA
    }

    public StoreFavorite(String userId, UUID storeId) {
        this.id = new Id(userId, storeId);
    }

    public Id getId() {
        return id;
    }

    public String getUserId() {
        return id.userId();
    }

    public UUID getStoreId() {
        return id.storeId();
    }

    public Instant getCreatedAt() {
        return createdAt;
    }
}
