package com.delivery.product.service;

import java.math.BigDecimal;
import java.time.Clock;
import java.time.DayOfWeek;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalTime;
import java.time.ZoneOffset;
import java.util.Arrays;
import java.util.Collection;
import java.util.List;
import java.util.Optional;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.mock.env.MockEnvironment;

import com.delivery.platform.storage.StorageService;
import com.delivery.product.api.dto.BannerDtos.BannerRequest;
import com.delivery.product.domain.TestPin;
import com.delivery.product.domain.Banner;
import com.delivery.product.domain.BannerRepository;
import com.delivery.product.domain.Category;
import com.delivery.product.domain.CategoryRepository;
import com.delivery.product.domain.Product;
import com.delivery.product.domain.ProductRepository;
import com.delivery.product.domain.Store;
import com.delivery.product.domain.StoreFavoriteRepository;
import com.delivery.product.domain.StoreHours;
import com.delivery.product.domain.StoreOfferRepository;
import com.delivery.product.domain.StoreRepository;
import com.delivery.product.service.CatalogService.CatalogRuleViolationException;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Service shops stay off every goods surface unless a read asks for them by name.
 *
 * <p>The failure this guards against is silent. An app built before the services marketplace reads
 * an unknown vertical as RESTAURANT, so a print shop that reached the Home storefront, the Home strip,
 * a banner or the gift hub would be drawn on an installed phone as a restaurant, and nothing on the
 * server would report it. Each surface is pinned here, where its decision is made. "Near me" is
 * pinned beside the rest of the nearby search in {@code NearbyStoreSearchTest}. The SQL that stands
 * behind the queries is run against a real database by {@code ServicesVerticalDatabaseTest}, because
 * a mock can show which query was asked but not what it answers.
 */
@DisplayName("service shops stay off the goods storefront")
class ServicesStorefrontIsolationTest {

    private static final Instant NOW = Instant.parse("2026-09-13T10:00:00Z");

    private static final Pageable FIRST_PAGE = PageRequest.of(0, 20);

    /** Listed and open all week, as a shop on a customer's screen would be. */
    private static Store listed(Store store) {
        store.replaceHours(Arrays.stream(DayOfWeek.values())
                .map(day -> new StoreHours(day, LocalTime.MIDNIGHT, LocalTime.of(23, 59, 59)))
                .toList());
        TestPin.pinned(store);
        store.publish(NOW.minus(Duration.ofDays(30)));
        return store;
    }

    private static Store printShop() {
        return listed(new Store("merchant-press", "Al Fakhry Press", Store.Vertical.SERVICES,
                Store.ServiceCategory.PRINTING));
    }

    private static Store grocer() {
        return listed(new Store("merchant-grocer", "Abu Hassan Mini Market", Store.Vertical.GROCERY));
    }

    @Nested
    @DisplayName("the storefront and its search")
    class Storefront {

        private StoreRepository stores;
        private MockEnvironment environment;
        private StoreService service;

        @BeforeEach
        void setUp() {
            stores = mock(StoreRepository.class);
            environment = new MockEnvironment();
            service = new StoreService(stores, mock(StoreOfferRepository.class),
                    mock(StoreFavoriteRepository.class), mock(ProductRepository.class),
                    mock(CategoryRepository.class), new ServiceCategories(environment),
                    mock(OnboardingApplicationClient.class),
                    Clock.fixed(NOW, ZoneOffset.UTC), Duration.ofHours(4), "Asia/Beirut");
            when(stores.findStorefront(any(), any(), any(), any(), any(), any(), any()))
                    .thenReturn(Page.empty());
            when(stores.findServicesStorefront(any(), any(), any(), any(), any(), any(), any()))
                    .thenReturn(Page.empty());
        }

        /** The categories the services query was asked for. */
        @SuppressWarnings("unchecked")
        private Collection<Store.ServiceCategory> servicesQueryCategories() {
            ArgumentCaptor<Collection<Store.ServiceCategory>> asked =
                    ArgumentCaptor.forClass(Collection.class);
            verify(stores).findServicesStorefront(asked.capture(), any(), any(), any(), any(), any(),
                    any());
            return asked.getValue();
        }

        private void neitherQueryWasAsked() {
            verify(stores, never()).findStorefront(any(), any(), any(), any(), any(), any(), any());
            verify(stores, never())
                    .findServicesStorefront(any(), any(), any(), any(), any(), any(), any());
        }

        /**
         * Home, its search and every installed app send no vertical. That read goes to the goods
         * query, whose WHERE refuses service shops, and never to the services one.
         */
        @Test
        void a_read_naming_no_vertical_is_the_goods_storefront() {
            service.storefront(null, null, "fakhry", null, null, null, null, FIRST_PAGE);
            service.storefront(null, "fakhry", null, null, null, null, FIRST_PAGE);

            org.mockito.Mockito.verify(stores, org.mockito.Mockito.times(2))
                    .findStorefront(isNull(), any(), any(), any(), any(), any(), any());
            verify(stores, never())
                    .findServicesStorefront(any(), any(), any(), any(), any(), any(), any());
        }

        @Test
        void a_goods_vertical_is_that_vertical_as_it_always_was() {
            service.storefront(Store.Vertical.GROCERY, null, null, null, null, null, null, FIRST_PAGE);

            verify(stores).findStorefront(eq(Store.Vertical.GROCERY), any(), any(), any(), any(),
                    any(), any());
            verify(stores, never())
                    .findServicesStorefront(any(), any(), any(), any(), any(), any(), any());
        }

        @Test
        void services_lists_service_shops_in_the_open_categories_only() {
            service.storefront(Store.Vertical.SERVICES, null, null, null, null, null, null,
                    FIRST_PAGE);

            assertThat(servicesQueryCategories()).containsExactlyInAnyOrder(
                    Store.ServiceCategory.PRINTING, Store.ServiceCategory.TAILORING,
                    Store.ServiceCategory.REPAIRS, Store.ServiceCategory.PHOTOGRAPHY);
            verify(stores, never()).findStorefront(any(), any(), any(), any(), any(), any(), any());
        }

        @Test
        void a_service_category_on_its_own_asks_for_service_shops() {
            service.storefront(null, Store.ServiceCategory.PRINTING, null, null, null, null, null,
                    FIRST_PAGE);

            assertThat(servicesQueryCategories()).containsExactly(Store.ServiceCategory.PRINTING);
        }

        /** Owner default 1: Cleaning is in the taxonomy but closed, so it shows nothing. */
        @Test
        void a_closed_category_shows_nothing_even_when_asked_for_by_name() {
            Page<StoreService.StoreView> page = service.storefront(Store.Vertical.SERVICES,
                    Store.ServiceCategory.CLEANING, null, null, null, null, null, FIRST_PAGE);

            assertThat(page).isEmpty();
            neitherQueryWasAsked();
        }

        /** Filters narrow each other, and no goods shop has a service category. */
        @Test
        void a_goods_vertical_with_a_service_category_shows_nothing() {
            Page<StoreService.StoreView> page = service.storefront(Store.Vertical.GROCERY,
                    Store.ServiceCategory.PRINTING, null, null, null, null, null, FIRST_PAGE);

            assertThat(page).isEmpty();
            neitherQueryWasAsked();
        }

        @Test
        void opening_a_category_in_configuration_lists_it_without_a_redeploy() {
            environment.setProperty(ServiceCategories.PROPERTY, "PRINTING,CLEANING");

            service.storefront(Store.Vertical.SERVICES, Store.ServiceCategory.CLEANING, null, null,
                    null, null, null, FIRST_PAGE);

            assertThat(servicesQueryCategories()).containsExactly(Store.ServiceCategory.CLEANING);
        }

        /** The category setting is read only by services reads, so a typo in it spares Home. */
        @Test
        void a_typo_in_the_category_setting_cannot_take_home_down() {
            environment.setProperty(ServiceCategories.PROPERTY, "PRINTNG");

            service.storefront(null, null, null, null, null, null, null, FIRST_PAGE);
            verify(stores).findStorefront(isNull(), any(), any(), any(), any(), any(), any());

            assertThatThrownBy(() -> service.storefront(Store.Vertical.SERVICES, null, null, null,
                    null, null, null, FIRST_PAGE))
                    .isInstanceOf(IllegalStateException.class)
                    .hasMessageContaining("PRINTNG");
        }
    }

    @Nested
    @DisplayName("the Home strip and its banners")
    class HomeStrip {

        private BannerRepository banners;
        private CategoryRepository categories;
        private StoreRepository stores;
        private BannerService service;

        @BeforeEach
        void setUp() {
            banners = mock(BannerRepository.class);
            categories = mock(CategoryRepository.class);
            stores = mock(StoreRepository.class);
            service = new BannerService(banners, categories, stores, mock(StorageService.class),
                    Clock.fixed(NOW, ZoneOffset.UTC));
            when(banners.save(any(Banner.class))).thenAnswer(call -> call.getArgument(0));
        }

        private static Category tagged(String name, Store.Vertical vertical) {
            Category category = new Category(name, null);
            category.setVertical(vertical);
            return category;
        }

        /**
         * Nothing can write a Services chip today: setVertical refuses one, and V33 kept the category
         * CHECK without SERVICES. The row below is the one those two rules exist to prevent, and the
         * strip must stay right if either of them is ever loosened.
         */
        @Test
        void the_strip_never_shows_a_services_chip() {
            when(categories.findByStoreIdIsNull()).thenReturn(List.of(
                    tagged("Groceries", Store.Vertical.GROCERY),
                    tagged("Services", Store.Vertical.SERVICES),
                    tagged("Frozen", null)));

            assertThat(service.verticalCategories()).extracting(Category::getName)
                    .containsExactly("Groceries");
        }

        @Test
        void no_category_can_be_made_to_stand_for_services() {
            Category printing = new Category("Printing", null);
            when(categories.findById(printing.getId())).thenReturn(Optional.of(printing));

            assertThatThrownBy(() -> service.setVertical(printing.getId(), Store.Vertical.SERVICES))
                    .isInstanceOf(CatalogRuleViolationException.class)
                    .hasMessageContaining("Services tab");
            assertThat(printing.getVertical()).isNull();
        }

        @Test
        void a_banner_cannot_send_home_to_a_service_shop() {
            Store press = printShop();
            when(stores.findById(press.getId())).thenReturn(Optional.of(press));

            assertThatThrownBy(() -> service.create(new BannerRequest("Business cards, printed nearby",
                    null, Banner.LinkKind.STORE, press.getId().toString(), 1, true)))
                    .isInstanceOf(CatalogRuleViolationException.class)
                    .hasMessageContaining("Al Fakhry Press");
            verify(banners, never()).save(any(Banner.class));
        }

        @Test
        void a_banner_still_points_at_a_goods_shop() {
            Store grocer = grocer();
            when(stores.findById(grocer.getId())).thenReturn(Optional.of(grocer));

            Banner saved = service.create(new BannerRequest("Fresh bread every morning", null,
                    Banner.LinkKind.STORE, grocer.getId().toString(), 1, true));

            assertThat(saved.getLinkTarget()).isEqualTo(grocer.getId().toString());
        }
    }

    @Nested
    @DisplayName("the gift hub")
    class GiftHub {

        private ProductRepository products;
        private StoreRepository stores;
        private GiftBundleService gifts;

        @BeforeEach
        void setUp() {
            products = mock(ProductRepository.class);
            stores = mock(StoreRepository.class);
            gifts = new GiftBundleService(products, stores);
            when(products.save(any(Product.class))).thenAnswer(call -> call.getArgument(0));
        }

        private static Product liveProductOf(Store shop, String name) {
            Product product = new Product(shop.getMerchantId(), shop.getId(), name, null,
                    new BigDecimal("25.00"), null);
            product.addImage("products/" + name + ".jpg");
            product.publish();
            return product;
        }

        @Test
        void a_service_offer_never_reaches_the_hub() {
            Store press = printShop();
            Store grocer = grocer();
            Product cards = liveProductOf(press, "500 business cards");
            Product box = liveProductOf(grocer, "Family essentials box");
            when(products.findFeaturedGifts(any(Pageable.class))).thenReturn(List.of(cards, box));
            when(stores.findAllById(any())).thenReturn(List.of(press, grocer));

            assertThat(gifts.featured(NOW)).extracting(bundle -> bundle.product().getName())
                    .containsExactly("Family essentials box");
        }

        @Test
        void a_service_offer_cannot_be_featured() {
            Store press = printShop();
            Product cards = liveProductOf(press, "500 business cards");
            when(products.findById(cards.getId())).thenReturn(Optional.of(cards));
            when(stores.findById(press.getId())).thenReturn(Optional.of(press));

            assertThatThrownBy(() -> gifts.setFeatured(cards.getId(), true, "backoffice-sub", NOW))
                    .isInstanceOf(CatalogRuleViolationException.class)
                    .hasMessageContaining("not giftable");
            assertThat(cards.isGiftFeatured()).isFalse();
            verify(products, never()).save(any(Product.class));
        }
    }
}
