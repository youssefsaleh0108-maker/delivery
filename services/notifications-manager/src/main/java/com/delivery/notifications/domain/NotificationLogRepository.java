package com.delivery.notifications.domain;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

public interface NotificationLogRepository extends JpaRepository<NotificationLog, UUID> {

    /**
     * Finds the message a carrier receipt refers to.
     *
     * <p>Scoped by provider as well as id because the vendor's id is only unique within that
     * vendor — two providers issuing the same string is not a hypothetical, and an unscoped lookup
     * would mark the wrong message delivered. Backed by the partial index added in V12.
     */
    Optional<NotificationLog> findByProviderAndProviderMessageId(String provider,
                                                                 String providerMessageId);

    List<NotificationLog> findByRecipientIdOrderByCreatedAtDesc(String recipientId);

    List<NotificationLog> findByOrderIdOrderByCreatedAtDesc(UUID orderId);

    /**
     * Guards against duplicate notifications when the bus redelivers an event.
     *
     * <p>Outbox delivery is at-least-once, so the same {@code order.status_changed} can arrive
     * twice. Without this check the customer gets two texts for one status change — annoying for
     * in-app, and billable for SMS.
     */
    boolean existsByOrderIdAndEventTypeAndChannelAndRecipientId(
            UUID orderId, String eventType, String channel, String recipientId);

    /**
     * Delivery rates per channel and provider over a window.
     *
     * <p>The gate on Phase 6's vendor cutover: "monitor delivery rates before fully retiring the
     * test-inbox fallback" is unanswerable without this. Grouped by provider rather than only by
     * channel because during a canary ramp two providers are live on one channel at once, and the
     * whole point is to compare them.
     *
     * <p>Computed from notification_log rather than from a counter, so it survives a restart and
     * reports history rather than uptime — a rate that resets when a pod cycles is not something
     * anyone can make a cutover decision on.
     */
    @org.springframework.data.jpa.repository.Query(value = """
            SELECT channel                                       AS "channel",
                   provider                                      AS "provider",
                   count(*)                                      AS "total",
                   count(*) FILTER (WHERE status = 'SENT')       AS "sent",
                   count(*) FILTER (WHERE status IN ('FAILED', 'DEAD_LETTERED')) AS "failed",
                   count(*) FILTER (WHERE status = 'PENDING')    AS "pending",
                   avg(EXTRACT(EPOCH FROM (sent_at - created_at))) AS "avgSecondsToSend",
                   count(*) FILTER (WHERE delivery_status = 'DELIVERED')   AS "delivered",
                   count(*) FILTER (WHERE delivery_status = 'UNDELIVERED') AS "undelivered",
                   count(*) FILTER (WHERE status = 'SENT' AND delivery_status IS NULL)
                                                                 AS "awaitingReceipt",
                   avg(EXTRACT(EPOCH FROM (delivered_at - sent_at)))
                       FILTER (WHERE delivery_status = 'DELIVERED') AS "avgSecondsToDeliver"
              FROM notification_log
             WHERE created_at >= :since
             GROUP BY channel, provider
             ORDER BY channel, provider
            """, nativeQuery = true)
    List<DeliveryRateProjection> deliveryRatesSince(
            @org.springframework.data.repository.query.Param("since") java.time.Instant since);
}
