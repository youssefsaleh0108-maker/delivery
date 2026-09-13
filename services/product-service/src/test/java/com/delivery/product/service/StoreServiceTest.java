package com.delivery.product.service;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.List;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.mockito.InOrder;
import org.springframework.mock.env.MockEnvironment;

import com.delivery.product.api.dto.StoreDtos.StoreRequest;
import com.delivery.product.domain.CategoryRepository;
import com.delivery.product.domain.ProductRepository;
import com.delivery.product.domain.Store;
import com.delivery.product.domain.StoreFavoriteRepository;
import com.delivery.product.domain.StoreOfferRepository;
import com.delivery.product.domain.StoreRepository;
import com.delivery.product.service.CatalogService.CatalogRuleViolationException;

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
 * shop that already exists is returned without Onboarding being asked at all. The rest pins that the
 * app's bootstrap is safe to repeat: one services shop per merchant, however many times it is asked.
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
                Duration.ofHours(4));
        when(stores.save(any(Store.class))).thenAnswer(call -> call.getArgument(0));
        when(stores.findByMerchantIdOrderByCreatedAtDesc(MERCHANT)).thenReturn(List.of());
    }

    /** What the provider's app sends on its first entry: the application's name, category and area. */
    private static StoreRequest servicesShop(String name, Store.ServiceCategory category, String area) {
        return new StoreRequest(name, SERVICES, null, null, List.of(), null, null, area, category);
    }

    @Nested
    @DisplayName("a first product, with no shop yet")
    class RequireStoreFor {

        @Test
        @DisplayName("for a services applicant is refused, and no restaurant is opened")
        void never_a_restaurant_for_a_services_applicant() {
            when(applications.appliedToOfferServices()).thenReturn(true);

            assertThatThrownBy(() -> service.requireStoreFor(MERCHANT))
                    .isInstanceOf(StoreService.ServicesShopNotOpenedException.class)
                    // Still a catalogue rule, so every caller that answers those with a 422 does.
                    .isInstanceOf(CatalogRuleViolationException.class)
                    .hasMessageContaining("Open your services shop first");
            verify(stores, never()).save(any(Store.class));
        }

        @Test
        @DisplayName("for anybody else still opens the published restaurant it always did")
        void a_shop_still_gets_its_restaurant() {
            when(applications.appliedToOfferServices()).thenReturn(false);

            Store provisioned = service.requireStoreFor(MERCHANT);

            assertThat(provisioned.getVertical()).isEqualTo(RESTAURANT);
            assertThat(provisioned.getName()).isEqualTo("My Store");
            verify(stores).save(provisioned);
        }

        @Test
        @DisplayName("opens nothing when Onboarding cannot say what the merchant applied to be")
        void an_outage_opens_nothing() {
            when(applications.appliedToOfferServices()).thenThrow(
                    new OnboardingApplicationClient.OnboardingUnavailableException("down", null));

            assertThatThrownBy(() -> service.requireStoreFor(MERCHANT))
                    .isInstanceOf(OnboardingApplicationClient.OnboardingUnavailableException.class);
            verify(stores, never()).save(any(Store.class));
        }

        @Test
        @DisplayName("returns the shop a merchant already has, without asking Onboarding anything")
        void an_existing_shop_is_returned_unasked() {
            Store printShop = new Store(MERCHANT, "Al Fakhry Press", SERVICES, PRINTING);
            when(stores.findByMerchantIdOrderByCreatedAtDesc(MERCHANT)).thenReturn(List.of(printShop));

            assertThat(service.requireStoreFor(MERCHANT)).isSameAs(printShop);
            verifyNoInteractions(applications);
            verify(stores, never()).lockMerchantStores(anyString());
        }

        @Test
        @DisplayName("decides under the merchant's lock, on a second look taken after it")
        void decides_under_the_lock() {
            // The first look finds nothing; by the time the lock is held, the provider's app has
            // opened the services shop. That shop is the answer, and nobody is asked anything.
            Store justOpened = new Store(MERCHANT, "Al Fakhry Press", SERVICES, PRINTING);
            when(stores.findByMerchantIdOrderByCreatedAtDesc(MERCHANT))
                    .thenReturn(List.of(), List.of(justOpened));

            assertThat(service.requireStoreFor(MERCHANT)).isSameAs(justOpened);

            InOrder order = inOrder(stores);
            order.verify(stores).findByMerchantIdOrderByCreatedAtDesc(MERCHANT);
            order.verify(stores).lockMerchantStores(MERCHANT);
            order.verify(stores).findByMerchantIdOrderByCreatedAtDesc(MERCHANT);
            verifyNoInteractions(applications);
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
