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

import com.delivery.product.domain.DeliveredOrderLine;
import com.delivery.product.domain.DeliveredOrderLineRepository;
import com.delivery.product.domain.ReviewableOrder;
import com.delivery.product.domain.ReviewableOrderRepository;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * Records what was delivered: which orders may be reviewed, and what was in the basket.
 *
 * <p>This is the whole of Product Service's interest in orders, and it is still not a mirror of one.
 * Two projections come off {@code order.delivered} and nothing else does:
 *
 * <ul>
 *   <li>{@link ReviewableOrder} — which order, whose it was, which shop. The three facts that make a
 *       review trustworthy (V19).
 *   <li>{@link DeliveredOrderLine} — which products shared a basket. The only honest basis for a
 *       cross-sell rail in a service that cannot read the orders schema (V22).
 * </ul>
 *
 * <p>Neither carries a price, a status or an address. Those are state another service owns, and a
 * second copy here would be a second copy that drifts.
 *
 * <p>Only {@code order.delivered} counts, for both. A placed order can still be cancelled: accepting
 * it early would let a customer rate a shop on the strength of an order they abandoned, and would
 * let a basket that was never handed over count as evidence that two things go together.
 */
@Component
public class OrderEventListener {

    private static final Logger log = LoggerFactory.getLogger(OrderEventListener.class);

    private final ReviewableOrderRepository reviewableOrders;
    private final DeliveredOrderLineRepository deliveredLines;
    private final ObjectMapper objectMapper;

    public OrderEventListener(ReviewableOrderRepository reviewableOrders,
                              DeliveredOrderLineRepository deliveredLines,
                              ObjectMapper objectMapper) {
        this.reviewableOrders = reviewableOrders;
        this.deliveredLines = deliveredLines;
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
            UUID storeId = UUID.fromString(rawStoreId);
            Instant deliveredAt = Instant.now();

            // save() rather than a check-then-insert: the id is the order's, so a redelivery of the
            // same event overwrites the row it already wrote instead of failing on the primary key.
            reviewableOrders.save(new ReviewableOrder(orderId, storeId, customerId, deliveredAt));

            recordBasket(event, orderId, storeId, deliveredAt);

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

    /**
     * Keeps the basket's line items, so cross-sell has something real to count.
     *
     * <p>The event has always carried {@code items}; nothing kept them until V22. This reads
     * {@code productId} and {@code qty} and deliberately nothing else — no price, no product name.
     * Both are already in the catalog, they are already versioned there, and copying them would
     * create a second record of what a thing is called that goes stale the first time a merchant
     * renames it.
     *
     * <p>A line with no {@code productId} is skipped rather than failing the batch. An errand's
     * "items" are free text a customer typed, not catalog rows, and a basket that is partly
     * catalogued is still worth counting for the part that is.
     *
     * <p>Idempotent by the primary key {@code (orderId, productId)}, like the reviewable-order row
     * above: an at-least-once redelivery rewrites the basket it already wrote rather than counting
     * it twice. That matters more here than there, because double-counting a basket would inflate a
     * number this service publishes as evidence.
     */
    private void recordBasket(JsonNode event, UUID orderId, UUID storeId, Instant deliveredAt) {
        JsonNode items = event.path("items");
        if (!items.isArray() || items.isEmpty()) {
            return;
        }

        for (JsonNode item : items) {
            String rawProductId = item.path("productId").asText(null);
            if (rawProductId == null || rawProductId.isBlank()) {
                continue;
            }

            UUID productId;
            try {
                productId = UUID.fromString(rawProductId);
            } catch (IllegalArgumentException notAUuid) {
                // One unparseable line must not cost the basket, nor the reviewable-order row that
                // has already been written in this same transaction.
                log.debug("Skipping an order line with an unusable product id");
                continue;
            }

            // Missing or nonsensical quantities are normalised to one rather than dropped. The
            // co-occurrence query counts baskets, not units, so the quantity does not affect the
            // rail at all — but the column is NOT NULL and CHECK (qty > 0), and losing the whole
            // line over a field nothing reads would be the wrong trade.
            int qty = Math.max(item.path("qty").asInt(1), 1);

            deliveredLines.save(
                    new DeliveredOrderLine(orderId, productId, storeId, qty, deliveredAt));
        }
    }
}
