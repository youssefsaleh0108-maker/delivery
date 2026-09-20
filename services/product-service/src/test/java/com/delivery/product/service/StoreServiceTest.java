package com.delivery.product.service;

import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.Arrays;
import java.util.List;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.EnumSource;
import org.mockito.InOrder;
import org.springframework.mock.env.MockEnvironment;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.product.api.CatalogScanController;
import com.delivery.product.api.ProductController;
import com.delivery.product.api.dto.CatalogDtos.ProductRequest;
import com.delivery.product.api.dto.CatalogScanDtos.CreateScanRequest;
import com.delivery.product.api.dto.StoreDtos.StoreRequest;
import com.delivery.product.domain.CategoryRepository;
import com.delivery.product.domain.ProductRepository;
import com.delivery.product.domain.Store;
import com.delivery.product.domain.StoreFavoriteRepository;
import com.delivery.product.domain.StoreOfferRepository;
import com.delivery.product.domain.StoreRepository;
import com.delivery.product.service.CatalogService.CatalogRuleViolationException;
import com.delivery.product.service.StoreService.FirstShop;

import static com.delivery.product.domain.Store.ServiceCategory.CLEANING;
import static com.delivery.product.domain.Store.ServiceCategory.PRINTING;
import static com.delivery.product.domain.Store.ServiceCategory.REPAIRS;
import static com.delivery.product.domain.Store.Vertical.RESTAURANT;
import static com.delivery.product.domain.Store.Vertical.SERVICES;
import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.inOrder;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

/**
 * Where a merchant's shop comes from when they did not open one by hand: the restaurant a first
 * product provisions, and the services shop the provider's app opens from the application.
 *
 * <p>The property pinned above all is the one that cannot be undone. A shop never moves into
 * SERVICES, so a "My Store" restaurant opened for a print shop's first offer would be a restaurant
 * for good — every offer refused, and the Services tab never listing it. So a services applicant with
 * no shop is refused rather than provisioned, an Onboarding that cannot answer opens nothing, and a
 * merchant who already has a shop is never asked about at all.
 *
 * <p>And when Onboarding is asked, it is asked before the request's transaction, never inside it:
 * inside, the wait held one of ten pooled connections and the merchant's lock, on every refused tap
 * of a services applicant who is still waiting. The rest pins that the app's bootstrap is safe to
 * repeat: one services shop per merchant, however many times it is asked.
 */
@DisplayName("the shop a merchant is given")
class StoreServiceTest {

    private static final String MERCHANT = "merchant-sub";

    private StoreRepository stores;
    private OnboardingApplicationClient applications;
    private StoreService service;

    @BeforeEach
    void setUp() {
        stores = mock(StoreRepository.class);
        applications = mock(OnboardingApplicationClient.class);
        service = new StoreService(stores, mock(StoreOfferRepository.class),
                mock(StoreFavoriteRepository.class), mock(ProductRepository.class),
                mock(CategoryRepository.class), new ServiceCategories(new MockEnvironment()),
                applications, Clock.fixed(Instant.parse("2026-09-13T10:00:00Z"), ZoneOffset.UTC),
                Duration.ofHours(4), "Asia/Beirut");
        when(stores.save(any(Store.class))).thenAnswer(call -> call.getArgument(0));
        when(stores.findByMerchantIdOrderByCreatedAtDesc(MERCHANT)).thenReturn(List.of());
    }

    /** What the provider's app sends on its first entry: the application's name, category and area. */
    private static StoreRequest servicesShop(String name, Store.ServiceCategory category, String area) {
        return new StoreRequest(name, SERVICES, null, null, List.of(), null, null, area, category);
    }

    @Nested
    @DisplayName("what a first product or scan may open, asked before any transaction or lock")
    class FirstShopFor {

        @Test
        @DisplayName("a merchant who has a shop is not asked about, and nothing is locked")
        void a_merchant_with_a_shop_is_not_asked_about() {
            when(stores.existsByMerchantId(MERCHANT)).thenReturn(true);

            assertThat(service.firstShopFor(MERCHANT, null)).isEqualTo(FirstShop.ALREADY_OPEN);
            verifyNoInteractions(applications);
            verify(stores, never()).lockMerchantStores(anyString());
        }

        @Test
        @DisplayName("a request that names its store needs no answer at all")
        void a_named_store_needs_no_answer() {
            assertThat(service.firstShopFor(MERCHANT, UUID.randomUUID()))
                    .isEqualTo(FirstShop.ALREADY_OPEN);
            verifyNoInteractions(applications, stores);
        }

        @Test
        @DisplayName("a merchant with no shop is asked about, of Onboarding, with no lock held")
        void a_merchant_with_no_shop_is_asked_about() {
            when(applications.appliedToOfferServices()).thenReturn(true, false);

            assertThat(service.firstShopFor(MERCHANT, null))
                    .isEqualTo(FirstShop.NOT_FOR_A_SERVICES_APPLICANT);
            assertThat(service.firstShopFor(MERCHANT, null)).isEqualTo(FirstShop.RESTAURANT);
            verify(stores, never()).lockMerchantStores(anyString());
            verify(stores, never()).save(any(Store.class));
        }

        @Test
        @DisplayName("an Onboarding that cannot say is a 503 before anything starts, never a restaurant")
        void an_outage_opens_nothing() {
            when(applications.appliedToOfferServices()).thenThrow(
                    new OnboardingApplicationClient.OnboardingUnavailableException("down", null));

            assertThatThrownBy(() -> service.firstShopFor(MERCHANT, null))
                    .isInstanceOf(OnboardingApplicationClient.OnboardingUnavailableException.class);
            verify(stores, never()).save(any(Store.class));
        }

        /**
         * A transaction boundary is not something a mocked suite can watch, so its shape is pinned:
         * the question holds no transaction, the transactions that open a first shop only take its
         * answer, and the callers that ask it hold none either.
         */
        @Test
        @DisplayName("by shape: asked outside any transaction, and nothing that holds one can ask it")
        void asked_outside_any_transaction() throws NoSuchMethodException {
            Method firstShopFor = StoreService.class.getMethod("firstShopFor", String.class, UUID.class);
            assertThat(firstShopFor.getAnnotation(Transactional.class)).isNull();
            assertThat(StoreService.class.getAnnotation(Transactional.class)).isNull();

            List<Method> opening = List.of(
                    StoreService.class.getMethod("requireStoreFor", String.class, FirstShop.class),
                    CatalogService.class.getMethod("create", String.class, ProductRequest.class,
                            FirstShop.class),
                    CatalogScanService.class.getMethod("create", String.class, UUID.class,
                            FirstShop.class));
            for (Method method : opening) {
                assertThat(method.getAnnotation(Transactional.class)).as("%s", method).isNotNull();
            }
            for (Class<?> type : List.<Class<?>>of(CatalogService.class, CatalogScanService.class)) {
                assertThat(Arrays.stream(type.getDeclaredFields()).map(Field::getType))
                        .as("%s cannot ask Onboarding", type)
                        .doesNotContain(OnboardingApplicationClient.class);
            }

            List<Method> asking = List.of(
                    ProductController.class.getMethod("create", ProductRequest.class),
                    CatalogScanController.class.getMethod("create", CreateScanRequest.class));
            for (Method method : asking) {
                assertThat(method.getAnnotation(Transactional.class)).as("%s", method).isNull();
                assertThat(method.getDeclaringClass().getAnnotation(Transactional.class))
                        .as("%s", method.getDeclaringClass()).isNull();
            }
        }
    }

    @Nested
    @DisplayName("a first product or scan, with no shop yet")
    class RequireStoreFor {

        @Test
        @DisplayName("for a services applicant is refused, and no restaurant is opened")
        void never_a_restaurant_for_a_services_applicant() {
            assertThatThrownBy(() -> service.requireStoreFor(MERCHANT,
                    FirstShop.NOT_FOR_A_SERVICES_APPLICANT))
                    .isInstanceOf(StoreService.ServicesShopNotOpenedException.class)
                    // Still a catalogue rule, so every caller that answers those with a 422 does.
                    .isInstanceOf(CatalogRuleViolationException.class)
                    .hasMessageContaining("Open your services shop first");
            verify(stores, never()).save(any(Store.class));
        }

        @Test
        @DisplayName("for anybody else still opens the published restaurant it always did")
        void a_shop_still_gets_its_restaurant() {
            Store provisioned = service.requireStoreFor(MERCHANT, FirstShop.RESTAURANT);

            assertThat(provisioned.getVertical()).isEqualTo(RESTAURANT);
            assertThat(provisioned.getName()).isEqualTo("My Store");
            verify(stores).save(provisioned);
        }

        @ParameterizedTest
        @EnumSource(FirstShop.class)
        @DisplayName("never waits on Onboarding, whatever it is handed: that was asked before")
        void never_asks_onboarding(FirstShop answer) {
            try {
                service.requireStoreFor(MERCHANT, answer);
            } catch (RuntimeException refused) {
                // Refusing is allowed here. Asking is not.
            }
            verifyNoInteractions(applications);
        }

        @Test
        @DisplayName("returns the shop a merchant already has, without taking the lock")
        void an_existing_shop_is_returned() {
            Store printShop = new Store(MERCHANT, "Al Fakhry Press", SERVICES, PRINTING);
            when(stores.findByMerchantIdOrderByCreatedAtDesc(MERCHANT)).thenReturn(List.of(printShop));

            assertThat(service.requireStoreFor(MERCHANT, FirstShop.ALREADY_OPEN)).isSameAs(printShop);
            verify(stores, never()).lockMerchantStores(anyString());
        }

        @Test
        @DisplayName("decides under the merchant's lock, on a second look taken after it")
        void decides_under_the_lock() {
            // The first look finds nothing; by the time the lock is held, the provider's app has
            // opened the services shop. That shop is the answer, and nothing is opened.
            Store justOpened = new Store(MERCHANT, "Al Fakhry Press", SERVICES, PRINTING);
            when(stores.findByMerchantIdOrderByCreatedAtDesc(MERCHANT))
                    .thenReturn(List.of(), List.of(justOpened));

            assertThat(service.requireStoreFor(MERCHANT, FirstShop.NOT_FOR_A_SERVICES_APPLICANT))
                    .isSameAs(justOpened);

            InOrder order = inOrder(stores);
            order.verify(stores).findByMerchantIdOrderByCreatedAtDesc(MERCHANT);
            order.verify(stores).lockMerchantStores(MERCHANT);
            order.verify(stores).findByMerchantIdOrderByCreatedAtDesc(MERCHANT);
            verify(stores, never()).save(any(Store.class));
        }

        @Test
        @DisplayName("opens nothing when the shop Onboarding was not asked about is not there")
        void a_missing_shop_opens_nothing() {
            assertThatThrownBy(() -> service.requireStoreFor(MERCHANT, FirstShop.ALREADY_OPEN))
                    .isInstanceOf(IllegalStateException.class);
            verify(stores, never()).save(any(Store.class));
        }
    }

    @Nested
    @DisplayName("the provider's app opening its services shop")
    class Bootstrap {

        @Test
        @DisplayName("opens a services shop with the application's name, category and area")
        void opens_the_shop_the_application_describes() {
            StoreService.Opened opened = service.open(MERCHANT,
                    servicesShop("Al Fakhry Press", PRINTING, "Mar Mikhael"));

            Store shop = opened.view().store();
            assertThat(opened.created()).isTrue();
            assertThat(shop.getVertical()).isEqualTo(SERVICES);
            assertThat(shop.getServiceCategory()).isEqualTo(PRINTING);
            assertThat(shop.getName()).isEqualTo("Al Fakhry Press");
            assertThat(shop.getNeighborhood()).isEqualTo("Mar Mikhael");
            verify(stores).save(shop);
        }

        @Test
        @DisplayName("asked again, hands back that same shop unchanged and opens no second one")
        void is_idempotent() {
            Store[] saved = new Store[1];
            when(stores.save(any(Store.class))).thenAnswer(call -> saved[0] = call.getArgument(0));
            when(stores.findByMerchantIdOrderByCreatedAtDesc(MERCHANT))
                    .thenAnswer(call -> saved[0] == null ? List.of() : List.of(saved[0]));

            StoreService.Opened first = service.open(MERCHANT,
                    servicesShop("Al Fakhry Press", PRINTING, "Mar Mikhael"));
            // A retry from a second phone with different answers still lands on the first shop.
            StoreService.Opened again = service.open(MERCHANT,
                    servicesShop("Fakhry Print & Copy", REPAIRS, "Hamra"));

            assertThat(first.created()).isTrue();
            assertThat(again.created()).isFalse();
            assertThat(again.view().store()).isSameAs(first.view().store());
            assertThat(again.view().store().getName()).isEqualTo("Al Fakhry Press");
            assertThat(again.view().store().getServiceCategory()).isEqualTo(PRINTING);
            verify(stores, times(1)).save(any(Store.class));
        }

        @Test
        @DisplayName("looks for an existing services shop only once it holds the merchant's lock")
        void looks_under_the_lock() {
            service.open(MERCHANT, servicesShop("Al Fakhry Press", PRINTING, "Mar Mikhael"));

            InOrder order = inOrder(stores);
            order.verify(stores).lockMerchantStores(MERCHANT);
            order.verify(stores).findByMerchantIdOrderByCreatedAtDesc(MERCHANT);
            order.verify(stores).save(any(Store.class));
        }

        @Test
        @DisplayName("is not satisfied by a goods shop the merchant happens to have")
        void a_goods_shop_does_not_stand_in() {
            Store grill = new Store(MERCHANT, "Beirut Grill", RESTAURANT);
            when(stores.findByMerchantIdOrderByCreatedAtDesc(MERCHANT)).thenReturn(List.of(grill));

            StoreService.Opened opened = service.open(MERCHANT,
                    servicesShop("Al Fakhry Press", PRINTING, "Mar Mikhael"));

            assertThat(opened.created()).isTrue();
            assertThat(opened.view().store().getVertical()).isEqualTo(SERVICES);
        }

        @Test
        @DisplayName("still refuses a closed category")
        void a_closed_category_is_refused() {
            assertThatThrownBy(() -> service.open(MERCHANT,
                    servicesShop("Shine Cleaning", CLEANING, "Hamra")))
                    .isInstanceOf(CatalogRuleViolationException.class);
            verify(stores, never()).save(any(Store.class));
        }

        @Test
        @DisplayName("leaves goods shops as they were: one per call, no lock")
        void goods_shops_are_unchanged() {
            StoreRequest grill = new StoreRequest("Beirut Grill", RESTAURANT, null, null, List.of(),
                    null, null, null, null);

            assertThat(service.open(MERCHANT, grill).created()).isTrue();
            assertThat(service.open(MERCHANT, grill).created()).isTrue();
            verify(stores, times(2)).save(any(Store.class));
            verify(stores, never()).lockMerchantStores(anyString());
        }
    }
}
