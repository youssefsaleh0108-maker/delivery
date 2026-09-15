package com.delivery.product.domain;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

public interface CatalogScanPhotoRepository extends JpaRepository<CatalogScanPhoto, UUID> {

    List<CatalogScanPhoto> findByScanIdOrderByPositionAsc(UUID scanId);

    /** Scoped to the scan, so a file id from another scan — even the caller's own — is not found. */
    Optional<CatalogScanPhoto> findByScanIdAndFileId(UUID scanId, UUID fileId);

    long countByScanId(UUID scanId);
}
