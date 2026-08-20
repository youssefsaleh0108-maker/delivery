package com.delivery.product.domain;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.IdClass;
import jakarta.persistence.Table;

/**
 * What one shop charges to reach one area.
 *
 * <p><strong>Absence is the interesting part.</strong> A shop with no row for an area does not
 * deliver there, and an order to it is refused at placement. "We don't go that far" is the commonest
 * delivery rule in this market and could not be expressed at all before — a shop either took every
 * order or closed.
 *
 * <p>A shop with <em>no</em> rows at all is unchanged: it charges its flat fee and serves everywhere,
 * which is what every existing shop does today. Zones are opt-in per shop.
 */
@Entity
@Table(name = "store_delivery_zones")
@IdClass(StoreDeliveryZone.Key.class)
public class StoreDeliveryZone {

    @Id
    @Column(name = "store_id", nullable = false, updatable = false)
    private UUID storeId;

    @Id
    @Column(name = "zone_id", nullable = false, updatable = false)
    private UUID zoneId;

    @Column(name = "delivery_fee", nullable = false, precision = 12, scale = 2)
    private BigDecimal deliveryFee;

    /** Null means "use the shop's own minimum" rather than "no minimum". */
    @Column(name = "min_order", precision = 12, scale = 2)
    private BigDecimal minOrder;

    /** Added to both ends of the shop's ETA range: a further area genuinely takes longer. */
    @Column(name = "eta_extra_minutes", nullable = false)
    private int etaExtraMinutes;

    @Column(name = "updated_at", nullable = false, insertable = false, updatable = false)
    private Instant updatedAt;

    protected StoreDeliveryZone() {
        // for JPA
    }

    public StoreDeliveryZone(UUID storeId, UUID zoneId, BigDecimal deliveryFee,
                             BigDecimal minOrder, int etaExtraMinutes) {
        this.storeId = storeId;
        this.zoneId = zoneId;
        this.deliveryFee = deliveryFee;
        this.minOrder = minOrder;
        this.etaExtraMinutes = etaExtraMinutes;
    }

    public void update(BigDecimal deliveryFee, BigDecimal minOrder, int etaExtraMinutes) {
        this.deliveryFee = deliveryFee;
        this.minOrder = minOrder;
        this.etaExtraMinutes = etaExtraMinutes;
    }

    public UUID getStoreId() {
        return storeId;
    }

    public UUID getZoneId() {
        return zoneId;
    }

    public BigDecimal getDeliveryFee() {
        return deliveryFee;
    }

    public BigDecimal getMinOrder() {
        return minOrder;
    }

    public int getEtaExtraMinutes() {
        return etaExtraMinutes;
    }

    public Instant getUpdatedAt() {
        return updatedAt;
    }

    public static class Key implements java.io.Serializable {
        private UUID storeId;
        private UUID zoneId;

        @Override
        public boolean equals(Object o) {
            if (this == o) {
                return true;
            }
            if (!(o instanceof Key other)) {
                return false;
            }
            return java.util.Objects.equals(storeId, other.storeId)
                    && java.util.Objects.equals(zoneId, other.zoneId);
        }

        @Override
        public int hashCode() {
            return java.util.Objects.hash(storeId, zoneId);
        }
    }
}
