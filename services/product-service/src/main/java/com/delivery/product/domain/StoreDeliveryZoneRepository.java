package com.delivery.product.domain;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

public interface StoreDeliveryZoneRepository
        extends JpaRepository<StoreDeliveryZone, StoreDeliveryZone.Key> {

    List<StoreDeliveryZone> findByStoreId(UUID storeId);

    /** The terms for one shop reaching one area, or empty when it does not go there. */
    Optional<StoreDeliveryZone> findByStoreIdAndZoneId(UUID storeId, UUID zoneId);

    /** Whether this shop prices by area at all. False means the flat fee still applies. */
    boolean existsByStoreId(UUID storeId);

    List<StoreDeliveryZone> findByZoneId(UUID zoneId);

    void deleteByStoreIdAndZoneId(UUID storeId, UUID zoneId);
}
