package com.delivery.product.service;

import java.util.List;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.mock.env.MockEnvironment;

import com.delivery.platform.outbox.OutboxRecorder;
import com.delivery.product.domain.CategoryRepository;
import com.delivery.product.domain.ProductOptionGroupRepository;
import com.delivery.product.domain.ProductRepository;
import com.delivery.product.domain.ServiceTermsRepository;
import com.delivery.product.domain.StoreDeliveryZoneRepository;
import com.delivery.product.domain.StoreRepository;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyBoolean;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * A shop's shelf searched for a term ({@link CatalogService#browseStore}): the term as it is run, and
 * the words the query is given. What the query does with them is SQL, which
 * {@code ItemSearchDatabaseTest} checks.
 */
@DisplayName("searching a shop's shelf")
class ShelfSearchTest {

    private ProductRepository products;
    private CatalogService catalog;

    @BeforeEach
    void setUp() {
        products = mock(ProductRepository.class);
        catalog = new CatalogService(products, mock(CategoryRepository.class), mock(StoreService.class),
                mock(OutboxRecorder.class), mock(StoreRepository.class), mock(ServiceTermsRepository.class),
                mock(StoreDeliveryZoneRepository.class), mock(ProductOptionGroupRepository.class),
                new ServiceCategories(new MockEnvironment()));
        when(products.findActiveInStoreMatching(any(), anyBoolean(), any(), anyString(), anyString(),
                anyString(), any(Pageable.class))).thenReturn(Page.empty());
    }

    /**
     * Each product of the shop is checked against each word of the term, so the term's length is the one
     * cost a caller controls: 4 KB of one-letter words took 0.28 s for a 500-product shop.
     */
    @Test
    @DisplayName("a term is cut to its first hundred characters, never through an emoji")
    void a_term_is_cut_to_a_hundred_characters() {
        assertThat(CatalogService.shelfTerm("  pepsi  ")).isEqualTo("pepsi");
        assertThat(CatalogService.shelfTerm("p".repeat(100))).hasSize(100);
        assertThat(CatalogService.shelfTerm("a b ".repeat(1024))).isEqualTo("a b ".repeat(25).trim());
        String cup = new String(Character.toChars(0x1F964));
        String cut = CatalogService.shelfTerm(cup.repeat(150));
        assertThat(cut.codePointCount(0, cut.length())).isEqualTo(100);
        assertThat(cut).isEqualTo(cup.repeat(100));
    }

    @Test
    @DisplayName("the shelf is searched for the cut term, folded by the database, its words longest first")
    void the_shelf_query_is_given_the_cut_term_and_its_words() {
        String longTerm = "Nido Full Cream " + "x".repeat(200);
        String cut = CatalogService.shelfTerm(longTerm);
        when(products.foldForSearch(cut, "", "")).thenReturn(List.of("nido full cream " + "x".repeat(84), "", ""));
        UUID shop = UUID.randomUUID();

        catalog.browseStore(shop, "customer-sub", null, longTerm, PageRequest.of(0, 20));

        verify(products).foldForSearch(cut, "", "");
        verify(products).findActiveInStoreMatching(eq(shop), eq(false), eq(shop),
                eq("nido full cream " + "x".repeat(84)), eq("x".repeat(84) + " cream nido full"),
                eq(SearchPatterns.like(cut)), eq(PageRequest.of(0, 20)));
    }
}
