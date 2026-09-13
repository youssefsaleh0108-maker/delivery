package com.delivery.accounting.domain;

import java.time.LocalDate;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import jakarta.persistence.LockModeType;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/**
 * Delivery companies' pay runs.
 *
 * <p>Every read names the company as well as the run. A run id from another company's page must
 * find nothing, and the only way to make that true everywhere is for no query to find a run by its
 * id alone.
 */
public interface CarrierPayRunRepository extends JpaRepository<CarrierPayRun, UUID> {

    Optional<CarrierPayRun> findByIdAndCarrierRef(UUID id, String carrierRef);

    /**
     * The run, locked for the rest of the transaction.
     *
     * <p>Every change to a run or its payslips takes this first, so a recompute, an approval and a
     * payment on the same run happen one after another: two approvals cannot both net a rider's
     * cash, and a payment cannot land on a payslip a recompute is replacing.
     */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("""
            SELECT r FROM CarrierPayRun r
             WHERE r.id = :id
               AND r.carrierRef = :carrier
            """)
    Optional<CarrierPayRun> lockOwned(@Param("id") UUID id, @Param("carrier") String carrier);

    /**
     * Any run of this company sharing a day with the period. Calendar-aligned periods that overlap
     * always share a first or last day, and the unique keys refuse that; this is the friendly check
     * that names the run already there before the insert is attempted.
     */
    @Query("""
            SELECT r FROM CarrierPayRun r
             WHERE r.carrierRef = :carrier
               AND r.periodFrom <= :to
               AND r.periodTo >= :from
            """)
    List<CarrierPayRun> overlapping(@Param("carrier") String carrier,
                                    @Param("from") LocalDate from,
                                    @Param("to") LocalDate to);

    /** The company's runs for periods ending on or after a day, latest period first. */
    @Query("""
            SELECT r FROM CarrierPayRun r
             WHERE r.carrierRef = :carrier
               AND r.periodTo >= :since
             ORDER BY r.periodFrom DESC
            """)
    List<CarrierPayRun> endingOnOrAfter(@Param("carrier") String carrier,
                                        @Param("since") LocalDate since);

    /**
     * Whether a run past its draft starts on or after a day. A new pay policy may not start before
     * such a run: it would claim to govern a period whose figures are already frozen under another.
     */
    boolean existsByCarrierRefAndStatusNotAndPeriodFromGreaterThanEqual(
            String carrierRef, CarrierPayRun.Status status, LocalDate day);
}
