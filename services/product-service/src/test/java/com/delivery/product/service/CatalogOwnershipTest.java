package com.delivery.product.service;

import java.math.BigDecimal;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import com.delivery.platform.outbox.OutboxRecorder;
import com.delivery.product.api.dto.CatalogDtos.ProductRequest;
import com.delivery.product.domain.CategoryRepository;
import com.delivery.product.domain.Product;
import com.delivery.product.domain.ProductRepository;
import com.delivery.product.domain.Store;
import com.delivery.product.event.CatalogEvents;
import com.delivery.product.service.CatalogService.CatalogRuleViolationException;
import com.delivery.product.service.CatalogService.ProductNotFoundException;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Cross-merchant isolation, and the events that must commit with the row.
 *
 * <p>Every rule here is one that fails quietly when it breaks. A merchant editing a competitor's
 * product, a product filed into a competitor's storefront, an unpublished price readable by anyone
 * who can guess a UUID — none of these throw on their own, they just work, and the damage is only
 * visible from the other merchant's side.
 *
 * <p>The refusals are all "not found" rather than "forbidden" on purpose: a 403 confirms the id
 * exists, which is itself a fact about somebody else's catalog.
 */
class CatalogOwnershipTest {

    private static final String MERCHANT = "merchant-sub";
    private static final String OTHER = "other-merchant-sub";
    private static final UUID PRODUCT = UUID.randomUUID();

    private ProductRepository products;
    private CategoryRepository categories;
    private StoreService storeService;
    private OutboxRecorder outbox;
    private CatalogService catalog;

    @BeforeEach
    void setUp() {
        products = mock(ProductRepository.class);
        categories = mock(CategoryRepository.class);
        storeService = mock(StoreService.class);
        outbox = mock(OutboxRecorder.class);
        catalog = new CatalogService(products, categories, storeService, outbox);

        when(products.save(any(Product.class))).thenAnswer(call -> call.getArgument(0));
        when(categories.existsById(any(UUID.class))).thenReturn(true);
        when(products.existsById(any(UUID.class))).thenReturn(false);
        when(products.findByIdAndMerchantId(any(UUID.class), anyString()))
                .thenReturn(Optional.empty());
    }

    private Product ownedBy(String merchantId) {
        Product product = new Product(merchantId, UUID.randomUUID(), "Falafel wrap",
                "With pickles", new BigDecimal("6.50"), null);
        // A product cannot be published without an image, and several of these tests need one that
        // reaches ACTIVE to check what a customer can see.
        product.addImage("products/x/photo.jpg");
        when(products.findByIdAndMerchantId(PRODUCT, merchantId)).thenReturn(Optional.of(product));
        when(products.findById(PRODUCT)).thenReturn(Optional.of(product));
        when(products.existsById(PRODUCT)).thenReturn(true);
        return product;
    }

    private static ProductRequest request(UUID storeId) {
        return new ProductRequest("Falafel wrap", "With pickles", new BigDecimal("6.50"),
                null, storeId);
    }

    @Nested
    @DisplayName("writing to a product")
    class Writes {

        @Test
        void the_owning_merchant_may_update_it() {
            Product product = ownedBy(MERCHANT);

            catalog.update(PRODUCT, MERCHANT, request(null));

            assertThat(product.getName()).isEqualTo("Falafel wrap");
        }

        @Test
        void another_merchant_may_not_update_it() {
            ownedBy(MERCHANT);

            assertThatThrownBy(() -> catalog.update(PRODUCT, OTHER, request(null)))
                    .isInstanceOf(ProductNotFoundException.class);
        }

        @Test
        void another_merchant_may_not_publish_it() {
            ownedBy(MERCHANT);

            assertThatThrownBy(() -> catalog.publish(PRODUCT, OTHER))
                    .isInstanceOf(ProductNotFoundException.class);
        }

        /** Archiving somebody else's product would take a competitor's item off sale. */
        @Test
        void another_merchant_may_not_archive_it() {
            ownedBy(MERCHANT);

            assertThatThrownBy(() -> catalog.archive(PRODUCT, OTHER))
                    .isInstanceOf(ProductNotFoundException.class);
        }

        /** A refused write must not emit an event either — consumers would act on a change that
         *  never happened. */
        @Test
        void a_refused_write_records_no_event() {
            ownedBy(MERCHANT);

            assertThatThrownBy(() -> catalog.update(PRODUCT, OTHER, request(null)))
                    .isInstanceOf(ProductNotFoundException.class);

            verify(outbox, never()).record(anyString(), anyString(), anyString(), any());
        }

        /** The same answer whether the product exists or belongs to someone else. */
        @Test
        void a_product_that_does_not_exist_is_refused_identically() {
            UUID missing = UUID.randomUUID();
            when(products.existsById(missing)).thenReturn(false);

            assertThatThrownBy(() -> catalog.update(missing, MERCHANT, request(null)))
                    .isInstanceOf(ProductNotFoundException.class);
        }
    }

    @Nested
    @DisplayName("reading a product")
    class Reads {

        @Test
        void an_active_product_is_readable_by_anyone() {
            Product product = ownedBy(MERCHANT);
            product.publish();

            assertThat(catalog.read(PRODUCT, "some-customer")).isSameAs(product);
        }

        /** Otherwise a customer could enumerate ids and read pricing that is not live yet. */
        @Test
        void a_draft_product_is_hidden_from_everyone_but_its_owner() {
            ownedBy(MERCHANT);

            assertThatThrownBy(() -> catalog.read(PRODUCT, "some-customer"))
                    .isInstanceOf(ProductNotFoundException.class);
        }

        @Test
        void a_draft_product_is_readable_by_its_owner() {
            Product product = ownedBy(MERCHANT);

            assertThat(catalog.read(PRODUCT, MERCHANT)).isSameAs(product);
        }

        @Test
        void an_archived_product_is_hidden_from_customers_but_visible_to_its_owner() {
            Product product = ownedBy(MERCHANT);
            product.publish();
            product.archive();

            assertThatThrownBy(() -> catalog.read(PRODUCT, "some-customer"))
                    .isInstanceOf(ProductNotFoundException.class);
            assertThat(catalog.read(PRODUCT, MERCHANT)).isSameAs(product);
        }

        /** An unauthenticated viewer is not the owner of anything. */
        @Test
        void an_anonymous_viewer_cannot_see_a_draft() {
            ownedBy(MERCHANT);

            assertThatThrownBy(() -> catalog.read(PRODUCT, null))
                    .isInstanceOf(ProductNotFoundException.class);
        }
    }

    @Nested
    @DisplayName("creating a product")
    class Creating {

        private Store storeOwnedBy(String merchantId) {
            Store store = new Store(merchantId, "Their shop", Store.Vertical.RESTAURANT);
            when(storeService.ownedBy(merchantId)).thenReturn(List.of(store));
            return store;
        }

        @Test
        void lands_in_the_merchants_own_store_when_one_is_named() {
            Store mine = storeOwnedBy(MERCHANT);

            Product created = catalog.create(MERCHANT, request(mine.getId()));

            assertThat(created.getStoreId()).isEqualTo(mine.getId());
            assertThat(created.getMerchantId()).isEqualTo(MERCHANT);
        }

        /**
         * The same class of hole that keeping merchantId out of the request body closes for
         * products: without the check, passing a competitor's store id files your product on their
         * shopfront.
         */
        @Test
        void cannot_be_filed_into_another_merchants_store() {
            Store theirs = new Store(OTHER, "Their shop", Store.Vertical.RESTAURANT);
            when(storeService.ownedBy(MERCHANT)).thenReturn(List.of());

            assertThatThrownBy(() -> catalog.create(MERCHANT, request(theirs.getId())))
                    .isInstanceOf(CatalogRuleViolationException.class)
                    .hasMessageContaining("not yours");

            verify(products, never()).save(any(Product.class));
        }

        /** "Add your first product" must not need "but first create a store" wired into the client. */
        @Test
        void a_merchant_with_no_store_yet_gets_one_provisioned() {
            Store provisioned = new Store(MERCHANT, "My Store", Store.Vertical.RESTAURANT);
            when(storeService.requireStoreFor(MERCHANT)).thenReturn(provisioned);

            assertThat(catalog.create(MERCHANT, request(null)).getStoreId())
                    .isEqualTo(provisioned.getId());
        }

        @Test
        void a_category_that_does_not_exist_is_refused() {
            UUID unknown = UUID.randomUUID();
            when(categories.existsById(unknown)).thenReturn(false);
            when(storeService.requireStoreFor(MERCHANT))
                    .thenReturn(new Store(MERCHANT, "My Store", Store.Vertical.RESTAURANT));

            assertThatThrownBy(() -> catalog.create(MERCHANT,
                    new ProductRequest("n", "d", BigDecimal.ONE, unknown, null)))
                    .isInstanceOf(CatalogRuleViolationException.class);

            verify(products, never()).save(any(Product.class));
        }
    }

    @Nested
    @DisplayName("events")
    class Events {

        @Test
        void a_create_records_a_created_event() {
            when(storeService.requireStoreFor(MERCHANT))
                    .thenReturn(new Store(MERCHANT, "My Store", Store.Vertical.RESTAURANT));

            catalog.create(MERCHANT, request(null));

            verify(outbox).record(eq(CatalogEvents.AGGREGATE_TYPE), anyString(),
                    eq(CatalogEvents.PRODUCT_CREATED), any());
        }

        @Test
        void each_lifecycle_change_records_its_own_event() {
            ownedBy(MERCHANT);

            catalog.update(PRODUCT, MERCHANT, request(null));
            verify(outbox).record(anyString(), anyString(), eq(CatalogEvents.PRODUCT_UPDATED), any());

            catalog.publish(PRODUCT, MERCHANT);
            verify(outbox).record(anyString(), anyString(), eq(CatalogEvents.PRODUCT_PUBLISHED), any());

            catalog.archive(PRODUCT, MERCHANT);
            verify(outbox).record(anyString(), anyString(), eq(CatalogEvents.PRODUCT_ARCHIVED), any());
        }

        /** The event is keyed on the product so a consumer can tell which one changed. */
        @Test
        void the_event_names_the_product_it_is_about() {
            Product product = ownedBy(MERCHANT);

            catalog.publish(PRODUCT, MERCHANT);

            verify(outbox).record(eq(CatalogEvents.AGGREGATE_TYPE),
                    eq(product.getId().toString()), anyString(), any());
        }
    }

    @Nested
    @DisplayName("categories")
    class Categories {

        @Test
        void a_child_category_needs_a_parent_that_exists() {
            UUID missing = UUID.randomUUID();
            when(categories.existsById(missing)).thenReturn(false);

            assertThatThrownBy(() -> catalog.createCategory("Wraps", missing))
                    .isInstanceOf(CatalogRuleViolationException.class)
                    .hasMessageContaining("does not exist");
        }

        @Test
        void a_root_category_needs_no_parent() {
            when(categories.save(any())).thenAnswer(call -> call.getArgument(0));

            assertThat(catalog.createCategory("Food", null)).isNotNull();
        }
    }
}
