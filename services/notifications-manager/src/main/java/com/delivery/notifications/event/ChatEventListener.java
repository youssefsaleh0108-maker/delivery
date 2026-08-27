package com.delivery.notifications.event;

import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.messaging.handler.annotation.Header;
import org.springframework.stereotype.Component;

import com.delivery.notifications.service.NotificationDispatchService;
import com.delivery.notifications.service.RecipientDirectory;
import com.delivery.platform.notifications.ChatEvents;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * Turns "that chat message reached nobody" into a push.
 *
 * <p>The other half of {@link ChatEvents}. App Notification Service holds the chat socket and knows
 * when a message had nowhere live to land; it does not know the recipient's device token, their
 * notification preferences or their locale, and it must not — that is this service's job, and a
 * service that reached past it would also bypass {@code notification_log}, leaving "why did this
 * push not arrive" unanswerable for exactly one kind of notification.
 *
 * <p><strong>Its own queue, bound to {@code chat.#}.</strong> Not the {@code order.#} queue next
 * door: a chat event carries no order snapshot, so {@link OrderEventListener} would have to
 * recognise and discard it on every delivery, and one malformed chat message would sit in front of
 * every order notification behind it.
 *
 * <p><strong>Deduplicated on the message id, not the order.</strong> Every other event this service
 * consumes is unique per order — one {@code order.delivered} per order. A conversation is many
 * messages against one order, so the order-based check would push for the first missed message and
 * stay silent for the rest of the thread. See {@code NotificationDispatchService.dispatch}'s
 * {@code dedupeKey}.
 */
@Component
public class ChatEventListener {

    private static final Logger log = LoggerFactory.getLogger(ChatEventListener.class);

    private final NotificationDispatchService dispatch;
    private final RecipientDirectory recipients;
    private final ObjectMapper objectMapper;

    public ChatEventListener(NotificationDispatchService dispatch, RecipientDirectory recipients,
                             ObjectMapper objectMapper) {
        this.dispatch = dispatch;
        this.recipients = recipients;
        this.objectMapper = objectMapper;
    }

    @RabbitListener(queues = "${delivery.notifications.chat-events-queue:notifications.chat-events}")
    public void onChatEvent(String payload,
                            @Header(name = "eventType", required = false) String headerEventType,
                            @Header(name = "amqp_receivedRoutingKey", required = false) String routingKey,
                            @Header(name = "amqp_correlationId", required = false) String correlationId) {

        String eventType = headerEventType != null ? headerEventType : routingKey;

        if (correlationId != null) {
            MDC.put("correlationId", correlationId);
        }

        try {
            if (!ChatEvents.MESSAGE_MISSED.equals(eventType)) {
                // The binding is a wildcard so a new chat event reaches this service without a
                // config change; until one has an audience there is nothing to do with it.
                log.debug("No audience defined for {}", eventType);
                return;
            }

            JsonNode event = objectMapper.readTree(payload);

            UUID orderId = uuidOrNull(event, "orderId");
            UUID messageId = uuidOrNull(event, "messageId");
            String recipientId = textOrNull(event, "recipientId");

            // Every one of the three is load-bearing and none can be guessed. Acked rather than
            // requeued: a message that can never be understood coming back forever blocks every
            // good one behind it, and nothing here is retryable.
            if (orderId == null || messageId == null || recipientId == null) {
                log.warn("Ignoring a {} missing the order, the message or the recipient", eventType);
                return;
            }

            dispatch.dispatch(eventType, orderId, recipientId,
                    recipients.contactsFor(recipientId), placeholders(event, orderId),
                    correlationId, messageId.toString());

            // The preview is deliberately absent from this line. The body is private to two people
            // and a log file is not one of them.
            log.debug("Requested a push for missed chat message {} on order {}", messageId, orderId);

        } catch (Exception e) {
            log.error("Could not turn a chat event into a notification: {}", payload, e);

        } finally {
            if (correlationId != null) {
                MDC.remove("correlationId");
            }
        }
    }

    /**
     * The values the chat templates interpolate.
     *
     * <p>{@code conversationId} is here for two reasons. It is what the template's declared
     * {@code CONVERSATION} link target reads its id from — so a tapped push opens the thread rather
     * than the order — and it is the only way the customer's app can tell which of several
     * conversations the notification was about.
     *
     * <p><strong>{@code preview} is text one user wrote about another.</strong> It is placed as a
     * value and never lengthened here; App Notification already capped it, and re-expanding it
     * would put more of a private message on a lock screen than the service that owns it decided to
     * expose. Absent — previews turned off — it renders as an empty string rather than the literal
     * "null".
     */
    private Map<String, String> placeholders(JsonNode event, UUID orderId) {
        Map<String, String> values = new LinkedHashMap<>();
        values.put("shortId", orderId.toString().substring(0, 8).toUpperCase(java.util.Locale.ROOT));
        values.put("orderId", orderId.toString());
        values.put("conversationId", event.path("conversationId").asText(""));
        values.put("preview", event.path("preview").asText(""));
        // "the rider" / "the customer", not a name: the event carries roles precisely so neither
        // participant's identity has to travel to the other's lock screen.
        values.put("sender", who(event.path("senderRole").asText("")));
        return values;
    }

    private static String who(String role) {
        return switch (role) {
            case "RIDER" -> "your rider";
            case "CUSTOMER" -> "your customer";
            default -> "someone";
        };
    }

    private static UUID uuidOrNull(JsonNode event, String field) {
        String value = textOrNull(event, field);
        if (value == null) {
            return null;
        }
        try {
            return UUID.fromString(value);
        } catch (IllegalArgumentException e) {
            return null;
        }
    }

    private static String textOrNull(JsonNode event, String field) {
        JsonNode node = event.path(field);
        if (node.isMissingNode() || node.isNull()) {
            return null;
        }
        String value = node.asText(null);
        return value == null || value.isBlank() ? null : value;
    }
}
