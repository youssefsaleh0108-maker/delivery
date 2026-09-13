package com.delivery.accounting.domain;

import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

/** The payslips of delivery companies' pay runs. Always reached through a run already scoped. */
public interface CarrierPayslipRepository extends JpaRepository<CarrierPayslip, UUID> {

    List<CarrierPayslip> findByRunIdOrderByRiderRefAsc(UUID runId);

    /** Every payslip of several runs, for the period list's counts — a few hundred rows at most. */
    List<CarrierPayslip> findByRunIdIn(Collection<UUID> runIds);

    /** A payslip only through its own run: an id from another run finds nothing. */
    Optional<CarrierPayslip> findByIdAndRunId(UUID id, UUID runId);

    /** A draft's payslips, replaced when it is recomputed. Never called for an approved run. */
    void deleteByRunId(UUID runId);
}
