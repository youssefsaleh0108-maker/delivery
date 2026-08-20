package com.delivery.tracking.domain;

import java.util.List;
import java.util.UUID;

import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface TrackingEventRepository extends JpaRepository<TrackingEvent, UUID> {

    /** The breadcrumb trail for one delivery, oldest first — what a map draws as a route line. */
    List<TrackingEvent> findByOrderIdOrderByRecordedAtAsc(UUID orderId);

    /**
     * The single most recent ping for an order.
     *
     * <p>Only used to warm the Redis cache after a restart or a cache miss. The live read path never
     * reaches Postgres: Section 10 is explicit that a tracking screen polling every few seconds must
     * not hammer the database.
     */
    @Query("""
            SELECT t FROM TrackingEvent t
            WHERE t.orderId = :orderId
            ORDER BY t.recordedAt DESC
            """)
    List<TrackingEvent> findLatestForOrder(@Param("orderId") UUID orderId, Pageable pageable);
}
