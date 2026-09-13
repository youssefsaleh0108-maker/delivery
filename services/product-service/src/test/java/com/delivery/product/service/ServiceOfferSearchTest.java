package com.delivery.product.service;

import java.util.Collection;

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

import com.delivery.product.domain.Product;
import com.delivery.product.domain.ProductRepository;
import com.delivery.product.domain.Store.ServiceCategory;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Which service offers a search may reach: the categories it is scoped to.
 *
 * <p>What the query returns for a scope (ACTIVE offers of ACTIVE service shops only, never goods) is
 * proven against a real database in {@code ServiceOffersDatabaseTest}. This pins the scope handed to it.
 * The "Popular near you" row ranks shops, and is pinned in {@code PopularServiceShopsTest}.
 */
@DisplayName("the search of service offers")
class ServiceOfferSearchTest {

    private static final String OPEN_CATEGORIES = "delivery.product.services.enabled-categories";

    private ProductRepository products;

    @BeforeEach
    void setUp() {
        products = mock(ProductRepository.class);
        when(products.findListedServiceOffers(any(), anyString(), any(Pageable.class)))
                .thenReturn(Page.empty());
    }

    private ServiceOfferSearch launchConfiguration() {
        return new ServiceOfferSearch(products, new ServiceCategories(new MockEnvironment()));
    }

    private ServiceOfferSearch withOpen(String categories) {
        return new ServiceOfferSearch(products,
                new ServiceCategories(new MockEnvironment().withProperty(OPEN_CATEGORIES, categories)));
    }

    @SuppressWarnings("unchecked")
    private Collection<ServiceCategory> searchedScope() {
        ArgumentCaptor<Collection<ServiceCategory>> scope = ArgumentCaptor.forClass(Collection.class);
        verify(products).findListedServiceOffers(scope.capture(), anyString(), any(Pageable.class));
        return scope.getValue();
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
            withOpen("PRINTING,CLEANING").search(null, ServiceCategory.CLEANING, PageRequest.of(0, 20));

            assertThat(searchedScope()).containsExactly(ServiceCategory.CLEANING);
        }

        /** Present but blank is a decision somebody wrote down: every category closed. */
        @Test
        void every_category_closed_answers_nothing() {
            assertThat(withOpen("").search("cards", null, PageRequest.of(0, 20))).isEmpty();

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
}
