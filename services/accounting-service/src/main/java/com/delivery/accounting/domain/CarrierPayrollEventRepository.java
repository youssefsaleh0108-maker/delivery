package com.delivery.accounting.domain;

import java.util.List;
import java.util.UUID;

import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;

/** The audit trail of delivery companies' payroll. */
public interface CarrierPayrollEventRepository extends JpaRepository<CarrierPayrollEvent, UUID> {

    /** What was done to one run, newest first. */
    List<CarrierPayrollEvent> findByRunIdOrderByOccurredAtDesc(UUID runId, Pageable pageable);
}
