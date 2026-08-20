package com.delivery.platform.notifications;

import java.time.Instant;

/**
 * What a worker reports back to Notifications Manager once a channel is done with a message.
 *
 * <p>The manager writes the notification_log row before dispatch and never learns the result
 * synchronously — the worker is a separate deployable consuming off a queue. Without this receipt
 * every row would sit at PENDING forever, and "why didn't this SMS arrive" (Section 10) would be
 * unanswerable from the log alone, which is the whole point of keeping one.
 *
 * <p>{@code deadLettered} is separate from {@code success} because the two failure shapes need
 * different operator responses: a retryable failure that is still being retried is noise, while a
 * dead-lettered message is a message a human has to decide about.
 *
 * @param notificationId the notification_log row id — the same idempotency key the command carried
 */
public record DeliveryReceipt(
        String notificationId,
        String channel,
        String provider,
        boolean success,
        boolean deadLettered,
        String providerMessageId,
        String failureReason,
        Instant occurredAt) {

    /** Routing key workers publish receipts on; the manager binds exactly this. */
    public static final String ROUTING_KEY = "notification.result";

    public static DeliveryReceipt from(NotificationCommand command, String fallbackProvider,
                                       DeliveryOutcome outcome) {
        return new DeliveryReceipt(
                command.notificationId(),
                command.channel(),
                // The connector names the vendor it used; the fallback covers failures that never
                // reached one.
                outcome.provider() != null ? outcome.provider() : fallbackProvider,
                outcome.success(),
                // Exhausted or permanent: either way nothing further will be attempted for it.
                !outcome.success() && !outcome.retryable(),
                outcome.providerMessageId(),
                outcome.failureReason(),
                Instant.now());
    }
}
