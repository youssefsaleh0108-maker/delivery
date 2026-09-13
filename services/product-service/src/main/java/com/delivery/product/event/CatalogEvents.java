package com.delivery.product.event;

import java.math.BigDecimal;
import java.util.List;
import java.util.UUID;

import com.delivery.product.domain.Product;
import com.delivery.product.domain.ServiceTerms;

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
 *
 * <p>Pausing and resuming a service offer record {@link #PRODUCT_UPDATED}: the snapshot's status says
 * which, and a consumer that already follows updates needs nothing new to notice either.
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
            Product.Status status,
            /**
             * A service offer's terms; null for a goods product.
             *
             * <p>On every event about the offer, including the ones an image upload records. A
             * consumer projecting snapshots takes each one as the whole truth, so a snapshot that left
             * the terms out would read as terms removed. Order Manager needs them to price packs and
             * to know which fulfilments an offer allows.
             */
            ServiceBlock service) {

        /**
         * @param terms the product's service terms, or null for a goods product. A parameter rather
         *              than a default, so no writer can record a service offer without its terms.
         */
        public static ProductSnapshot of(Product product, ServiceTerms terms) {
            return new ProductSnapshot(
                    product.getId(),
                    product.getMerchantId(),
                    product.getName(),
                    product.getPrice(),
                    product.getCategoryId(),
                    product.getImageRefs(),
                    product.getStatus(),
                    ServiceBlock.of(terms));
        }
    }

    /** A service offer's terms as events carry them. See {@link ServiceTerms}. */
    public record ServiceBlock(
            ServiceTerms.PricingType pricingType,
            String unitLabel,
            int unitSize,
            int turnaroundMinHours,
            int turnaroundMaxHours,
            ServiceTerms.Fulfilment fulfilmentModes,
            ServiceTerms.AttachmentPolicy attachmentPolicy,
            String instructionsPrompt) {

        static ServiceBlock of(ServiceTerms terms) {
            if (terms == null) {
                return null;
            }
            return new ServiceBlock(terms.getPricingType(), terms.getUnitLabel(), terms.getUnitSize(),
                    terms.getTurnaroundMinHours(), terms.getTurnaroundMaxHours(),
                    terms.getFulfilmentModes(), terms.getAttachmentPolicy(),
                    terms.getInstructionsPrompt());
        }
    }
}
