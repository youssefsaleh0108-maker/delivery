package com.delivery.accounting.domain;

import java.util.Collection;
import java.util.List;
import java.util.UUID;

import jakarta.persistence.LockModeType;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/** Corrections to delivery companies' approved pay runs. */
public interface CarrierPayAdjustmentRepository extends JpaRepository<CarrierPayAdjustment, UUID> {

    /**
     * Corrections about to be paid, locked for the rest of the transaction.
     *
     * <p>Two drafts of one company can both carry the same correction, and each run is locked on its
     * own row. Locking the correction as well is what makes the second approval wait, find it already
     * paid, and refuse — instead of both runs paying it.
     */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("""
            SELECT a FROM CarrierPayAdjustment a
             WHERE a.id IN :ids
             ORDER BY a.id
            """)
    List<CarrierPayAdjustment> lockAll(@Param("ids") Collection<UUID> ids);

    /** A company's corrections not yet paid in any run, oldest first. */
    List<CarrierPayAdjustment> findByCarrierRefAndAppliedRunIdIsNullOrderByCreatedAtAsc(
            String carrierRef);

    /** The corrections recorded against one run. */
    List<CarrierPayAdjustment> findByCorrectsRunIdOrderByCreatedAtAsc(UUID runId);
}
