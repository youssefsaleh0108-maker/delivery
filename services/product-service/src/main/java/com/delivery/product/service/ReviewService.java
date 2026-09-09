package com.delivery.product.service;

import java.math.BigDecimal;
import java.util.Optional;
import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.product.domain.ReviewableOrder;
import com.delivery.product.domain.ReviewableOrderRepository;
import com.delivery.product.domain.Store;
import com.delivery.product.domain.StoreRepository;
import com.delivery.product.domain.StoreReview;
import com.delivery.product.domain.StoreReviewRepository;
import com.delivery.product.domain.StoreReviewRepository.RatingAggregate;
import com.delivery.product.service.CatalogService.CatalogRuleViolationException;
import com.delivery.product.service.StoreService.StoreNotFoundException;

/**
 * Reviews, and the store rating derived from them.
 *
 * <p>The rating on {@code stores} is denormalised so a storefront card does not run an aggregate
 * per shop — but it is always <em>recomputed</em> from the reviews on every write, never
 * incremented. An incremental average silently drifts the first time a review is edited or removed,
 * and nothing ever notices.
 */
@Service
public class ReviewService {

    private static final Logger log = LoggerFactory.getLogger(ReviewService.class);

    private final StoreReviewRepository reviews;
    private final StoreRepository stores;
    private final ReviewableOrderRepository reviewableOrders;

    public ReviewService(StoreReviewRepository reviews, StoreRepository stores,
                         ReviewableOrderRepository reviewableOrders) {
        this.reviews = reviews;
        this.stores = stores;
        this.reviewableOrders = reviewableOrders;
    }

    @Transactional(readOnly = true)
    public Page<StoreReview> forStore(UUID storeId, Pageable pageable) {
        return reviews.findByStoreIdOrderByCreatedAtDesc(storeId, pageable);
    }

    /** Whether this order has already been reviewed, so the app can offer "rate" or "edit". */
    @Transactional(readOnly = true)
    public Optional<StoreReview> forOrder(UUID orderId) {
        return reviews.findByOrderId(orderId);
    }

    /**
     * Rates an order, or revises an existing rating.
     *
     * <p>Upsert rather than insert-only: a customer changing their mind is ordinary, and the unique
     * constraint on {@code order_id} would otherwise turn it into a 409 they cannot act on.
     *
     * <p>The order must be one this customer actually had delivered from this shop. That fact lives
     * in order-manager and this service cannot see that schema, so it is checked against the local
     * {@link ReviewableOrder} projection built from {@code order.delivered} — the shape this method's
     * earlier note argued for. Until it existed the endpoint trusted the caller entirely: any token
     * plus an invented UUID bought a five-star review of your own shop, or a one-star review of a
     * competitor's, repeatedly. Ratings drive the storefront ranking, so that was not cosmetic.
     *
     * <p>A projection rather than a call to order-manager, because this runs on the write path and
     * a synchronous dependency would take reviews down whenever that service restarted — to confirm
     * a fact that cannot change after delivery.
     */
    @Transactional
    public StoreReview rate(UUID storeId, String customerId, UUID orderId, int rating,
                            String comment) {
        Store store = stores.findById(storeId)
                .orElseThrow(() -> new StoreNotFoundException(storeId.toString()));

        requireDeliveredOrder(storeId, customerId, orderId);

        StoreReview review = reviews.findByOrderId(orderId).orElse(null);
        try {
            if (review == null) {
                review = reviews.save(
                        new StoreReview(storeId, customerId, orderId, rating, comment));
            } else {
                if (!review.isBy(customerId)) {
                    // Someone else's order. 404-shaped rather than 403: confirming the order exists
                    // would leak that it does.
                    throw new OrderNotFoundException(orderId);
                }
                review.revise(rating, comment);
            }
        } catch (IllegalArgumentException e) {
            throw new CatalogRuleViolationException(e.getMessage());
        }

        recomputeRating(store);
        return review;
    }

    @Transactional
    public void delete(UUID orderId, String customerId) {
        reviews.findByOrderId(orderId).ifPresent(review -> {
            if (!review.isBy(customerId)) {
                throw new OrderNotFoundException(orderId);
            }
            UUID storeId = review.getStoreId();
            reviews.delete(review);
            // Flushed so the aggregate below does not still count the row just removed.
            reviews.flush();
            stores.findById(storeId).ifPresent(this::recomputeRating);
        });
    }

    /**
     * The one place the "you have to have bought it" rule is applied.
     *
     * <p>Refused as a not-found on the order rather than a forbidden, matching the rest of this
     * service: telling a caller that an order id exists but is not theirs is itself a fact about
     * somebody else, and it is obtainable by guessing.
     *
     * <p>It answered about the <em>store</em> for a while — "Store &lt;orderId&gt; was not found" —
     * which was wrong twice over: the shop is right there in the storefront the customer is looking
     * at, and the id in the message was the order's. A customer told their shop does not exist has
     * nothing to do about an order they cannot rate.
     */
    private void requireDeliveredOrder(UUID storeId, String customerId, UUID orderId) {
        ReviewableOrder delivered = reviewableOrders.findById(orderId)
                .orElseThrow(() -> {
                    log.warn("Refusing a review for order {}: no delivered order on record", orderId);
                    return new OrderNotFoundException(orderId);
                });

        if (!delivered.allowsReviewBy(customerId, storeId)) {
            log.warn("Refusing a review for order {}: it is not this customer's order from this shop",
                    orderId);
            throw new OrderNotFoundException(orderId);
        }
    }

    private void recomputeRating(Store store) {
        RatingAggregate aggregate = reviews.aggregateFor(store.getId());
        Double average = aggregate == null ? null : aggregate.average();
        long count = aggregate == null || aggregate.count() == null ? 0 : aggregate.count();

        store.applyRating(average == null ? null : BigDecimal.valueOf(average), (int) count);
        log.debug("Store {} now rated {} from {} review(s)",
                store.getId(), store.getRating(), count);
    }

    /**
     * An order this customer cannot rate. Mapped to 404.
     *
     * <p>The wording is the careful part. It says the order was not found <em>among the caller's
     * own delivered orders</em>, which is true of a mistyped id, of an order still in the kitchen
     * and of somebody else's order alike — so the response is the same in all three cases and
     * cannot be used to discover that an id belongs to another customer.
     */
    public static class OrderNotFoundException extends RuntimeException {
        public OrderNotFoundException(UUID orderId) {
            super("Order " + orderId + " was not found among your delivered orders");
        }
    }
}
