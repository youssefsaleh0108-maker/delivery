package com.delivery.tracking.domain;

import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface DutySessionRepository extends JpaRepository<DutySession, UUID> {

    /** The rider's running shift, if any. Backed by the partial unique index, so at most one. */
    Optional<DutySession> findByRiderIdAndEndedAtIsNull(String riderId);

    /**
     * One rider's sessions overlapping {@code [from, until)}, oldest first.
     *
     * <p>Overlap rather than containment: a shift that started before the window still worked hours
     * inside it, and the aggregation clips it to the window rather than losing or double-counting
     * it. A session that ended exactly at {@code from} has zero overlap and is excluded.
     */
    @Query("""
            SELECT s FROM DutySession s
             WHERE s.riderId = :riderId
               AND s.startedAt < :until
               AND (s.endedAt IS NULL OR s.endedAt > :from)
             ORDER BY s.startedAt
            """)
    List<DutySession> findOverlapping(@Param("riderId") String riderId,
                                      @Param("from") Instant from,
                                      @Param("until") Instant until);

    /**
     * Open sessions of riders the platform has given up hearing from.
     *
     * <p>Abandoned means both the shift start and the last sighting are older than the cutoff. Both
     * conditions matter: a rider who just went on duty and has no GPS fix yet must not be expired
     * on a stale {@code last_seen_at} from before their shift, and a rider who is still pinging
     * keeps moving {@code last_seen_at} and never matches.
     */
    @Query("""
            SELECT s FROM DutySession s, RiderPresence p
             WHERE p.riderId = s.riderId
               AND s.endedAt IS NULL
               AND s.startedAt < :cutoff
               AND (p.lastSeenAt IS NULL OR p.lastSeenAt < :cutoff)
            """)
    List<DutySession> findAbandonedBefore(@Param("cutoff") Instant cutoff);
}
