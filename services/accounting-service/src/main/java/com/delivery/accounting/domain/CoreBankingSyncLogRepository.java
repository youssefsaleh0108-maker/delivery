package com.delivery.accounting.domain;

import java.util.List;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

public interface CoreBankingSyncLogRepository extends JpaRepository<CoreBankingSyncLog, UUID> {

    List<CoreBankingSyncLog> findByTransactionIdOrderBySyncedAtDesc(UUID transactionId);
}
