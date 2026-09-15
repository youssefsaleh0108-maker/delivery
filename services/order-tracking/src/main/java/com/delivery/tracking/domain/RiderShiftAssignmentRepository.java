package com.delivery.tracking.domain;

import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface RiderShiftAssignmentRepository extends JpaRepository<RiderShiftAssignment, UUID> {

    /**
     * One rider's assignments in one fleet that touch {@code [from, to]}, oldest first.
     *
     * <p>Filtered by fleet as well as rider so a former employer's schedule never follows a rider
     * to their next company.
     */
    @Query("""
            SELECT a FROM RiderShiftAssignment a
             WHERE a.riderId = :riderId
               AND a.carrierId = :carrierId
               AND a.effectiveFrom <= :to
               AND (a.effectiveTo IS NULL OR a.effectiveTo >= :from)
             ORDER BY a.effectiveFrom
            """)
    List<RiderShiftAssignment> findTouching(@Param("riderId") String riderId,
                                            @Param("carrierId") UUID carrierId,
                                            @Param("from") LocalDate from,
                                            @Param("to") LocalDate to);

    /**
     * Everything in a fleet that is running today or starts later — what the schedule page lists.
     */
    @Query("""
            SELECT a FROM RiderShiftAssignment a
             WHERE a.carrierId = :carrierId
               AND (a.effectiveTo IS NULL OR a.effectiveTo >= :today)
             ORDER BY a.riderId, a.effectiveFrom
            """)
    List<RiderShiftAssignment> findCurrentAndUpcoming(@Param("carrierId") UUID carrierId,
                                                      @Param("today") LocalDate today);

    /** Rows for one rider in one fleet that are running today or start later. */
    @Query("""
            SELECT a FROM RiderShiftAssignment a
             WHERE a.riderId = :riderId
               AND a.carrierId = :carrierId
               AND (a.effectiveTo IS NULL OR a.effectiveTo >= :day)
             ORDER BY a.effectiveFrom
            """)
    List<RiderShiftAssignment> findFrom(@Param("riderId") String riderId,
                                        @Param("carrierId") UUID carrierId,
                                        @Param("day") LocalDate day);

    /** How many riders are on (or about to start) this shift — archiving waits until it is none. */
    @Query("""
            SELECT count(a) FROM RiderShiftAssignment a
             WHERE a.templateId = :templateId
               AND (a.effectiveTo IS NULL OR a.effectiveTo >= :today)
            """)
    long countActiveOrUpcoming(@Param("templateId") UUID templateId,
                               @Param("today") LocalDate today);
}
