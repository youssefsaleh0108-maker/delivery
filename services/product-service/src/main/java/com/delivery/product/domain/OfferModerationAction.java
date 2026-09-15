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
 * One act of back office on a service offer: taking it down or restoring it (V36).
 *
 * <p>The trail, not the state. Whether an offer is taken down is on the product ({@link Product#takeDown});
 * this records who acted, when, on which offer of which shop, and why. It is written in the same
 * transaction as the act, so an act nobody can account for never happens, and it is never updated.
 * Every column is {@code updatable = false}, so no later save can rewrite what was recorded.
 *
 * <p>{@code createdAt} is the service's clock, handed in, rather than the column default. A take-down's
 * row then carries the same instant as the product's {@code taken_down_at}, and the two can be matched.
 */
@Entity
@Table(name = "offer_moderation_actions")
public class OfferModerationAction {

    public enum Action {
        /** Taken off sale and held there ({@link Product#takeDown}). */
        TAKE_DOWN,
        /** The hold lifted ({@link Product#restore}). */
        RESTORE
    }

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "product_id", nullable = false, updatable = false)
    private UUID productId;

    @Column(name = "store_id", nullable = false, updatable = false)
    private UUID storeId;

    @Enumerated(EnumType.STRING)
    @Column(name = "action", nullable = false, length = 16, updatable = false)
    private Action action;

    @Column(name = "reason", nullable = false, length = Product.MAX_TAKEDOWN_REASON_LENGTH, updatable = false)
    private String reason;

    /** The staff member's Keycloak {@code sub}, from their token. */
    @Column(name = "actor_id", nullable = false, length = 64, updatable = false)
    private String actorId;

    /** The username their token carried; null when it carried none. */
    @Column(name = "actor_name", length = 255, updatable = false)
    private String actorName;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    protected OfferModerationAction() {
        // for JPA
    }

    /**
     * Records an act on {@code offer}. Built before the act is applied, so a reason the trail cannot
     * hold refuses the act rather than half of it.
     *
     * @throws IllegalArgumentException when the reason is blank or longer than
     *                                  {@value Product#MAX_TAKEDOWN_REASON_LENGTH} characters
     */
    public OfferModerationAction(Product offer, Action action, String reason, String actorId,
                                 String actorName, Instant at) {
        String given = reason == null ? "" : reason.trim();
        if (given.isEmpty()) {
            throw new IllegalArgumentException("Say why");
        }
        if (given.length() > Product.MAX_TAKEDOWN_REASON_LENGTH) {
            throw new IllegalArgumentException(
                    "A reason is at most " + Product.MAX_TAKEDOWN_REASON_LENGTH + " characters");
        }
        this.id = UUID.randomUUID();
        this.productId = offer.getId();
        this.storeId = offer.getStoreId();
        this.action = action;
        this.reason = given;
        this.actorId = actorId;
        this.actorName = actorName == null || actorName.isBlank() ? null : actorName;
        this.createdAt = at;
    }

    public UUID getId() {
        return id;
    }

    public UUID getProductId() {
        return productId;
    }

    public UUID getStoreId() {
        return storeId;
    }

    public Action getAction() {
        return action;
    }

    public String getReason() {
        return reason;
    }

    public String getActorId() {
        return actorId;
    }

    public String getActorName() {
        return actorName;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }
}
