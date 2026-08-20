package com.delivery.platform.notifications;

import java.time.Instant;
import java.util.Map;

/**
 * The contract between a worker and its connector.
 *
 * <p>One shape for all three channels. The worker has already decided <em>what</em> to say and to
 * <em>whom</em>; the connector only decides <em>how</em> to hand it to a provider. Keeping the
 * rendered body here rather than a template id means the connector never needs the template store,
 * which is what lets a connector hold provider credentials without also holding notification
 * content logic.
 *
 * @param notificationId the notification_log row this came from — also the idempotency key, so a
 *                       redelivered command can never send a second SMS (Section 7)
 * @param channel        SMS, EMAIL or PUSH
 * @param recipient      phone number, email address or device token, depending on channel
 * @param subject        used by EMAIL and PUSH; ignored for SMS
 * @param body           fully rendered, ready to send
 * @param metadata       channel-specific extras (e.g. deep-link for PUSH), never secrets
 */
public record NotificationCommand(
        String notificationId,
        String channel,
        String recipient,
        String subject,
        String body,
        Map<String, String> metadata,
        String correlationId,
        Instant createdAt) implements IdempotentCommand {

    /** The notification_log row id, stable across every retry and redelivery. */
    @Override
    public String idempotencyKey() {
        return notificationId;
    }

    public static final String CHANNEL_SMS = "SMS";
    public static final String CHANNEL_EMAIL = "EMAIL";
    public static final String CHANNEL_PUSH = "PUSH";
    public static final String CHANNEL_IN_APP = "IN_APP";

    /**
     * The endpoint every connector exposes. One path for all three so a worker's client code is
     * identical bar the base URL, and so adding a fourth channel needs no new contract.
     */
    public static final String CONNECTOR_SEND_PATH = "/api/connector/send";

    /**
     * Routing keys: {@code notification.dispatch.sms|email|push|in_app}.
     *
     * <p>One key — and so one queue and one consumer — per channel. A single shared queue would let
     * one poison message or one slow provider back up every other channel behind it, which is
     * head-of-line blocking across SMS, email and push at once.
     */
    public static String routingKeyFor(String channel) {
        return "notification.dispatch." + channel.toLowerCase(java.util.Locale.ROOT);
    }
}
