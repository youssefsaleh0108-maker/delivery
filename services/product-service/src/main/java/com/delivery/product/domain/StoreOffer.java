package com.delivery.product.domain;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * A promotion, scoped to one store or to the whole platform.
 *
 * <p>{@code storeId} being null is the platform-wide case rather than a separate table, because the
 * two are identical in every respect the customer sees and identical in how they are applied to a
 * basket. Two tables would mean two of every query that renders an Offers tab.
 */
@Entity
@Table(name = "store_offers")
public class StoreOffer {

    public enum Kind {
        /** {@code value} is a percentage of the eligible subtotal. */
        PERCENT_OFF,
        /** {@code value} is a flat currency amount. */
        AMOUNT_OFF,
        /** Waives the store's delivery fee. {@code value} is unused. */
        FREE_DELIVERY
    }

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    /** Null means platform-wide. */
    @Column(name = "store_id")
    private UUID storeId;

    @Enumerated(EnumType.STRING)
    @Column(name = "kind", nullable = false, length = 24)
    private Kind kind;

    @Column(name = "title", nullable = false, length = 160)
    private String title;

    @Column(name = "subtitle", length = 240)
    private String subtitle;

    @Column(name = "value", precision = 12, scale = 2)
    private BigDecimal value;

    @Column(name = "min_subtotal", nullable = false, precision = 12, scale = 2)
    private BigDecimal minSubtotal = BigDecimal.ZERO;

    @Column(name = "starts_at", nullable = false)
    private Instant startsAt;

    /** Null runs until withdrawn. */
    @Column(name = "ends_at")
    private Instant endsAt;

    @Column(name = "active", nullable = false)
    private boolean active = true;

    protected StoreOffer() {
        // for JPA
    }

    public StoreOffer(UUID storeId, Kind kind, String title, String subtitle,
                      BigDecimal value, BigDecimal minSubtotal) {
        this.id = UUID.randomUUID();
        this.storeId = storeId;
        this.kind = kind;
        this.title = title;
        this.subtitle = subtitle;
        this.value = value;
        this.minSubtotal = minSubtotal == null ? BigDecimal.ZERO : minSubtotal;
        this.startsAt = Instant.now();
        this.active = true;
    }

    public boolean isLiveAt(Instant now) {
        return active
                && !startsAt.isAfter(now)
                && (endsAt == null || endsAt.isAfter(now));
    }

    public boolean appliesTo(BigDecimal subtotal) {
        return subtotal != null && subtotal.compareTo(minSubtotal) >= 0;
    }

    /**
     * What this offer takes off the basket.
     *
     * <p>Returns zero for {@link Kind#FREE_DELIVERY}: that discount lands on the delivery fee, not
     * the subtotal, and folding it in here would double-count it against a basket that has not yet
     * had a fee added.
     */
    public BigDecimal discountOn(BigDecimal subtotal) {
        if (!appliesTo(subtotal)) {
            return BigDecimal.ZERO;
        }
        BigDecimal discount = switch (kind) {
            case PERCENT_OFF -> subtotal.multiply(value)
                    .divide(BigDecimal.valueOf(100), 2, RoundingMode.HALF_UP);
            case AMOUNT_OFF -> value;
            case FREE_DELIVERY -> BigDecimal.ZERO;
        };
        // Never discount past zero — a basket cannot pay the customer.
        return discount.min(subtotal).max(BigDecimal.ZERO);
    }

    public void withdraw() {
        this.active = false;
    }

    public UUID getId() {
        return id;
    }

    public UUID getStoreId() {
        return storeId;
    }

    public Kind getKind() {
        return kind;
    }

    public String getTitle() {
        return title;
    }

    public String getSubtitle() {
        return subtitle;
    }

    public BigDecimal getValue() {
        return value;
    }

    public BigDecimal getMinSubtotal() {
        return minSubtotal;
    }

    public Instant getStartsAt() {
        return startsAt;
    }

    public Instant getEndsAt() {
        return endsAt;
    }

    public boolean isActive() {
        return active;
    }
}
