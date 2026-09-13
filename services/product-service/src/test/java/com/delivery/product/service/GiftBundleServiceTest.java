package com.delivery.product.service;

import java.math.BigDecimal;
import java.time.DayOfWeek;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalTime;
import java.time.ZoneId;
import java.time.ZonedDateTime;
import java.util.Arrays;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.data.domain.Pageable;

import com.delivery.product.domain.Product;
import com.delivery.product.domain.ProductRepository;
import com.delivery.product.domain.Store;
import com.delivery.product.domain.StoreHours;
import com.delivery.product.domain.StoreRepository;
import com.delivery.product.service.CatalogService.CatalogRuleViolationException;
import com.delivery.product.service.CatalogService.ProductNotFoundException;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Which products the gift hub shows, what "Same-day Deliverable" means, and the back office's switch.
 *
 * <p>Every rule here fails quietly when it breaks: a suspended shop's product on the platform's own
 * window, a card promising today from a shop that shuts in ten minutes, a draft somebody can tap and
 * not buy. None of them throws — they just show — so each is pinned at a chosen instant.
 */
@DisplayName("the gift hub's featured bundles")
class GiftBundleServiceTest {

    /** A Wednesday; shops default to UTC, so these instants are the shop's own clock. */
    private static final LocalDate WEDNESDAY = LocalDate.of(2026, 8, 12);

    private static Instant utc(int hour, int minute) {
        return ZonedDateTime.of(WEDNESDAY, LocalTime.of(hour, minute), ZoneId.of("UTC")).toInstant();
    }

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

    /** Listed and open 08:00-23:00 every day, with the default 40-minute slow ETA. */
    private static Store listedShop(String name) {
        Store shop = new Store("merchant-sub", name, Store.Vertical.GROCERY);
        shop.replaceHours(Arrays.stream(DayOfWeek.values())
                .map(day -> new StoreHours(day, LocalTime.of(8, 0), LocalTime.of(23, 0)))
                .toList());
        shop.publish(utc(0, 0));
        return shop;
    }

    private static Product liveProductOf(Store shop, String name) {
        Product product = new Product("merchant-sub", shop.getId(), name, null,
                new BigDecimal("30.00"), null);
        product.addImage("products/" + name + ".jpg");
        product.publish();
        return product;
    }

    private void picked(List<Product> featured, Store... shops) {
        when(products.findFeaturedGifts(any(Pageable.class))).thenReturn(featured);
        when(stores.findAllById(any())).thenReturn(List.of(shops));
    }

    @Nested
    @DisplayName("what reaches the hub")
    class Reaches {

        @Test
        @DisplayName("only products of listed shops: never a draft shop's, a suspended shop's or an orphan's")
        void onlyListedShops() {
            Store listed = listedShop("Dekkane Abou Selim");
            Store draft = new Store("merchant-sub", "Not Yet Open", Store.Vertical.GROCERY);
            Store suspended = listedShop("Suspended Sweets");
            suspended.suspend();
            Product fromListed = liveProductOf(listed, "family-essentials");
            Product fromDraft = liveProductOf(draft, "draft-box");
            Product fromSuspended = liveProductOf(suspended, "baklava-tray");
            Product orphan = new Product("merchant-sub", UUID.randomUUID(), "orphan", null,
                    new BigDecimal("5.00"), null);
            picked(List.of(fromListed, fromDraft, fromSuspended, orphan), listed, draft, suspended);

            assertThat(gifts.featured(utc(12, 0)))
                    .extracting(GiftBundleService.GiftBundle::product)
                    .containsExactly(fromListed);
        }

        @Test
        @DisplayName("not a product the stock projection says is gone")
        void notASoldOutProduct() {
            Store shop = listedShop("Dekkane Abou Selim");
            Product soldOut = liveProductOf(shop, "breakfast-box");
            soldOut.applyStockProjection(false);
            Product inStock = liveProductOf(shop, "sweet-treats");
            picked(List.of(soldOut, inStock), shop);

            assertThat(gifts.featured(utc(12, 0)))
                    .extracting(GiftBundleService.GiftBundle::product)
                    .containsExactly(inStock);
        }

        @Test
        @DisplayName("in the order the picks were made, from one read of the shops, at most twelve")
        void inOrderFromOneReadBounded() {
            Store shop = listedShop("Dekkane Abou Selim");
            Product newest = liveProductOf(shop, "newest");
            Product older = liveProductOf(shop, "older");
            picked(List.of(newest, older), shop);

            assertThat(gifts.featured(utc(12, 0)))
                    .extracting(GiftBundleService.GiftBundle::product)
                    .containsExactly(newest, older);

            verify(stores, times(1)).findAllById(any());
            ArgumentCaptor<Pageable> page = ArgumentCaptor.forClass(Pageable.class);
            verify(products).findFeaturedGifts(page.capture());
            assertThat(page.getValue().getPageSize()).isEqualTo(GiftBundleService.MAX_BUNDLES);
        }

        @Test
        @DisplayName("nothing featured reads no shops at all")
        void nothingFeatured() {
            when(products.findFeaturedGifts(any(Pageable.class))).thenReturn(List.of());

            assertThat(gifts.featured(utc(12, 0))).isEmpty();
            verify(stores, never()).findAllById(any());
        }
    }

    @Nested
    @DisplayName("promising today")
    class Today {

        private GiftBundleService.GiftBundle bundleAt(Instant now) {
            Store shop = listedShop("Dekkane Abou Selim");
            picked(List.of(liveProductOf(shop, "family-essentials")), shop);
            return gifts.featured(now).get(0);
        }

        @Test
        @DisplayName("a shop with time to deliver before it closes promises today")
        void timeToDeliver() {
            GiftBundleService.GiftBundle bundle = bundleAt(utc(12, 0));

            assertThat(bundle.availability()).isEqualTo(Store.Availability.OPEN);
            assertThat(bundle.sameDayDeliverable()).isTrue();
        }

        @Test
        @DisplayName("exactly the slow ETA before closing still makes it")
        void theBoundaryIsInclusive() {
            assertThat(bundleAt(utc(22, 20)).sameDayDeliverable()).isTrue();
            assertThat(bundleAt(utc(22, 21)).sameDayDeliverable()).isFalse();
        }

        @Test
        @DisplayName("a shop closing before its ETA stays on the hub without the promise")
        void closingTooSoon() {
            GiftBundleService.GiftBundle bundle = bundleAt(utc(22, 40));

            assertThat(bundle.availability()).isEqualTo(Store.Availability.CLOSING_SOON);
            assertThat(bundle.sameDayDeliverable()).isFalse();
        }

        @Test
        @DisplayName("a closed shop stays on the hub without the promise")
        void closed() {
            GiftBundleService.GiftBundle bundle = bundleAt(utc(23, 30));

            assertThat(bundle.availability()).isEqualTo(Store.Availability.CLOSED);
            assertThat(bundle.sameDayDeliverable()).isFalse();
        }
    }

    @Nested
    @DisplayName("the back office's switch")
    class Switch {

        private final Instant first = Instant.parse("2026-09-13T08:00:00Z");
        private final Instant later = Instant.parse("2026-09-13T09:30:00Z");

        private Product stored(Product product) {
            when(products.findById(product.getId())).thenReturn(Optional.of(product));
            return product;
        }

        @Test
        @DisplayName("features a live product at the moment it was picked, and saves it")
        void featuresALiveProduct() {
            Product product = stored(liveProductOf(listedShop("Dekkane"), "family-essentials"));

            Product saved = gifts.setFeatured(product.getId(), true, "ops-sub", first);

            assertThat(saved.isGiftFeatured()).isTrue();
            assertThat(saved.getGiftFeaturedAt()).isEqualTo(first);
            verify(products).save(product);
        }

        @Test
        @DisplayName("featuring twice keeps the first moment, so the hub does not reshuffle")
        void featuringTwiceKeepsTheFirstMoment() {
            Product product = stored(liveProductOf(listedShop("Dekkane"), "family-essentials"));

            gifts.setFeatured(product.getId(), true, "ops-sub", first);
            gifts.setFeatured(product.getId(), true, "ops-sub", later);

            assertThat(product.getGiftFeaturedAt()).isEqualTo(first);
        }

        @Test
        @DisplayName("unfeaturing takes it off and forgets when it was picked")
        void unfeaturing() {
            Product product = stored(liveProductOf(listedShop("Dekkane"), "family-essentials"));
            product.featureAsGift(first);

            gifts.setFeatured(product.getId(), false, "ops-sub", later);

            assertThat(product.isGiftFeatured()).isFalse();
            assertThat(product.getGiftFeaturedAt()).isNull();
        }

        @Test
        @DisplayName("a draft cannot be featured: a card nobody can buy is refused, and nothing is saved")
        void aDraftIsRefused() {
            Store shop = listedShop("Dekkane");
            Product draft = stored(new Product("merchant-sub", shop.getId(), "draft", null,
                    new BigDecimal("9.00"), null));

            assertThatThrownBy(() -> gifts.setFeatured(draft.getId(), true, "ops-sub", first))
                    .isInstanceOf(CatalogRuleViolationException.class);
            assertThat(draft.isGiftFeatured()).isFalse();
            verify(products, never()).save(any());
        }

        @Test
        @DisplayName("an unknown product is not found")
        void unknown() {
            UUID nobody = UUID.randomUUID();
            when(products.findById(nobody)).thenReturn(Optional.empty());

            assertThatThrownBy(() -> gifts.setFeatured(nobody, true, "ops-sub", first))
                    .isInstanceOf(ProductNotFoundException.class);
        }

        @Test
        @DisplayName("archiving a product takes it off the hub for good")
        void archivingTakesItOff() {
            Product product = liveProductOf(listedShop("Dekkane"), "family-essentials");
            product.featureAsGift(first);

            product.archive();

            assertThat(product.isGiftFeatured()).isFalse();
            assertThat(product.getGiftFeaturedAt()).isNull();
        }
    }
}
