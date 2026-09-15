package com.delivery.tracking.domain;

import java.time.LocalDate;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface AttendanceEntryRepository extends JpaRepository<AttendanceEntry, UUID> {

    /** The live entry for one day, if the office has recorded one. Backed by a partial unique index. */
    Optional<AttendanceEntry> findByRiderIdAndCarrierIdAndWorkDateAndRevokedAtIsNull(
            String riderId, UUID carrierId, LocalDate workDate);

    /** Live entries over a period, in date order. Revoked rows are history and are not read here. */
    @Query("""
            SELECT e FROM AttendanceEntry e
             WHERE e.riderId = :riderId
               AND e.carrierId = :carrierId
               AND e.workDate BETWEEN :from AND :to
               AND e.revokedAt IS NULL
             ORDER BY e.workDate
            """)
    List<AttendanceEntry> findLive(@Param("riderId") String riderId,
                                   @Param("carrierId") UUID carrierId,
                                   @Param("from") LocalDate from,
                                   @Param("to") LocalDate to);
}
