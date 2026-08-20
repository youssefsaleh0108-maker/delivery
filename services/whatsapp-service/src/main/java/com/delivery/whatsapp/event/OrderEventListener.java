package com.delivery.whatsapp.event;

import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.messaging.handler.annotation.Header;
import org.springframework.stereotype.Component;

import com.delivery.whatsapp.service.OrderUpdateService;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * Order status changes, on their way back to the customer's chat.
 *
 * <p>A customer who ordered over WhatsApp has no app to open and no tracking screen to refresh. The
 * thread is the only thing they have, so this is where "your order is on the way" comes from.
 *
 * <p>Most events arriving here are for ordinary app orders and are dropped. That is expected — see
 * the binding note in {@code WhatsAppRabbitConfiguration}.
 */
@Component
public class OrderEventListener {

    /** Matches the key platform-observability's filter uses on the HTTP side. */
    private static final String CORRELATION_MDC_KEY = "correlationId";

    private static final Logger log = LoggerFactory.getLogger(OrderEventListener.class);

    private final OrderUpdateService updates;
    private final ObjectMapper objectMapper;

    public OrderEventListener(OrderUpdateService updates, ObjectMapper objectMapper) {
        this.updates = updates;
        this.objectMapper = objectMapper;
    }

    @RabbitListener(queues = "${delivery.whatsapp.order-events-queue:whatsapp.order-events}")
    public void onOrderEvent(String payload,
                             @Header(name = "amqp_correlationId", required = false) String correlationId) {

        // Rejoins this work to the request that caused it, so the message a customer received can
        // be traced back to the rider tap that triggered it.
        if (correlationId != null) {
            MDC.put(CORRELATION_MDC_KEY, correlationId);
        }

        try {
            JsonNode node = objectMapper.readTree(payload);
            String rawOrderId = node.path("orderId").asText(null);
            String status = node.path("status").asText(null);
            if (rawOrderId == null || status == null) {
                // Not a snapshot we recognise. Acked anyway: rejecting would requeue it forever and
                // stall every real update behind one bad message.
                log.warn("Ignoring an order event with no order id or status");
                return;
            }

            JsonNode reason = node.path("cancelReason");
            updates.onStatus(UUID.fromString(rawOrderId), status,
                    reason.isTextual() ? reason.asText() : null);

        } catch (Exception e) {
            // Same reasoning: a malformed message must not become a poison pill.
            log.error("Could not handle an order event, skipping", e);
        } finally {
            if (correlationId != null) {
                MDC.remove(CORRELATION_MDC_KEY);
            }
        }
    }
}
