package com.delivery.product.event;

import java.math.BigDecimal;
import java.util.List;
import java.util.UUID;

import com.delivery.product.domain.Product;

/**
 * Catalog-change events published to the bus via the transactional outbox (Section 7).
 *
 * <p>Consumers so far: Order Manager caches name and price at order time so an order line survives
 * a later price change, and the Notifications Manager can tell a customer a saved item is back.
 * Neither exists yet — the events are published from Phase 1 so those services have history to
 * replay when they arrive.
 *
 * <p>The payload is intentionally a snapshot rather than a diff: a consumer that missed an earlier
 * event still ends up correct, which matters because outbox delivery is at-least-once and
 * out-of-order redelivery is possible.
 */
public final class CatalogEvents {

    /** Event type names double as the RabbitMQ routing key. */
    public static final String PRODUCT_CREATED = "product.created";
    public static final String PRODUCT_UPDATED = "product.updated";
    public static final String PRODUCT_PUBLISHED = "product.published";
    public static final String PRODUCT_ARCHIVED = "product.archived";

    public static final String AGGREGATE_TYPE = "Product";

    private CatalogEvents() {
    }

    public record ProductSnapshot(
            UUID id,
            String merchantId,
            String name,
            BigDecimal price,
            UUID categoryId,
            List<String> imageRefs,
            Product.Status status) {

        public static ProductSnapshot of(Product product) {
            return new ProductSnapshot(
                    product.getId(),
                    product.getMerchantId(),
                    product.getName(),
                    product.getPrice(),
                    product.getCategoryId(),
                    product.getImageRefs(),
                    product.getStatus());
        }
    }
}
