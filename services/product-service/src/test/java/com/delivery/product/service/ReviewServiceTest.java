package com.delivery.product.service;

import java.time.Instant;
import java.util.Optional;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import com.delivery.product.domain.ReviewableOrder;
import com.delivery.product.domain.ReviewableOrderRepository;
import com.delivery.product.domain.Store;
import com.delivery.product.domain.StoreRepository;
import com.delivery.product.domain.StoreReview;
import com.delivery.product.domain.StoreReviewRepository;
import com.delivery.product.service.CatalogService.CatalogRuleViolationException;
import com.delivery.product.service.StoreService.StoreNotFoundException;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Who may rate a shop, and how the rating on the card is kept honest.
 *
 * <p>The rule that carries the most weight is that a review has to correspond to an order this
 * customer actually had delivered from this shop. Without it, the endpoint took the caller's word:
 * any valid token plus an invented UUID was a five-star review of your own shop, or a one-star
 * review of a competitor's, as many times as you cared to send it. Ratings drive the storefront
 * ranking, so an unverified review endpoint is a way to reorder the marketplace.
 */
class ReviewServiceTest {

    private static final UUID ORDER = UUID.randomUUID();
    private static final String CUSTOMER = "customer-sub";

    private StoreReviewRepository reviews;
    private StoreRepository stores;
    private ReviewableOrderRepository reviewableOrders;
    private ReviewService service;
    private Store store;

    /** The store's own generated id — the rating is recomputed against it, not against a constant. */
    private UUID STORE;

    @BeforeEach
    void setUp() {
        reviews = mock(StoreReviewRepository.class);
        stores = mock(StoreRepository.class);
        reviewableOrders = mock(ReviewableOrderRepository.class);
        service = new ReviewService(reviews, stores, reviewableOrders);

        store = new Store("merchant-sub", "Beirut Grill", Store.Vertical.RESTAURANT);
        STORE = store.getId();
        when(stores.findById(STORE)).thenReturn(Optional.of(store));
        when(reviews.findByOrderId(any(UUID.class))).thenReturn(Optional.empty());
        when(reviews.save(any(StoreReview.class))).thenAnswer(call -> call.getArgument(0));
        when(reviews.aggregateFor(any(UUID.class))).thenReturn(aggregate(4.5, 2L));

        deliveredTo(CUSTOMER, STORE);
    }

    /** Records that this customer had this order delivered from this shop. */
    private void deliveredTo(String customerId, UUID storeId) {
        when(reviewableOrders.findById(ORDER)).thenReturn(Optional.of(
                new ReviewableOrder(ORDER, storeId, customerId, Instant.now())));
    }

    private static StoreReviewRepository.RatingAggregate aggregate(Double average, Long count) {
        return new StoreReviewRepository.RatingAggregate(average, count);
    }

    @Nested
    @DisplayName("who may leave a review")
    class Eligibility {

        @Test
        void a_customer_may_rate_an_order_they_had_delivered() {
            StoreReview review = service.rate(STORE, CUSTOMER, ORDER, 5, "Excellent");

            assertThat(review.getRating()).isEqualTo((short) 5);
            verify(reviews).save(any(StoreReview.class));
        }

        /** The invented-order-id attack: a token plus a random UUID used to be enough. */
        @Test
        void an_order_that_was_never_delivered_cannot_be_rated() {
            when(reviewableOrders.findById(ORDER)).thenReturn(Optional.empty());

            assertThatThrownBy(() -> service.rate(STORE, CUSTOMER, ORDER, 5, "Padding my own shop"))
                    .isInstanceOf(StoreNotFoundException.class);

            verify(reviews, never()).save(any(StoreReview.class));
        }

        /** Somebody else's genuine order is not a licence to rate on their behalf. */
        @Test
        void another_customers_order_cannot_be_rated() {
            deliveredTo("someone-else", STORE);

            assertThatThrownBy(() -> service.rate(STORE, CUSTOMER, ORDER, 1, "Sabotage"))
                    .isInstanceOf(StoreNotFoundException.class);

            verify(reviews, never()).save(any(StoreReview.class));
        }

        /**
         * The attack that needs no forged id at all: point a genuine order of your own at a shop you
         * never bought from.
         */
        @Test
        void a_real_order_cannot_be_aimed_at_a_shop_it_did_not_come_from() {
            deliveredTo(CUSTOMER, UUID.randomUUID());

            assertThatThrownBy(() -> service.rate(STORE, CUSTOMER, ORDER, 1, "Competitor"))
                    .isInstanceOf(StoreNotFoundException.class);

            verify(reviews, never()).save(any(StoreReview.class));
        }

        /** Confirming that an order id exists is itself a fact about somebody else. */
        @Test
        void an_ineligible_review_is_refused_as_not_found_rather_than_forbidden() {
            deliveredTo("someone-else", STORE);

            assertThatThrownBy(() -> service.rate(STORE, CUSTOMER, ORDER, 1, null))
                    .isInstanceOf(StoreNotFoundException.class)
                    .hasMessageContaining(ORDER.toString());
        }

        @Test
        void a_shop_that_does_not_exist_cannot_be_rated() {
            when(stores.findById(STORE)).thenReturn(Optional.empty());

            assertThatThrownBy(() -> service.rate(STORE, CUSTOMER, ORDER, 5, null))
                    .isInstanceOf(StoreNotFoundException.class);
        }
    }

    @Nested
    @DisplayName("revising a review")
    class Revising {

        private StoreReview existing(String byCustomer) {
            StoreReview review = new StoreReview(STORE, byCustomer, ORDER, 2, "Was cold");
            when(reviews.findByOrderId(ORDER)).thenReturn(Optional.of(review));
            return review;
        }

        /** Changing your mind is ordinary; the unique constraint would otherwise be a dead end. */
        @Test
        void a_customer_may_revise_their_own_review() {
            StoreReview review = existing(CUSTOMER);

            service.rate(STORE, CUSTOMER, ORDER, 5, "They sorted it out");

            assertThat(review.getRating()).isEqualTo((short) 5);
            assertThat(review.getComment()).isEqualTo("They sorted it out");
        }

        @Test
        void revising_does_not_create_a_second_review() {
            existing(CUSTOMER);

            service.rate(STORE, CUSTOMER, ORDER, 5, "Better");

            verify(reviews, never()).save(any(StoreReview.class));
        }

        @Test
        void another_customer_cannot_revise_it() {
            existing("someone-else");
            deliveredTo("someone-else", STORE);

            assertThatThrownBy(() -> service.rate(STORE, CUSTOMER, ORDER, 1, "Sabotage"))
                    .isInstanceOf(StoreNotFoundException.class);
        }
    }

    @Nested
    @DisplayName("the rating on the card")
    class Rating {

        /**
         * Recomputed, never incremented. An incremental average drifts the first time a review is
         * edited or removed, and nothing ever notices.
         */
        @Test
        void is_recomputed_from_the_reviews_on_every_write() {
            service.rate(STORE, CUSTOMER, ORDER, 5, null);

            verify(reviews).aggregateFor(STORE);
            assertThat(store.getRating()).isEqualByComparingTo("4.5");
            assertThat(store.getRatingCount()).isEqualTo(2);
        }

        @Test
        void is_rounded_to_one_decimal_place() {
            when(reviews.aggregateFor(STORE)).thenReturn(aggregate(4.26, 3L));

            service.rate(STORE, CUSTOMER, ORDER, 5, null);

            assertThat(store.getRating()).isEqualByComparingTo("4.3");
        }

        /**
         * The storefront has to be able to tell "nobody has rated this" from "everybody rated it
         * badly", so an absent average stays null rather than becoming zero.
         */
        @Test
        void an_unrated_shop_reads_as_null_rather_than_zero() {
            when(reviews.aggregateFor(STORE)).thenReturn(aggregate(null, 0L));

            service.rate(STORE, CUSTOMER, ORDER, 5, null);

            assertThat(store.getRating()).isNull();
            assertThat(store.getRatingCount()).isZero();
        }

        @Test
        void a_shop_with_no_aggregate_row_at_all_is_handled() {
            when(reviews.aggregateFor(STORE)).thenReturn(null);

            service.rate(STORE, CUSTOMER, ORDER, 5, null);

            assertThat(store.getRating()).isNull();
        }
    }

    @Nested
    @DisplayName("deleting a review")
    class Deleting {

        @Test
        void a_customer_may_delete_their_own_and_the_rating_is_recomputed() {
            StoreReview review = new StoreReview(STORE, CUSTOMER, ORDER, 2, "Was cold");
            when(reviews.findByOrderId(ORDER)).thenReturn(Optional.of(review));

            service.delete(ORDER, CUSTOMER);

            verify(reviews).delete(review);
            // Flushed first, or the aggregate still counts the row just removed.
            verify(reviews).flush();
            verify(reviews).aggregateFor(STORE);
        }

        @Test
        void another_customer_cannot_delete_it() {
            StoreReview review = new StoreReview(STORE, "someone-else", ORDER, 2, null);
            when(reviews.findByOrderId(ORDER)).thenReturn(Optional.of(review));

            assertThatThrownBy(() -> service.delete(ORDER, CUSTOMER))
                    .isInstanceOf(StoreNotFoundException.class);

            verify(reviews, never()).delete(any(StoreReview.class));
        }

        /** Deleting something that is not there is success, not an error. */
        @Test
        void deleting_a_review_that_does_not_exist_is_silent() {
            when(reviews.findByOrderId(ORDER)).thenReturn(Optional.empty());

            service.delete(ORDER, CUSTOMER);

            verify(reviews, never()).delete(any(StoreReview.class));
        }
    }

    @Nested
    @DisplayName("the rating value itself")
    class Validation {

        @Test
        void a_rating_outside_one_to_five_is_refused() {
            assertThatThrownBy(() -> service.rate(STORE, CUSTOMER, ORDER, 0, null))
                    .isInstanceOf(CatalogRuleViolationException.class);
            assertThatThrownBy(() -> service.rate(STORE, CUSTOMER, ORDER, 6, null))
                    .isInstanceOf(CatalogRuleViolationException.class);
        }

        @Test
        void both_ends_of_the_scale_are_accepted() {
            assertThat(service.rate(STORE, CUSTOMER, ORDER, 1, null).getRating()).isEqualTo((short) 1);
            assertThat(service.rate(STORE, CUSTOMER, ORDER, 5, null).getRating()).isEqualTo((short) 5);
        }

        /** A star rating with no words is the common case. */
        @Test
        void a_review_with_no_comment_is_fine() {
            assertThat(service.rate(STORE, CUSTOMER, ORDER, 4, null)).isNotNull();
        }
    }
}
