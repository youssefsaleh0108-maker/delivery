package com.delivery.product.domain;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

public interface DeliveryZoneRepository extends JpaRepository<DeliveryZone, UUID> {

    /** The picker: retired areas are hidden, and the order is the one an operator chose. */
    List<DeliveryZone> findByActiveTrueOrderBySortOrderAscNameAsc();

    List<DeliveryZone> findAllByOrderBySortOrderAscNameAsc();

    Optional<DeliveryZone> findByNameIgnoreCase(String name);

    boolean existsByNameIgnoreCase(String name);
}
