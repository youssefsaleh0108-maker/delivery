package com.delivery.product.domain;

import java.math.BigDecimal;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * One answer within a {@link ProductOptionGroup} — "Medium (30 Cm)", "Extra cheese".
 *
 * <p>{@code priceDelta} is signed. "Small" being -1.00 is as ordinary as "Large" being +3.00, and
 * modelling surcharges only would force every menu to be priced from its cheapest variant.
 */
@Entity
@Table(name = "product_options")
public class ProductOption {

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "group_id", insertable = false, updatable = false)
    private UUID groupId;

    @Column(name = "name", nullable = false, length = 120)
    private String name;

    @Column(name = "price_delta", nullable = false, precision = 12, scale = 2)
    private BigDecimal priceDelta = BigDecimal.ZERO;

    @Column(name = "is_default", nullable = false)
    private boolean isDefault;

    /** Sold out tonight. Kept rather than deleted so the price and any history survive. */
    @Column(name = "available", nullable = false)
    private boolean available = true;

    @Column(name = "position", nullable = false)
    private short position;

    protected ProductOption() {
        // for JPA
    }

    public ProductOption(String name, BigDecimal priceDelta, boolean isDefault, int position) {
        this.id = UUID.randomUUID();
        this.name = name;
        this.priceDelta = priceDelta == null ? BigDecimal.ZERO : priceDelta;
        this.isDefault = isDefault;
        this.available = true;
        this.position = (short) position;
    }

    public void setAvailable(boolean available) {
        this.available = available;
    }

    public UUID getId() {
        return id;
    }

    public UUID getGroupId() {
        return groupId;
    }

    public String getName() {
        return name;
    }

    public BigDecimal getPriceDelta() {
        return priceDelta;
    }

    public boolean isDefault() {
        return isDefault;
    }

    public boolean isAvailable() {
        return available;
    }

    public short getPosition() {
        return position;
    }
}
