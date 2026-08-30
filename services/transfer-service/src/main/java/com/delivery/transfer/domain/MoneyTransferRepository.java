package com.delivery.transfer.domain;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;

/** Transfers, looked up the two ways the API needs them: by order, and by payer. */
public interface MoneyTransferRepository extends JpaRepository<MoneyTransfer, UUID> {

    Optional<MoneyTransfer> findByOrderId(UUID orderId);

    List<MoneyTransfer> findByPayerRefOrderByCreatedAtDesc(String payerRef, Pageable pageable);
}
