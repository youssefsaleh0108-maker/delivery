package com.delivery.accounting.domain;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;

/** The settlements nobody will retry, for the Back Office's work list (RECON-04). */
public interface SettlementFailureRepository extends JpaRepository<SettlementFailure, UUID> {

    /** The open row for an order, which a redelivery updates instead of duplicating. */
    Optional<SettlementFailure> findByOrderIdAndResolvedAtIsNull(UUID orderId);

    /** Everything still open, most recently seen first. */
    List<SettlementFailure> findByResolvedAtIsNullOrderByLastSeenAtDesc(Pageable pageable);

    long countByResolvedAtIsNull();
}
