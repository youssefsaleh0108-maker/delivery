package com.delivery.tracking.domain;

import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/** When riders belonged to which delivery company. See {@link CarrierMembershipPeriod}. */
public interface CarrierMembershipPeriodRepository
        extends JpaRepository<CarrierMembershipPeriod, UUID> {

    /** The rider's current fleet, if the record has them on one. */
    Optional<CarrierMembershipPeriod> findByRiderIdAndLeftAtIsNull(String riderId);

    /** Everything on record for one rider, oldest first. */
    List<CarrierMembershipPeriod> findByRiderIdOrderByJoinedAtAsc(String riderId);

    /** Whether a join with exactly this instant is already on record — a redelivery. */
    boolean existsByRiderIdAndCarrierIdAndJoinedAt(String riderId, UUID carrierId, Instant joinedAt);

    /** Whether a leave with exactly this instant is already on record — a redelivery. */
    boolean existsByRiderIdAndCarrierIdAndLeftAt(String riderId, UUID carrierId, Instant leftAt);

    /** One rider's spells on one fleet that overlap {@code [from, to)}, oldest first. */
    @Query("""
            SELECT p FROM CarrierMembershipPeriod p
             WHERE p.carrierId = :carrierId
               AND p.riderId = :riderId
               AND p.joinedAt < :to
               AND (p.leftAt IS NULL OR p.leftAt > :from)
             ORDER BY p.joinedAt
            """)
    List<CarrierMembershipPeriod> overlappingForRider(@Param("carrierId") UUID carrierId,
                                                      @Param("riderId") String riderId,
                                                      @Param("from") Instant from,
                                                      @Param("to") Instant to);

    /** Every spell on one fleet that overlaps {@code [from, to)}, by rider and then by time. */
    @Query("""
            SELECT p FROM CarrierMembershipPeriod p
             WHERE p.carrierId = :carrierId
               AND p.joinedAt < :to
               AND (p.leftAt IS NULL OR p.leftAt > :from)
             ORDER BY p.riderId, p.joinedAt
            """)
    List<CarrierMembershipPeriod> overlappingForCarrier(@Param("carrierId") UUID carrierId,
                                                        @Param("from") Instant from,
                                                        @Param("to") Instant to);
}
