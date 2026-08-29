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
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * Turns {@code order.*} events into notifications.
 *
 * <p>This class answers only one question — <em>who cares about this event</em> — and hands the
 * rest to {@link NotificationDispatchService}. Which channels fire is not decided here: that is a
 * matter of which template rows exist, so adding an SMS to a status change is an insert, not a
 * release.
 *
 * <p>Audience is per event type and is a real product decision. The customer hears about their own
 * order's progress; the merchant hears that work has arrived and that it was cancelled; the rider
 * hears about the job they were assigned. Notifying everyone about everything is how a platform
 * trains its users to ignore its notifications.
 */
@Component
public class OrderEventListener {

    private static final Logger log = LoggerFactory.getLogger(OrderEventListener.class);

    private final NotificationDispatchService dispatch;
    private final RecipientDirectory recipients;
    private final ObjectMapper objectMapper;

    public OrderEventListener(NotificationDispatchService dispatch, RecipientDirectory recipients,
                              ObjectMapper objectMapper) {
        this.dispatch = dispatch;
        this.recipients = recipients;
        this.objectMapper = objectMapper;
    }

    @RabbitListener(queues = "${delivery.notifications.order-events-queue:notifications.order-events}")
    public void onOrderEvent(String payload,
                             @Header(name = "eventType", required = false) String headerEventType,
                             @Header(name = "amqp_receivedRoutingKey", required = false) String routingKey,
                             @Header(name = "amqp_correlationId", required = false) String correlationId) {

        // The outbox relay sets both; the routing key is the fallback for anything published
        // without the header.
        String eventType = headerEventType != null ? headerEventType : routingKey;

        if (correlationId != null) {
            // Rejoins this work to the request that caused it — the whole point of Section 10's
            // "why didn't this SMS arrive" being answerable across a dozen services.
            MDC.put("correlationId", correlationId);
        }

        try {
            JsonNode event = objectMapper.readTree(payload);

            if (event.path("orderId").isMissingNode() || eventType == null) {
                // Not an order snapshot we recognise. Acked rather than rejected: requeuing would
                // stall the whole queue behind one bad message.
                log.warn("Ignoring event without an orderId or type: {}", payload);
                return;
            }

            UUID orderId = UUID.fromString(event.path("orderId").asText());
            Map<String, String> values = placeholders(event, orderId);

            switch (eventType) {
                case "order.placed" -> {
                    notify(eventType, orderId, event.path("customerId").asText(null), values, correlationId);
                    // The merchant's copy says something different: it is a work item, not a
                    // receipt. Same event, different template row, keyed on a distinct type.
                    notify("order.placed.merchant", orderId, event.path("merchantId").asText(null),
                            values, correlationId);
                }
                case "order.status_changed" ->
                        // With a dedupe key carrying the RAW status. The order-based check treats
                        // all four transitions (ACCEPTED, PREPARING, READY, PICKED_UP) as one
                        // notification — same order, same type — so only the first ever fired and
                        // the rest were silently discarded as duplicates. Keyed per status, each
                        // transition notifies exactly once and a redelivered event still cannot
                        // notify twice. The raw wire value, not the humanised one: the key must be
                        // stable however the copy is worded.
                        notify(eventType, orderId, event.path("customerId").asText(null),
                                values, correlationId,
                                orderId + ":" + event.path("status").asText(""));
                case "order.delivered" ->
                        notify(eventType, orderId, event.path("customerId").asText(null),
                                values, correlationId);
                case "order.rider_assigned" -> {
                    notify(eventType, orderId, event.path("customerId").asText(null),
                            values, correlationId);
                    notify("order.rider_assigned.rider", orderId, textOrNull(event, "riderId"),
                            values, correlationId);
                }
                case "order.cancelled" -> {
                    notify(eventType, orderId, event.path("customerId").asText(null),
                            values, correlationId);
                    notify("order.cancelled.merchant", orderId, event.path("merchantId").asText(null),
                            values, correlationId);
                }
                default -> log.debug("No audience defined for {}", eventType);
            }

        } catch (Exception e) {
            // A malformed message must not become a poison pill. The notification_log is empty for
            // this event, which is itself the signal that something went wrong here.
            log.error("Could not turn event into notifications: {}", payload, e);

        } finally {
            if (correlationId != null) {
                MDC.remove("correlationId");
            }
        }
    }

    private void notify(String eventType, UUID orderId, String recipientId,
                        Map<String, String> values, String correlationId) {
        notify(eventType, orderId, recipientId, values, correlationId, null);
    }

    private void notify(String eventType, UUID orderId, String recipientId,
                        Map<String, String> values, String correlationId, String dedupeKey) {
        if (recipientId == null || recipientId.isBlank()) {
            return;
        }
        dispatch.dispatch(eventType, orderId, recipientId,
                recipients.contactsFor(recipientId), values, correlationId, dedupeKey);
    }

    /**
     * The values templates interpolate.
     *
     * <p>Everything is stringified here rather than in the template, so a template author never has
     * to think about formatting — and so a null in the event becomes an empty string rather than
     * the literal text "null" in a customer's SMS.
     */
    private Map<String, String> placeholders(JsonNode event, UUID orderId) {
        Map<String, String> values = new LinkedHashMap<>();

        // The full UUID is unreadable in a text message and useless to a customer reading it aloud
        // to support; the first segment is enough to identify an order in conversation.
        values.put("shortId", orderId.toString().substring(0, 8).toUpperCase(java.util.Locale.ROOT));
        values.put("orderId", orderId.toString());
        values.put("status", humanise(event.path("status").asText("")));
        values.put("statusMessage", statusMessage(event.path("status").asText("")));
        values.put("total", money(event.path("totalAmount")));
        values.put("address", event.path("deliveryAddress").asText(""));
        values.put("reason", event.path("cancelReason").asText(""));
        values.put("itemCount", String.valueOf(event.path("items").size()));

        return values;
    }

    /** {@code PICKED_UP} reads badly in a customer-facing message; "picked up" does not. */
    private static String humanise(String status) {
        return status.isEmpty()
                ? ""
                : status.replace('_', ' ').toLowerCase(java.util.Locale.ROOT);
    }

    /**
     * A real sentence per status, for the customer's status-change push. "Order #X is now
     * preparing" is a state machine talking; "The restaurant is preparing your order" is a
     * platform talking. Unknown statuses fall back to the humanised word so a new state never
     * sends an empty message.
     */
    private static String statusMessage(String status) {
        return switch (status) {
            case "ACCEPTED" -> "The restaurant has accepted your order.";
            case "PREPARING" -> "The restaurant is preparing your order.";
            case "READY" -> "Your order is ready and waiting for a rider.";
            case "PICKED_UP" -> "Your rider has picked up your order and is on the way.";
            default -> status.isEmpty() ? "" : "Your order is now " + humanise(status) + ".";
        };
    }

    private static String money(JsonNode amount) {
        if (amount.isMissingNode() || amount.isNull()) {
            return "";
        }
        return amount.decimalValue().setScale(2, java.math.RoundingMode.HALF_UP).toPlainString();
    }

    private static String textOrNull(JsonNode event, String field) {
        JsonNode node = event.path(field);
        return node.isNull() || node.isMissingNode() ? null : node.asText(null);
    }
}
