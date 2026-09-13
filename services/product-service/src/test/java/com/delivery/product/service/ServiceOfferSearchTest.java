package com.delivery.product.service;

import java.math.BigDecimal;
import java.util.Collection;
import java.util.List;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;
import org.springframework.mock.env.MockEnvironment;

import com.delivery.product.domain.DeliveredOrderLineRepository;
import com.delivery.product.domain.Product;
import com.delivery.product.domain.ProductRepository;
import com.delivery.product.domain.Store.ServiceCategory;
import com.delivery.product.service.ServiceOfferSearch.PopularOffer;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.tuple;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Which service offers a customer's read may reach: the categories it is scoped to, and the honesty of
 * "Popular".
 *
 * <p>What the queries return for a scope (ACTIVE offers of ACTIVE service shops only, never goods) is
 * proven against a real database in {@code ServiceOffersDatabaseTest}. This pins the scope handed to
 * them, and what happens around the counts.
 */
@DisplayName("the customer's reads of service offers")
class ServiceOfferSearchTest {

    private static final String OPEN_CATEGORIES = "delivery.product.services.enabled-categories";

    private ProductRepository products;
    private DeliveredOrderLineRepository deliveredLines;

    @BeforeEach
    void setUp() {
        products = mock(ProductRepository.class);
        deliveredLines = mock(DeliveredOrderLineRepository.class);
        when(products.findListedServiceOffers(any(), anyString(), any(Pageable.class)))
                .thenReturn(Page.empty());
    }

    private ServiceOfferSearch launchConfiguration() {
        return new ServiceOfferSearch(products, deliveredLines,
                new ServiceCategories(new MockEnvironment()), 3);
    }

    private ServiceOfferSearch withOpen(String categories, long popularFloor) {
        return new ServiceOfferSearch(products, deliveredLines,
                new ServiceCategories(new MockEnvironment().withProperty(OPEN_CATEGORIES, categories)),
                popularFloor);
    }

    @SuppressWarnings("unchecked")
    private Collection<ServiceCategory> searchedScope() {
        ArgumentCaptor<Collection<ServiceCategory>> scope = ArgumentCaptor.forClass(Collection.class);
        verify(products).findListedServiceOffers(scope.capture(), anyString(), any(Pageable.class));
        return scope.getValue();
    }

    private static Product live(String name) {
        Product product = new Product("provider-sub", UUID.randomUUID(), name, null,
                new BigDecimal("15.00"), null);
        product.addImage("products/" + name + ".jpg");
        product.publish();
        return product;
    }

    @Nested
    @DisplayName("search scoping")
    class Scoping {

        @Test
        void naming_no_category_searches_every_open_one_and_no_closed_one() {
            launchConfiguration().search("cards", null, PageRequest.of(0, 20));

            assertThat(searchedScope())
                    .containsExactlyInAnyOrder(ServiceCategory.PRINTING, ServiceCategory.TAILORING,
                            ServiceCategory.REPAIRS, ServiceCategory.PHOTOGRAPHY)
                    .doesNotContain(ServiceCategory.CLEANING, ServiceCategory.BEAUTY,
                            ServiceCategory.TUTORING);
        }

        @Test
        void an_open_category_named_is_the_only_one_searched() {
            launchConfiguration().search(null, ServiceCategory.PRINTING, PageRequest.of(0, 20));

            assertThat(searchedScope()).containsExactly(ServiceCategory.PRINTING);
        }

        @Test
        void a_closed_category_named_answers_nothing_without_asking_the_database() {
            Page<Product> page = launchConfiguration()
                    .search(null, ServiceCategory.CLEANING, PageRequest.of(0, 20));

            assertThat(page.getContent()).isEmpty();
            assertThat(page.getTotalElements()).isZero();
            verify(products, never()).findListedServiceOffers(any(), anyString(), any(Pageable.class));
        }

        @Test
        void a_category_opened_in_configuration_is_searched() {
            withOpen("PRINTING,CLEANING", 3).search(null, ServiceCategory.CLEANING, PageRequest.of(0, 20));

            assertThat(searchedScope()).containsExactly(ServiceCategory.CLEANING);
        }

        /** Present but blank is a decision somebody wrote down: every category closed. */
        @Test
        void every_category_closed_answers_nothing() {
            assertThat(withOpen("", 3).search("cards", null, PageRequest.of(0, 20))).isEmpty();

            verify(products, never()).findListedServiceOffers(any(), anyString(), any(Pageable.class));
        }

        @Test
        void pages_break_ties_by_id_after_the_callers_sort() {
            launchConfiguration().search(null, null,
                    PageRequest.of(2, 20, Sort.by(Sort.Direction.DESC, "createdAt")));

            ArgumentCaptor<Pageable> asked = ArgumentCaptor.forClass(Pageable.class);
            verify(products).findListedServiceOffers(any(), anyString(), asked.capture());
            assertThat(asked.getValue().getPageNumber()).isEqualTo(2);
            assertThat(asked.getValue().getSort()).containsExactly(
                    Sort.Order.desc("createdAt"), Sort.Order.asc("id"));
        }
    }

    @Nested
    @DisplayName("Popular")
    class Popular {

        @Test
        void lists_offers_by_their_delivered_orders_with_the_counts() {
            Product cards = live("Business cards");
            Product banner = live("Banner");
            when(deliveredLines.countDeliveredOrdersOfListedServiceOffers(any(), anyLong(),
                    any(Pageable.class)))
                    .thenReturn(List.of(new Object[] {cards.getId(), 7L},
                            new Object[] {banner.getId(), 3L}));
            when(products.findByIdIn(any())).thenReturn(List.of(banner, cards));

            List<PopularOffer> popular = launchConfiguration().popular(null, 10);

            assertThat(popular)
                    .extracting(p -> p.product().getName(), PopularOffer::deliveredOrders)
                    .containsExactly(tuple("Business cards", 7L), tuple("Banner", 3L));
        }

        @Test
        void asks_for_the_configured_floor_and_a_bounded_row() {
            withOpen("PRINTING", 5).popular(null, 500);

            verify(deliveredLines).countDeliveredOrdersOfListedServiceOffers(any(), eq(5L),
                    eq(PageRequest.of(0, ServiceOfferSearch.MAX_POPULAR)));
        }

        /** A misconfigured zero must not list offers nobody has ever received. */
        @Test
        void a_floor_of_zero_still_needs_one_delivered_order() {
            withOpen("PRINTING", 0).popular(null, 10);

            verify(deliveredLines).countDeliveredOrdersOfListedServiceOffers(any(), eq(1L),
                    any(Pageable.class));
        }

        @Test
        void without_enough_delivered_orders_it_is_empty_and_reads_no_offer() {
            when(deliveredLines.countDeliveredOrdersOfListedServiceOffers(any(), anyLong(),
                    any(Pageable.class))).thenReturn(List.of());

            assertThat(launchConfiguration().popular(null, 10)).isEmpty();

            verify(products, never()).findByIdIn(any());
        }

        @Test
        void an_offer_paused_after_it_was_counted_is_dropped_not_listed() {
            Product cards = live("Business cards");
            cards.pause();
            when(deliveredLines.countDeliveredOrdersOfListedServiceOffers(any(), anyLong(),
                    any(Pageable.class))).thenReturn(List.<Object[]>of(new Object[] {cards.getId(), 7L}));
            when(products.findByIdIn(any())).thenReturn(List.of(cards));

            assertThat(launchConfiguration().popular(null, 10)).isEmpty();
        }

        @Test
        void a_closed_category_has_no_popular_offers_and_counts_nothing() {
            assertThat(launchConfiguration().popular(ServiceCategory.BEAUTY, 10)).isEmpty();

            verify(deliveredLines, never()).countDeliveredOrdersOfListedServiceOffers(any(), anyLong(),
                    any(Pageable.class));
        }
    }
}
