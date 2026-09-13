package com.delivery.accounting.domain;

import java.util.List;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

/** Corrections to delivery companies' approved pay runs. */
public interface CarrierPayAdjustmentRepository extends JpaRepository<CarrierPayAdjustment, UUID> {

    /** A company's corrections not yet paid in any run, oldest first. */
    List<CarrierPayAdjustment> findByCarrierRefAndAppliedRunIdIsNullOrderByCreatedAtAsc(
            String carrierRef);

    /** The corrections recorded against one run. */
    List<CarrierPayAdjustment> findByCorrectsRunIdOrderByCreatedAtAsc(UUID runId);
}
