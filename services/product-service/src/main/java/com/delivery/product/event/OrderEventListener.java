package com.delivery.product.event;

import java.time.Instant;
import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.messaging.handler.annotation.Header;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.product.domain.ReviewableOrder;
import com.delivery.product.domain.ReviewableOrderRepository;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * Records which orders were delivered, so a review can be checked against one.
 *
 * <p>This is the whole of Product Service's interest in orders. It does not mirror the order — only
 * the three facts that make a review trustworthy: which order, whose it was, and which shop it came
 * from.
 *
 * <p>Only {@code order.delivered} counts. A placed or cancelled order is not something anyone can
 * have an opinion about yet, and accepting reviews earlier would let a customer rate a shop on the
 * basis of an order they then cancelled.
 */
@Component
public class OrderEventListener {

    private static final Logger log = LoggerFactory.getLogger(OrderEventListener.class);

    private final ReviewableOrderRepository reviewableOrders;
    private final ObjectMapper objectMapper;

    public OrderEventListener(ReviewableOrderRepository reviewableOrders,
                              ObjectMapper objectMapper) {
        this.reviewableOrders = reviewableOrders;
        this.objectMapper = objectMapper;
    }

    @RabbitListener(queues = "${delivery.product.order-events-queue:product.order-events}")
    @Transactional
    public void onOrderEvent(String payload,
                             @Header(name = "eventType", required = false) String headerEventType,
                             @Header(name = "amqp_receivedRoutingKey", required = false) String routingKey,
                             @Header(name = "amqp_correlationId", required = false) String correlationId) {

        String eventType = headerEventType != null ? headerEventType : routingKey;
        if (!"order.delivered".equals(eventType)) {
            return;
        }

        if (correlationId != null) {
            MDC.put("correlationId", correlationId);
        }

        try {
            JsonNode event = objectMapper.readTree(payload);

            String rawStoreId = event.path("storeId").asText(null);
            String customerId = event.path("customerId").asText(null);
            String rawOrderId = event.path("orderId").asText(null);

            if (rawOrderId == null || rawStoreId == null || customerId == null
                    || rawStoreId.isBlank() || customerId.isBlank()) {
                // An errand has no shop to review, so it is not reviewable and this is not an error.
                // Anything else missing is malformed, and either way there is nothing to record.
                log.debug("Delivered order has no reviewable shop, skipping");
                return;
            }

            UUID orderId = UUID.fromString(rawOrderId);
            // save() rather than a check-then-insert: the id is the order's, so a redelivery of the
            // same event overwrites the row it already wrote instead of failing on the primary key.
            reviewableOrders.save(new ReviewableOrder(
                    orderId, UUID.fromString(rawStoreId), customerId, Instant.now()));

            log.debug("Order {} is now reviewable", orderId);

        } catch (Exception e) {
            // Swallowed rather than rethrown: requeueing would spin, and a review invitation the
            // customer never receives is a smaller problem than a stuck queue. The row can be
            // rebuilt from the order history if it ever matters.
            log.error("Could not record a delivered order as reviewable", e);

        } finally {
            if (correlationId != null) {
                MDC.remove("correlationId");
            }
        }
    }
}
