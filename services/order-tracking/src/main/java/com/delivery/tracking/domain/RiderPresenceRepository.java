package com.delivery.tracking.domain;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface RiderPresenceRepository extends JpaRepository<RiderPresence, String> {

    /**
     * Moves a rider's last-known fix forward, but only if the stored one is already older than
     * {@code staleBefore}.
     *
     * <p>This is a throttle, and it is the reason presence does not double the cost of the busiest
     * write path in the platform. Every rider pings every few seconds; without the predicate this
     * would be a second row update per ping, forever, on top of the {@code tracking_events} insert.
     * With it, most pings match no row, Postgres writes nothing, and the row moves at most once per
     * {@code delivery.tracking.presence.persist-interval}.
     *
     * <p>The cost is that the durable {@code last_seen_at} lags reality by up to that interval, so
     * a rider can read as stale slightly sooner than they truly are. That is the right direction to
     * be wrong in — presence erring towards "we are not sure" is safe, erring towards "still there"
     * hands work to a phone that is off — and the Redis snapshot, written on every ping, carries
     * the exact value for the single-rider read.
     *
     * @return 1 if the row was moved, 0 if it was throttled <em>or</em> does not exist
     */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("""
            UPDATE RiderPresence p
               SET p.lastLat = :lat,
                   p.lastLng = :lng,
                   p.lastAccuracyM = :accuracyM,
                   p.lastSeenAt = :now,
                   p.updatedAt = :now
             WHERE p.riderId = :riderId
               AND (p.lastSeenAt IS NULL OR p.lastSeenAt < :staleBefore)
            """)
    int touchIfDue(@Param("riderId") String riderId,
                   @Param("lat") double lat,
                   @Param("lng") double lng,
                   @Param("accuracyM") Float accuracyM,
                   @Param("now") Instant now,
                   @Param("staleBefore") Instant staleBefore);

    /**
     * The roster, newest sighting first.
     *
     * <p>Ordered by last seen rather than by name: a console watching a fleet wants the riders it
     * has just heard from at the top and the ones that have gone quiet at the bottom, which is the
     * order that makes a dead handset obvious.
     */
    List<RiderPresence> findByDutyStateOrderByLastSeenAtDesc(DutyState dutyState);

    List<RiderPresence> findByCarrierIdOrderByLastSeenAtDesc(UUID carrierId);

    List<RiderPresence> findByCarrierIdAndDutyStateOrderByLastSeenAtDesc(UUID carrierId,
                                                                        DutyState dutyState);

    List<RiderPresence> findAllByOrderByLastSeenAtDesc();
}
