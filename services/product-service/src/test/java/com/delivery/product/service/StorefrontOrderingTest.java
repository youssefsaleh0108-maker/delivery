package com.delivery.product.service;

import java.math.BigDecimal;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.List;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;

import com.delivery.product.domain.CategoryRepository;
import com.delivery.product.domain.ProductRepository;
import com.delivery.product.domain.Store;
import com.delivery.product.domain.StoreFavoriteRepository;
import com.delivery.product.domain.StoreOfferRepository;
import com.delivery.product.domain.StoreRepository;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * The order the customer's shop list comes back in.
 *
 * <p>The controller asks for {@code rating DESC} and stops there, which quietly means two things
 * it does not intend.
 *
 * <p><strong>Unrated shops came first.</strong> SQL puts nulls first on a descending column, and a
 * shop nobody has reviewed has a null rating — so the top of the storefront was the shops with no
 * reviews at all. On the dev environment that was three unrated shops sitting above a 4.9, which
 * is the exact opposite of what "best first" promises a customer, and it was visible on the first
 * screen of the app.
 *
 * <p><strong>And ties made rows repeat and disappear.</strong> Paging over a non-unique sort key
 * leaves the order within a tie undefined, so the database may return a tied row on page one and
 * again on page two — and never return another one at all. That is not exotic: the same
 * environment had three shops tied at null and two tied at 4.8. A merchant whose shop falls in
 * the gap gets no orders from browsing and nothing anywhere reports a fault.
 *
 * <p>Both are asserted on the {@link Pageable} the service hands the repository, because that is
 * where the decision is made; whether Hibernate then emits NULLS LAST is Hibernate's contract,
 * not this service's.
 */
@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
class StorefrontOrderingTest {

    @Mock private StoreRepository stores;
    @Mock private StoreOfferRepository offers;
    @Mock private StoreFavoriteRepository favorites;
    @Mock private ProductRepository products;
    @Mock private CategoryRepository categories;

    private StoreService service;

    // Built here, not as a field initialiser: those run before Mockito injects the @Mock fields,
    // so the service would be constructed with six nulls and every test would fail on the first
    // call with an NPE about the repository rather than about anything it was asking.
    @BeforeEach
    void setUp() {
        service = new StoreService(stores, offers, favorites, products, categories,
                Clock.fixed(Instant.parse("2026-09-10T12:00:00Z"), ZoneOffset.UTC));
    }

    /** Runs a storefront read and hands back the Pageable the repository was actually given. */
    private Pageable pageableFor(Pageable asked) {
        when(stores.findStorefront(any(), any(), any(), any(), any(), any(), any()))
                .thenReturn(Page.empty());
        service.storefront(null, null, null, null, null, null, asked);

        ArgumentCaptor<Pageable> used = ArgumentCaptor.forClass(Pageable.class);
        verify(stores).findStorefront(any(), any(), any(), any(), any(), any(), used.capture());
        return used.getValue();
    }

    @Test
    @DisplayName("a shop nobody has rated does not outrank a shop everybody loves")
    void unratedShopsSortLast() {
        Sort.Order rating = pageableFor(
                PageRequest.of(0, 20, Sort.by(Sort.Direction.DESC, "rating")))
                .getSort().getOrderFor("rating");

        assertThat(rating).isNotNull();
        assertThat(rating.getNullHandling())
                .as("nulls must sort last, or the storefront leads with the shops nobody has "
                        + "reviewed — which is what it did")
                .isEqualTo(Sort.NullHandling.NULLS_LAST);
        assertThat(rating.getDirection()).isEqualTo(Sort.Direction.DESC);
    }

    @Test
    @DisplayName("the page order is total, so no shop is shown twice and none is skipped")
    void tiesAreBrokenByAStableKey() {
        List<Sort.Order> order = pageableFor(
                PageRequest.of(1, 20, Sort.by(Sort.Direction.DESC, "rating")))
                .getSort().toList();

        assertThat(order).hasSize(2);
        assertThat(order.get(0).getProperty()).isEqualTo("rating");
        assertThat(order.get(1).getProperty())
                .as("without a unique tiebreaker the rows within a tie have no defined order "
                        + "across pages, so a tied shop can appear on two pages and another on "
                        + "none")
                .isEqualTo("id");
    }

    @Test
    @DisplayName("and the page the caller asked for is the page they get")
    void pagingIsPreserved() {
        Pageable used = pageableFor(PageRequest.of(3, 7, Sort.by(Sort.Direction.DESC, "rating")));

        assertThat(used.getPageNumber()).isEqualTo(3);
        assertThat(used.getPageSize()).isEqualTo(7);
    }

    @Test
    @DisplayName("a caller who sorts by something else is left alone")
    void otherSortsAreUntouched() {
        Pageable asked = PageRequest.of(0, 20, Sort.by(Sort.Direction.ASC, "name"));
        Pageable used = pageableFor(asked);

        assertThat(used)
                .as("only the rating default is completed; adding an id tiebreaker to every sort "
                        + "in the app would be a wider change than this bug justifies")
                .isEqualTo(asked);
    }

    @Test
    @DisplayName("the filters still reach the query untouched")
    void filtersArePassedThrough() {
        when(stores.findStorefront(any(), any(), any(), any(), any(), any(), any()))
                .thenReturn(Page.empty());

        service.storefront(Store.Vertical.RESTAURANT, null, new BigDecimal("3.00"), 40,
                new BigDecimal("4.0"), "Hamra",
                PageRequest.of(0, 20, Sort.by(Sort.Direction.DESC, "rating")));

        verify(stores).findStorefront(eq(Store.Vertical.RESTAURANT), any(),
                eq(new BigDecimal("3.00")), eq(40), eq(new BigDecimal("4.0")), eq("Hamra"), any());
    }
}
