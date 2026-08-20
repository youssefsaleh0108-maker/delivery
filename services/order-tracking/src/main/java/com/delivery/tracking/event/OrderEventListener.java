package com.delivery.tracking.event;

import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.messaging.handler.annotation.Header;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.tracking.domain.OrderParticipants;
import com.delivery.tracking.domain.OrderParticipantsRepository;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * Consumes {@code order.*} events off the bus and maintains the local participants projection.
 *
 * <p>This is the first consumer of the outbox-backed bus in the platform, and it is what makes the
 * live-tracking authorisation check a local row lookup instead of a synchronous call to Order
 * Manager on every poll.
 *
 * <p><strong>Delivery is at-least-once</strong>, so this handler must be idempotent - the outbox
 * relay republishes anything whose PUBLISHED flag failed to commit. Every event carries a full
 * order snapshot rather than a diff, so re-applying one is a no-op by construction: the projection
 * is overwritten with the same values.
 */
@Component
public class OrderEventListener {

    private static final Logger log = LoggerFactory.getLogger(OrderEventListener.class);

    private final OrderParticipantsRepository participants;
    private final ObjectMapper objectMapper;

    public OrderEventListener(OrderParticipantsRepository participants, ObjectMapper objectMapper) {
        this.participants = participants;
        this.objectMapper = objectMapper;
    }

    @RabbitListener(queues = "${delivery.tracking.order-events-queue:tracking.order-events}")
    @Transactional
    public void onOrderEvent(String payload,
                             @Header(name = "amqp_correlationId", required = false) String correlationId) {

        // Rejoins this work to the request that caused it. Without it the projection update is the
        // one hop in an order's life that cannot be found by correlation id, which is exactly the
        // gap Section 10's tracing requirement exists to close - and it was missing until the
        // Phase 5 review went looking for it.
        if (correlationId != null) {
            MDC.put(CORRELATION_MDC_KEY, correlationId);
        }

        try {
            JsonNode node = objectMapper.readTree(payload);

            UUID orderId = UUID.fromString(node.path("orderId").asText());
            String customerId = node.path("customerId").asText(null);
            String merchantId = node.path("merchantId").asText(null);
            String riderId = node.path("riderId").isNull() ? null : node.path("riderId").asText(null);
            String status = node.path("status").asText(null);

            if (customerId == null || merchantId == null || status == null) {
                // Not an order snapshot we recognise. Ack it anyway - rejecting would requeue it
                // forever and stall the whole queue behind one bad message.
                log.warn("Ignoring order event without the expected fields: {}", payload);
                return;
            }

            participants.findById(orderId).ifPresentOrElse(
                    existing -> existing.apply(riderId, status),
                    () -> participants.save(new OrderParticipants(
                            orderId, customerId, merchantId, riderId, status)));

            log.debug("Projection updated: order {} status {} rider {}", orderId, status, riderId);

        } catch (Exception e) {
            // Same reasoning: a malformed message must not become a poison pill. The DLQ on the
            // publishing side is where genuinely undeliverable events end up (Section 10).
            log.error("Could not apply order event, skipping: {}", payload, e);

        } finally {
            if (correlationId != null) {
                MDC.remove(CORRELATION_MDC_KEY);
            }
        }
    }

    /** Matches the key platform-observability's filter uses on the HTTP side. */
    private static final String CORRELATION_MDC_KEY = "correlationId";
}
