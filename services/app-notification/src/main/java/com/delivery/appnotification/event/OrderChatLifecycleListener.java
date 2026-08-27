package com.delivery.appnotification.event;

import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.messaging.handler.annotation.Header;
import org.springframework.stereotype.Component;

import com.delivery.appnotification.service.ChatProperties;
import com.delivery.appnotification.service.ChatService;
import com.delivery.platform.observability.CorrelationIdFilter;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * Opens and closes order conversations from the order events on the bus.
 *
 * <p><strong>Nobody creates a conversation over HTTP.</strong> There is no "start a chat" endpoint,
 * and that absence is the point: membership has to be exactly the order's customer and the order's
 * assigned rider, so it is derived from the event that establishes that pairing rather than from
 * anything a client sends. A client that could name the participants could name the wrong ones.
 *
 * <p>Reads the same {@code order.*} snapshots Order Tracking's projection reads, on this service's
 * own queue. A topic exchange fans out, so binding the same key does not compete with any other
 * consumer for messages.
 *
 * <p><strong>Idempotent, because delivery is at-least-once.</strong> Re-opening finds the existing
 * conversation and returns it; re-closing keeps the first window rather than pushing it forward. A
 * redelivery an hour after a delivery must not give the customer another two hours.
 */
@Component
public class OrderChatLifecycleListener {

    private static final Logger log = LoggerFactory.getLogger(OrderChatLifecycleListener.class);

    /**
     * Order Manager's routing keys, restated rather than imported.
     *
     * <p>{@code OrderEvents} lives inside Order Manager's own deployable and this service does not
     * depend on it — making it a dependency would couple a notification service to an order
     * service's build for three string constants. The strings themselves are the contract; a later
     * integration pass may lift them into {@code platform-notifications}.
     */
    private static final String ORDER_RIDER_ASSIGNED = "order.rider_assigned";
    private static final String ORDER_DELIVERED = "order.delivered";
    private static final String ORDER_CANCELLED = "order.cancelled";

    private final ChatService chat;
    private final ChatProperties properties;
    private final ObjectMapper objectMapper;

    public OrderChatLifecycleListener(ChatService chat, ChatProperties properties,
                                      ObjectMapper objectMapper) {
        this.chat = chat;
        this.properties = properties;
        this.objectMapper = objectMapper;
    }

    @RabbitListener(queues = "${delivery.chat.order-events-queue:app-notification.order-events}")
    public void onOrderEvent(String payload,
                             @Header(name = "eventType", required = false) String headerEventType,
                             @Header(name = "amqp_receivedRoutingKey", required = false) String routingKey,
                             @Header(name = "amqp_correlationId", required = false) String correlationId) {

        // The outbox relay sets both; the routing key is the fallback for anything published
        // without the header.
        String eventType = headerEventType != null ? headerEventType : routingKey;
        if (eventType == null) {
            log.warn("Ignoring an order event with no type");
            return;
        }

        if (correlationId != null) {
            MDC.put(CorrelationIdFilter.MDC_KEY, correlationId);
        }

        try {
            JsonNode event = objectMapper.readTree(payload);
            JsonNode orderIdNode = event.path("orderId");
            if (orderIdNode.isMissingNode() || orderIdNode.isNull()) {
                log.warn("Ignoring a {} with no orderId", eventType);
                return;
            }
            UUID orderId = UUID.fromString(orderIdNode.asText());

            switch (eventType) {
                case ORDER_RIDER_ASSIGNED -> chat.openForRider(
                        orderId, text(event, "customerId"), text(event, "riderId"));

                // Delivered: the line stays open for a while, because the conversation a customer
                // needs after a delivery starts when they unpack the bag, not when they take it.
                case ORDER_DELIVERED -> chat.closeAfter(orderId, properties.getCloseAfterDelivery());

                // Cancelled: shut immediately. There is no delivery to ask about, and in the usual
                // case the rider never reached the address.
                case ORDER_CANCELLED -> chat.closeAfter(orderId, ChatProperties.CLOSE_ON_CANCEL);

                // Everything else, order.status_changed included, is somebody else's business. A
                // status change does not alter who is in the conversation, and this service already
                // hears about the two transitions that do.
                default -> log.trace("No chat lifecycle for {}", eventType);
            }

        } catch (Exception e) {
            // Acked rather than requeued: a malformed message must not become a poison pill that
            // stalls every later event behind it. The visible symptom is a conversation that never
            // opens, which the missing row makes obvious. The payload is an order snapshot and
            // carries no chat text, so logging it discloses nothing private.
            log.error("Could not apply order event {} to chat: {}", eventType, payload, e);

        } finally {
            if (correlationId != null) {
                MDC.remove(CorrelationIdFilter.MDC_KEY);
            }
        }
    }

    private static String text(JsonNode event, String field) {
        JsonNode node = event.path(field);
        return node.isMissingNode() || node.isNull() ? null : node.asText(null);
    }

}
