package com.delivery.product.domain;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

public interface CatalogScanItemRepository extends JpaRepository<CatalogScanItem, UUID> {

    List<CatalogScanItem> findByScanIdOrderByPositionAsc(UUID scanId);

    /** Scoped to the scan, which the caller has already been proved to own. */
    Optional<CatalogScanItem> findByIdAndScanId(UUID id, UUID scanId);
}
