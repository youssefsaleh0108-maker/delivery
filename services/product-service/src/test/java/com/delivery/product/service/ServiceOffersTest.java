package com.delivery.product.service;

import java.math.BigDecimal;
import java.time.DayOfWeek;
import java.time.Instant;
import java.time.LocalTime;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.mock.env.MockEnvironment;

import com.delivery.platform.outbox.OutboxRecorder;
import com.delivery.product.api.dto.CatalogDtos.ProductRequest;
import com.delivery.product.api.dto.CatalogDtos.ServiceTermsRequest;
import com.delivery.product.domain.CategoryRepository;
import com.delivery.product.domain.GeoPoint;
import com.delivery.product.domain.Product;
import com.delivery.product.domain.ProductOption;
import com.delivery.product.domain.ProductOptionGroup;
import com.delivery.product.domain.ProductOptionGroupRepository;
import com.delivery.product.domain.ProductRepository;
import com.delivery.product.domain.ServiceTerms;
import com.delivery.product.domain.ServiceTerms.AttachmentPolicy;
import com.delivery.product.domain.ServiceTerms.Fulfilment;
import com.delivery.product.domain.ServiceTerms.PricingType;
import com.delivery.product.domain.ServiceTermsRepository;
import com.delivery.product.domain.Store;
import com.delivery.product.domain.StoreDeliveryZoneRepository;
import com.delivery.product.domain.StoreHours;
import com.delivery.product.domain.StoreRepository;
import com.delivery.product.event.CatalogEvents;
import com.delivery.product.event.CatalogEvents.ProductSnapshot;
import com.delivery.product.service.CatalogService.CatalogRuleViolationException;
import com.delivery.product.service.CatalogService.ProductNotFoundException;
import com.delivery.product.service.CatalogService.ProductView;
import com.delivery.product.service.StoreService.FirstShop;
import com.delivery.product.service.StoreService.StoreNotFoundException;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyBoolean;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Service offers in the catalogue: the rules a product in a service shop lives by.
 *
 * <p>Each rule is decided from the shop the product sits in, never from what the request says, so every
 * test here puts a product in a shop and asks the service. Three shops are enough: a pinned print shop,
 * a print shop with no pin and no delivery areas, and a grill.
 *
 * <p>The SQL half, that listing queries never return a paused offer, a goods product or a closed
 * category, is proven against a real database in {@code ServiceOffersDatabaseTest}.
 */
@DisplayName("service offers in the catalogue")
class ServiceOffersTest {

    private static final String PROVIDER = "provider-sub";
    private static final String RIVAL = "rival-merchant-sub";

    private ProductRepository products;
    private StoreRepository stores;
    private ServiceTermsRepository serviceTerms;
    private StoreDeliveryZoneRepository storeZones;
    private ProductOptionGroupRepository optionGroups;
    private StoreService storeService;
    private OutboxRecorder outbox;
    private CatalogService catalog;

    /** The service's configuration, so a test can close a service category. */
    private MockEnvironment environment;

    /** The terms "saved" for each offer, served back by the mocked repository. */
    private final Map<UUID, ServiceTerms> savedTerms = new HashMap<>();

    private Store press;
    private Store backRoomPress;
    private Store grill;

    @BeforeEach
    void setUp() {
        products = mock(ProductRepository.class);
        stores = mock(StoreRepository.class);
        serviceTerms = mock(ServiceTermsRepository.class);
        storeZones = mock(StoreDeliveryZoneRepository.class);
        optionGroups = mock(ProductOptionGroupRepository.class);
        storeService = mock(StoreService.class);
        outbox = mock(OutboxRecorder.class);
        environment = new MockEnvironment();
        catalog = new CatalogService(products, mock(CategoryRepository.class), storeService, outbox,
                stores, serviceTerms, storeZones, optionGroups, new ServiceCategories(environment));

        press = shop(new Store(PROVIDER, "Al Fakhry Press", Store.Vertical.SERVICES,
                Store.ServiceCategory.PRINTING));
        press.pinAt(GeoPoint.of(33.898200d, 35.482500d));
        backRoomPress = shop(new Store(PROVIDER, "Back Room Press", Store.Vertical.SERVICES,
                Store.ServiceCategory.PRINTING));
        grill = shop(new Store(PROVIDER, "Hamra Grill", Store.Vertical.RESTAURANT));
        when(storeService.ownedBy(PROVIDER)).thenReturn(List.of(press, backRoomPress, grill));

        when(products.save(any(Product.class))).thenAnswer(call -> call.getArgument(0));
        when(products.findByIdAndMerchantId(any(UUID.class), anyString())).thenReturn(Optional.empty());
        when(serviceTerms.save(any(ServiceTerms.class))).thenAnswer(call -> {
            ServiceTerms terms = call.getArgument(0);
            savedTerms.put(terms.getProductId(), terms);
            return terms;
        });
        when(serviceTerms.findById(any(UUID.class)))
                .thenAnswer(call -> Optional.ofNullable(savedTerms.get(call.<UUID>getArgument(0))));
        when(serviceTerms.findAllById(any())).thenAnswer(call -> {
            List<ServiceTerms> found = new ArrayList<>();
            call.<Iterable<UUID>>getArgument(0).forEach(id -> {
                if (savedTerms.containsKey(id)) {
                    found.add(savedTerms.get(id));
                }
            });
            return found;
        });
    }

    private Store shop(Store store) {
        when(stores.findById(store.getId())).thenReturn(Optional.of(store));
        return store;
    }

    private static ServiceTermsRequest cardTerms(Fulfilment fulfilment) {
        return new ServiceTermsRequest(PricingType.FIXED, "cards", 500, 24, 48, fulfilment,
                AttachmentPolicy.REQUIRED, "Which paper colour?");
    }

    private static ProductRequest offerIn(Store shop, ServiceTermsRequest terms) {
        return new ProductRequest("Business card printing", "Matte, 350gsm", new BigDecimal("15.00"),
                null, shop.getId(), null, null, terms);
    }

    /**
     * An offer the provider owns in {@code shop}, with a photo, in {@code state}, and with saved terms
     * unless {@code fulfilment} is null (a goods product, or a service shop's product from before terms).
     */
    private Product offer(Store shop, Fulfilment fulfilment, Product.Status state) {
        Product product = new Product(PROVIDER, shop.getId(), "Business card printing", null,
                new BigDecimal("15.00"), null);
        product.addImage("products/cards.jpg");
        if (state != Product.Status.DRAFT) {
            product.publish();
        }
        if (state == Product.Status.PAUSED) {
            product.pause();
        }
        if (state == Product.Status.ARCHIVED) {
            product.archive();
        }
        when(products.findByIdAndMerchantId(product.getId(), PROVIDER)).thenReturn(Optional.of(product));
        when(products.findById(product.getId())).thenReturn(Optional.of(product));
        when(products.existsById(product.getId())).thenReturn(true);
        if (fulfilment != null) {
            savedTerms.put(product.getId(), new ServiceTerms(product.getId(), PricingType.FIXED, "cards",
                    500, 24, 48, fulfilment, AttachmentPolicy.NONE, null));
        }
        return product;
    }

    private ProductSnapshot recorded(String eventType) {
        ArgumentCaptor<Object> payload = ArgumentCaptor.forClass(Object.class);
        verify(outbox).record(eq(CatalogEvents.AGGREGATE_TYPE), anyString(), eq(eventType),
                payload.capture());
        return (ProductSnapshot) payload.getValue();
    }

    private void nothingRecorded() {
        verify(outbox, never()).record(anyString(), anyString(), anyString(), any());
    }

    @Nested
    @DisplayName("the service block follows the shop, both ways")
    class TheBlockFollowsTheShop {

        @Test
        void an_offer_in_a_service_shop_is_saved_with_its_terms() {
            Product created = catalog.create(PROVIDER, offerIn(press, cardTerms(Fulfilment.BOTH)),
                    FirstShop.ALREADY_OPEN);

            ServiceTerms terms = savedTerms.get(created.getId());
            assertThat(terms).isNotNull();
            assertThat(terms.getPricingType()).isEqualTo(PricingType.FIXED);
            assertThat(terms.getUnitLabel()).isEqualTo("cards");
            assertThat(terms.getUnitSize()).isEqualTo(500);
            assertThat(terms.getTurnaroundMinHours()).isEqualTo(24);
            assertThat(terms.getTurnaroundMaxHours()).isEqualTo(48);
            assertThat(terms.getFulfilmentModes()).isEqualTo(Fulfilment.BOTH);
            assertThat(terms.getAttachmentPolicy()).isEqualTo(AttachmentPolicy.REQUIRED);
            assertThat(terms.getInstructionsPrompt()).isEqualTo("Which paper colour?");
        }

        @Test
        void an_offer_in_a_service_shop_without_terms_is_refused_and_nothing_is_saved() {
            assertThatThrownBy(() -> catalog.create(PROVIDER, offerIn(press, null), FirstShop.ALREADY_OPEN))
                    .isInstanceOf(CatalogRuleViolationException.class)
                    .hasMessageContaining("service terms");

            verify(products, never()).save(any(Product.class));
            nothingRecorded();
        }

        @Test
        void a_goods_product_carrying_terms_is_refused() {
            assertThatThrownBy(() -> catalog.create(PROVIDER,
                    offerIn(grill, cardTerms(Fulfilment.PICKUP)), FirstShop.ALREADY_OPEN))
                    .isInstanceOf(CatalogRuleViolationException.class)
                    .hasMessageContaining("goods shop");

            verify(products, never()).save(any(Product.class));
            verify(serviceTerms, never()).save(any(ServiceTerms.class));
        }

        /** A goods form that has never heard of terms keeps working exactly as it did. */
        @Test
        void a_goods_product_without_terms_is_created_as_before() {
            Product dish = catalog.create(PROVIDER, offerIn(grill, null), FirstShop.ALREADY_OPEN);

            assertThat(dish.getStoreId()).isEqualTo(grill.getId());
            verify(serviceTerms, never()).save(any(ServiceTerms.class));
        }

        /** The shop a merchant files under by default is still a shop, and still decides. */
        @Test
        void the_default_shop_decides_when_the_request_names_none() {
            // A merchant who already has a shop is never asked what a first one may be.
            when(storeService.requireStoreFor(PROVIDER, FirstShop.ALREADY_OPEN)).thenReturn(press);
            ProductRequest noShopNamed = new ProductRequest("Flyers", null, new BigDecimal("25.00"),
                    null, null, null, null, null);

            assertThatThrownBy(() -> catalog.create(PROVIDER, noShopNamed, FirstShop.ALREADY_OPEN))
                    .isInstanceOf(CatalogRuleViolationException.class);
        }

        @Test
        void an_update_holds_the_same_rule_both_ways() {
            Product offer = offer(press, Fulfilment.BOTH, Product.Status.DRAFT);
            Product dish = offer(grill, null, Product.Status.DRAFT);

            assertThatThrownBy(() -> catalog.update(offer.getId(), PROVIDER, offerIn(press, null)))
                    .isInstanceOf(CatalogRuleViolationException.class);
            assertThatThrownBy(() -> catalog.update(dish.getId(), PROVIDER,
                    offerIn(grill, cardTerms(Fulfilment.PICKUP))))
                    .isInstanceOf(CatalogRuleViolationException.class);
            nothingRecorded();
        }

        @Test
        void an_update_revises_the_terms_the_offer_already_has() {
            Product offer = offer(press, Fulfilment.PICKUP, Product.Status.DRAFT);
            ServiceTerms before = savedTerms.get(offer.getId());

            catalog.update(offer.getId(), PROVIDER, offerIn(press, new ServiceTermsRequest(
                    PricingType.PER_UNIT, "sqm", 1, 2, 6, Fulfilment.DELIVERY,
                    AttachmentPolicy.OPTIONAL, null)));

            assertThat(before.getPricingType()).isEqualTo(PricingType.PER_UNIT);
            assertThat(before.getUnitLabel()).isEqualTo("sqm");
            assertThat(before.getTurnaroundMaxHours()).isEqualTo(6);
            assertThat(before.getFulfilmentModes()).isEqualTo(Fulfilment.DELIVERY);
            verify(serviceTerms, never()).save(any(ServiceTerms.class));
        }

        /** A print shop's product saved before this change is given terms by its next update. */
        @Test
        void an_update_gives_terms_to_a_service_shop_product_that_had_none() {
            Product legacy = offer(press, null, Product.Status.DRAFT);

            catalog.update(legacy.getId(), PROVIDER, offerIn(press, cardTerms(Fulfilment.PICKUP)));

            assertThat(savedTerms.get(legacy.getId())).isNotNull();
        }
    }

    @Nested
    @DisplayName("turnaround is checked before anything is saved")
    class TurnaroundThroughTheService {

        @Test
        void a_turnaround_that_ends_before_it_starts_is_a_422_and_saves_nothing() {
            ServiceTermsRequest backwards = new ServiceTermsRequest(PricingType.FIXED, "cards", 500,
                    72, 24, Fulfilment.BOTH, null, null);

            assertThatThrownBy(() -> catalog.create(PROVIDER, offerIn(press, backwards), FirstShop.ALREADY_OPEN))
                    .isInstanceOf(CatalogRuleViolationException.class)
                    .hasMessageContaining("72 hours")
                    .hasMessageContaining("24 hours");

            verify(products, never()).save(any(Product.class));
            verify(serviceTerms, never()).save(any(ServiceTerms.class));
            nothingRecorded();
        }

        @Test
        void an_update_with_a_turnaround_past_thirty_days_leaves_the_terms_as_they_were() {
            Product offer = offer(press, Fulfilment.PICKUP, Product.Status.DRAFT);

            assertThatThrownBy(() -> catalog.update(offer.getId(), PROVIDER, offerIn(press,
                    new ServiceTermsRequest(PricingType.FIXED, "cards", 500, 24, 2_000,
                            Fulfilment.PICKUP, null, null))))
                    .isInstanceOf(CatalogRuleViolationException.class)
                    .hasMessageContaining("720 hours");

            assertThat(savedTerms.get(offer.getId()).getTurnaroundMaxHours()).isEqualTo(48);
            nothingRecorded();
        }
    }

    @Nested
    @DisplayName("events carry the terms")
    class Events {

        @Test
        void product_created_carries_the_service_block() {
            catalog.create(PROVIDER, offerIn(press, cardTerms(Fulfilment.BOTH)), FirstShop.ALREADY_OPEN);

            ProductSnapshot snapshot = recorded(CatalogEvents.PRODUCT_CREATED);
            assertThat(snapshot.service()).isNotNull();
            assertThat(snapshot.service().pricingType()).isEqualTo(PricingType.FIXED);
            assertThat(snapshot.service().unitLabel()).isEqualTo("cards");
            assertThat(snapshot.service().unitSize()).isEqualTo(500);
            assertThat(snapshot.service().turnaroundMinHours()).isEqualTo(24);
            assertThat(snapshot.service().turnaroundMaxHours()).isEqualTo(48);
            assertThat(snapshot.service().fulfilmentModes()).isEqualTo(Fulfilment.BOTH);
            assertThat(snapshot.service().attachmentPolicy()).isEqualTo(AttachmentPolicy.REQUIRED);
            assertThat(snapshot.service().instructionsPrompt()).isEqualTo("Which paper colour?");
        }

        @Test
        void a_goods_product_created_carries_none() {
            catalog.create(PROVIDER, offerIn(grill, null), FirstShop.ALREADY_OPEN);

            assertThat(recorded(CatalogEvents.PRODUCT_CREATED).service()).isNull();
        }

        /** A consumer takes each snapshot as the whole offer: terms left out would read as removed. */
        @Test
        void publishing_and_archiving_an_offer_still_carry_its_terms() {
            Product offer = offer(press, Fulfilment.PICKUP, Product.Status.DRAFT);

            catalog.publish(offer.getId(), PROVIDER);
            assertThat(recorded(CatalogEvents.PRODUCT_PUBLISHED).service().fulfilmentModes())
                    .isEqualTo(Fulfilment.PICKUP);

            catalog.archive(offer.getId(), PROVIDER);
            assertThat(recorded(CatalogEvents.PRODUCT_ARCHIVED).service()).isNotNull();
        }
    }

    @Nested
    @DisplayName("an offer customers can have delivered needs a shop that says where it reaches")
    class DeliveryReach {

        @Test
        void publishing_it_from_a_shop_with_no_areas_and_no_pin_is_refused_with_what_to_do() {
            Product offer = offer(backRoomPress, Fulfilment.DELIVERY, Product.Status.DRAFT);

            assertThatThrownBy(() -> catalog.publish(offer.getId(), PROVIDER))
                    .isInstanceOf(CatalogRuleViolationException.class)
                    .hasMessageContaining("delivery areas")
                    .hasMessageContaining("pin")
                    .hasMessageContaining("pickup only");

            assertThat(offer.getStatus()).isEqualTo(Product.Status.DRAFT);
            nothingRecorded();
        }

        @Test
        void both_counts_as_delivery() {
            Product offer = offer(backRoomPress, Fulfilment.BOTH, Product.Status.DRAFT);

            assertThatThrownBy(() -> catalog.publish(offer.getId(), PROVIDER))
                    .isInstanceOf(CatalogRuleViolationException.class);
        }

        @Test
        void a_pin_is_enough() {
            Product offer = offer(press, Fulfilment.DELIVERY, Product.Status.DRAFT);

            assertThat(catalog.publish(offer.getId(), PROVIDER).getStatus())
                    .isEqualTo(Product.Status.ACTIVE);
        }

        @Test
        void delivery_areas_are_enough() {
            when(storeZones.existsByStoreId(backRoomPress.getId())).thenReturn(true);
            Product offer = offer(backRoomPress, Fulfilment.DELIVERY, Product.Status.DRAFT);

            assertThat(catalog.publish(offer.getId(), PROVIDER).getStatus())
                    .isEqualTo(Product.Status.ACTIVE);
        }

        @Test
        void a_pickup_offer_needs_neither() {
            Product offer = offer(backRoomPress, Fulfilment.PICKUP, Product.Status.DRAFT);

            assertThat(catalog.publish(offer.getId(), PROVIDER).getStatus())
                    .isEqualTo(Product.Status.ACTIVE);
            verify(storeZones, never()).existsByStoreId(any(UUID.class));
        }

        @Test
        void a_live_offer_cannot_be_switched_to_delivery_where_the_shop_does_not_reach() {
            Product offer = offer(backRoomPress, Fulfilment.PICKUP, Product.Status.ACTIVE);

            assertThatThrownBy(() -> catalog.update(offer.getId(), PROVIDER,
                    offerIn(backRoomPress, cardTerms(Fulfilment.DELIVERY))))
                    .isInstanceOf(CatalogRuleViolationException.class);

            assertThat(savedTerms.get(offer.getId()).getFulfilmentModes()).isEqualTo(Fulfilment.PICKUP);
            nothingRecorded();
        }

        /**
         * Keeping delivery is not switching to it. An offer published or resumed with delivery met the
         * rule then, so a shop that has since cleared its pin and its areas still fixes a typo without
         * pausing the offer; resuming and publishing check again.
         */
        @Test
        void a_live_delivery_offer_is_still_edited_after_the_shop_cleared_its_reach() {
            Product offer = offer(backRoomPress, Fulfilment.DELIVERY, Product.Status.ACTIVE);

            catalog.update(offer.getId(), PROVIDER, new ProductRequest("Business card printing, matte",
                    "Matte, 350gsm", new BigDecimal("15.00"), null, backRoomPress.getId(), null, null,
                    cardTerms(Fulfilment.BOTH)));

            assertThat(offer.getName()).isEqualTo("Business card printing, matte");
            assertThat(savedTerms.get(offer.getId()).getFulfilmentModes()).isEqualTo(Fulfilment.BOTH);
            verify(storeZones, never()).existsByStoreId(any(UUID.class));
        }

        /** A draft is not in front of anybody; publishing it is where the rule is met. */
        @Test
        void a_draft_may_be_switched_and_is_checked_when_published() {
            Product offer = offer(backRoomPress, Fulfilment.PICKUP, Product.Status.DRAFT);

            catalog.update(offer.getId(), PROVIDER, offerIn(backRoomPress, cardTerms(Fulfilment.DELIVERY)));

            assertThatThrownBy(() -> catalog.publish(offer.getId(), PROVIDER))
                    .isInstanceOf(CatalogRuleViolationException.class);
        }

        @Test
        void a_service_shop_product_without_terms_cannot_be_published() {
            Product legacy = offer(press, null, Product.Status.DRAFT);

            assertThatThrownBy(() -> catalog.publish(legacy.getId(), PROVIDER))
                    .isInstanceOf(CatalogRuleViolationException.class)
                    .hasMessageContaining("no service terms");
            assertThat(legacy.getStatus()).isEqualTo(Product.Status.DRAFT);
        }
    }

    @Nested
    @DisplayName("pausing and resuming")
    class PauseAndResume {

        @Test
        void pausing_a_live_offer_takes_it_off_sale_and_says_so() {
            Product offer = offer(press, Fulfilment.BOTH, Product.Status.ACTIVE);

            assertThat(catalog.pause(offer.getId(), PROVIDER).getStatus())
                    .isEqualTo(Product.Status.PAUSED);

            ProductSnapshot snapshot = recorded(CatalogEvents.PRODUCT_UPDATED);
            assertThat(snapshot.status()).isEqualTo(Product.Status.PAUSED);
            assertThat(snapshot.service()).isNotNull();
        }

        @Test
        void another_merchant_cannot_pause_it_and_is_told_it_does_not_exist() {
            Product offer = offer(press, Fulfilment.BOTH, Product.Status.ACTIVE);

            assertThatThrownBy(() -> catalog.pause(offer.getId(), RIVAL))
                    .isInstanceOf(ProductNotFoundException.class);

            assertThat(offer.getStatus()).isEqualTo(Product.Status.ACTIVE);
            nothingRecorded();
        }

        @Test
        void another_merchant_cannot_resume_it() {
            Product offer = offer(press, Fulfilment.BOTH, Product.Status.PAUSED);

            assertThatThrownBy(() -> catalog.resume(offer.getId(), RIVAL))
                    .isInstanceOf(ProductNotFoundException.class);

            assertThat(offer.getStatus()).isEqualTo(Product.Status.PAUSED);
            nothingRecorded();
        }

        @Test
        void a_goods_product_is_archived_not_paused() {
            Product dish = offer(grill, null, Product.Status.ACTIVE);

            assertThatThrownBy(() -> catalog.pause(dish.getId(), PROVIDER))
                    .isInstanceOf(CatalogRuleViolationException.class)
                    .hasMessageContaining("archiving");

            assertThat(dish.getStatus()).isEqualTo(Product.Status.ACTIVE);
        }

        @Test
        void a_draft_cannot_be_paused() {
            Product offer = offer(press, Fulfilment.BOTH, Product.Status.DRAFT);

            assertThatThrownBy(() -> catalog.pause(offer.getId(), PROVIDER))
                    .isInstanceOf(CatalogRuleViolationException.class);

            assertThat(offer.getStatus()).isEqualTo(Product.Status.DRAFT);
        }

        @Test
        void resuming_puts_it_back_on_sale_and_says_so() {
            Product offer = offer(press, Fulfilment.BOTH, Product.Status.PAUSED);

            assertThat(catalog.resume(offer.getId(), PROVIDER).getStatus())
                    .isEqualTo(Product.Status.ACTIVE);

            ProductSnapshot snapshot = recorded(CatalogEvents.PRODUCT_UPDATED);
            assertThat(snapshot.status()).isEqualTo(Product.Status.ACTIVE);
            assertThat(snapshot.service().fulfilmentModes()).isEqualTo(Fulfilment.BOTH);
        }

        @Test
        void resuming_an_offer_whose_last_photo_went_while_it_was_paused_is_refused() {
            Product offer = offer(press, Fulfilment.PICKUP, Product.Status.PAUSED);
            offer.removeImage("products/cards.jpg");

            assertThatThrownBy(() -> catalog.resume(offer.getId(), PROVIDER))
                    .isInstanceOf(CatalogRuleViolationException.class)
                    .hasMessageContaining("photo");

            assertThat(offer.getStatus()).isEqualTo(Product.Status.PAUSED);
        }

        @Test
        void resuming_a_delivery_offer_the_shop_no_longer_reaches_is_refused() {
            Product offer = offer(backRoomPress, Fulfilment.DELIVERY, Product.Status.PAUSED);

            assertThatThrownBy(() -> catalog.resume(offer.getId(), PROVIDER))
                    .isInstanceOf(CatalogRuleViolationException.class)
                    .hasMessageContaining("delivery areas");

            assertThat(offer.getStatus()).isEqualTo(Product.Status.PAUSED);
            nothingRecorded();
        }

        /** Told what is actually wrong: it is not paused, whatever the shop's reach. */
        @Test
        void resuming_an_offer_that_is_not_paused_says_so() {
            Product offer = offer(backRoomPress, Fulfilment.DELIVERY, Product.Status.DRAFT);

            assertThatThrownBy(() -> catalog.resume(offer.getId(), PROVIDER))
                    .isInstanceOf(CatalogRuleViolationException.class)
                    .hasMessageContaining("Only a paused offer");
        }
    }

    @Nested
    @DisplayName("a paused offer is never shown or orderable")
    class APausedOfferIsInvisible {

        /** Order Manager reads a product through here before pricing a line, and refuses anything else. */
        @Test
        void a_customer_reading_it_is_told_it_does_not_exist() {
            Product offer = offer(press, Fulfilment.BOTH, Product.Status.PAUSED);

            assertThatThrownBy(() -> catalog.read(offer.getId(), "customer-sub"))
                    .isInstanceOf(ProductNotFoundException.class);
            assertThatThrownBy(() -> catalog.read(offer.getId(), null))
                    .isInstanceOf(ProductNotFoundException.class);
        }

        @Test
        void its_owner_still_reads_it_to_resume_it() {
            Product offer = offer(press, Fulfilment.BOTH, Product.Status.PAUSED);

            assertThat(catalog.read(offer.getId(), PROVIDER)).isSameAs(offer);
        }

        @Test
        void buy_again_does_not_bring_it_back() {
            Product offer = offer(press, Fulfilment.BOTH, Product.Status.PAUSED);
            when(products.findByIdIn(any())).thenReturn(List.of(offer));

            assertThat(catalog.readAllActive(List.of(offer.getId()))).isEmpty();
        }
    }

    @Nested
    @DisplayName("a live offer is shown only while its shop is listed")
    class AnUnlistedShopsOffersAreInvisible {

        private static final String OPEN_CATEGORIES = "delivery.product.services.enabled-categories";

        /** Listed: open all week, published, and in a category the launch opens. */
        private Store listedPress;

        @BeforeEach
        void aListedPrintShop() {
            listedPress = listed(new Store(PROVIDER, "Listed Press", Store.Vertical.SERVICES,
                    Store.ServiceCategory.PRINTING));
        }

        private Store listed(Store store) {
            store.replaceHours(java.util.Arrays.stream(DayOfWeek.values())
                    .map(day -> new StoreHours(day, LocalTime.MIDNIGHT, LocalTime.of(23, 59, 59)))
                    .toList());
            store.publish(Instant.parse("2026-09-01T09:00:00Z"));
            return shop(store);
        }

        @Test
        void a_customer_reads_a_live_offer_of_a_listed_shop() {
            Product offer = offer(listedPress, Fulfilment.PICKUP, Product.Status.ACTIVE);

            assertThat(catalog.read(offer.getId(), "customer-sub")).isSameAs(offer);
        }

        /**
         * Order Manager reads and prices a line through here with the customer's token and knows no
         * category, so this is what stops such an offer being ordered by its id.
         */
        @Test
        void an_offer_in_a_category_the_platform_closed_is_not_found_by_anyone_but_its_provider() {
            Product offer = offer(listedPress, Fulfilment.PICKUP, Product.Status.ACTIVE);
            environment.setProperty(OPEN_CATEGORIES, "TAILORING,REPAIRS");

            assertThatThrownBy(() -> catalog.read(offer.getId(), "customer-sub"))
                    .isInstanceOf(ProductNotFoundException.class);
            assertThatThrownBy(() -> catalog.read(offer.getId(), null))
                    .isInstanceOf(ProductNotFoundException.class);
            assertThatThrownBy(() -> catalog.read(offer.getId(), RIVAL))
                    .isInstanceOf(ProductNotFoundException.class);
            assertThat(catalog.read(offer.getId(), PROVIDER)).isSameAs(offer);
        }

        @Test
        void an_offer_of_a_shop_in_a_category_that_never_opened_is_not_found() {
            Store cleaners = listed(new Store(PROVIDER, "Spotless Cleaners", Store.Vertical.SERVICES,
                    Store.ServiceCategory.CLEANING));
            Product offer = offer(cleaners, Fulfilment.PICKUP, Product.Status.ACTIVE);

            assertThatThrownBy(() -> catalog.read(offer.getId(), "customer-sub"))
                    .isInstanceOf(ProductNotFoundException.class);
        }

        @Test
        void an_offer_of_a_suspended_shop_is_not_found_and_its_provider_still_reads_it() {
            Product offer = offer(listedPress, Fulfilment.PICKUP, Product.Status.ACTIVE);
            listedPress.suspend();

            assertThatThrownBy(() -> catalog.read(offer.getId(), "customer-sub"))
                    .isInstanceOf(ProductNotFoundException.class);
            assertThat(catalog.read(offer.getId(), PROVIDER)).isSameAs(offer);
        }

        @Test
        void an_offer_of_a_shop_never_listed_is_not_found() {
            // The class's own fixture shops are drafts: created and never published.
            Product offer = offer(press, Fulfilment.PICKUP, Product.Status.ACTIVE);

            assertThatThrownBy(() -> catalog.read(offer.getId(), "customer-sub"))
                    .isInstanceOf(ProductNotFoundException.class);
        }

        /**
         * Goods are not judged by the services rules, and a broken category setting, which throws when
         * it is read, cannot reach them.
         */
        @Test
        void a_goods_product_reads_as_it_always_did() {
            Product dish = offer(grill, null, Product.Status.ACTIVE);
            environment.setProperty(OPEN_CATEGORIES, "PRINTNG");

            assertThat(catalog.read(dish.getId(), "customer-sub")).isSameAs(dish);
        }

        @Test
        void the_shelf_of_a_shop_that_is_not_listed_is_not_found_and_nothing_is_read_from_it() {
            listedPress.suspend();

            assertThatThrownBy(() -> catalog.browseStore(listedPress.getId(), "customer-sub", null, null,
                    PageRequest.of(0, 20)))
                    .isInstanceOf(StoreNotFoundException.class);
            assertThatThrownBy(() -> catalog.browseStoreByIds(listedPress.getId(), null,
                    List.of(UUID.randomUUID()), PageRequest.of(0, 20)))
                    .isInstanceOf(StoreNotFoundException.class);
            // Searched, the shelf goes to its own query (the item search's matching), and is refused first.
            assertThatThrownBy(() -> catalog.browseStore(listedPress.getId(), "customer-sub", null,
                    "cards", PageRequest.of(0, 20)))
                    .isInstanceOf(StoreNotFoundException.class);
            verify(products, never()).findActiveInStore(any(), any(), anyString(), any(Pageable.class));
            verify(products, never()).findActiveInStoreMatching(any(), anyBoolean(), any(), anyString(),
                    anyString(), any(Pageable.class));
            verify(products, never()).findActiveInStoreByIds(any(), any(), any(Pageable.class));
        }

        @Test
        void a_customer_sees_a_listed_shops_shelf_and_its_provider_sees_it_suspended() {
            when(products.findActiveInStore(any(), any(), anyString(), any(Pageable.class)))
                    .thenReturn(Page.empty());
            catalog.browseStore(listedPress.getId(), "customer-sub", null, null, PageRequest.of(0, 20));

            listedPress.suspend();
            catalog.browseStore(listedPress.getId(), PROVIDER, null, null, PageRequest.of(0, 20));

            verify(products, times(2)).findActiveInStore(eq(listedPress.getId()), any(), anyString(),
                    any(Pageable.class));
        }
    }

    @Nested
    @DisplayName("the dashboard's count of active offers")
    class TheStatusCount {

        @Test
        void a_status_narrows_the_merchants_own_list_and_the_count_is_the_databases() {
            Pageable oneRow = PageRequest.of(0, 1);
            Product live = offer(press, Fulfilment.BOTH, Product.Status.ACTIVE);
            when(products.findByMerchantIdAndStatus(PROVIDER, Product.Status.ACTIVE, oneRow))
                    .thenReturn(new PageImpl<>(List.of(live), oneRow, 3));

            assertThat(catalog.listOwnedBy(PROVIDER, null, Product.Status.ACTIVE, oneRow)
                    .getTotalElements())
                    .isEqualTo(3);
            verify(products, never()).findByMerchantId(anyString(), any(Pageable.class));
        }

        @Test
        void no_status_is_the_whole_list() {
            Pageable page = PageRequest.of(0, 20);
            when(products.findByMerchantId(PROVIDER, page)).thenReturn(new PageImpl<>(List.of()));

            catalog.listOwnedBy(PROVIDER, null, null, page);

            verify(products).findByMerchantId(PROVIDER, page);
            verify(products, never()).findByMerchantIdAndStatus(anyString(), any(), any(Pageable.class));
        }

        /**
         * "Active offers" is the service shop's. This account owns a grill as well, and its dishes are
         * not the provider's offers.
         */
        @Test
        void naming_one_of_the_merchants_shops_counts_that_shop_alone() {
            Pageable oneRow = PageRequest.of(0, 1);
            Product live = offer(press, Fulfilment.BOTH, Product.Status.ACTIVE);
            when(products.findByMerchantIdAndStoreIdAndStatus(PROVIDER, press.getId(),
                    Product.Status.ACTIVE, oneRow))
                    .thenReturn(new PageImpl<>(List.of(live), oneRow, 2));

            assertThat(catalog.listOwnedBy(PROVIDER, press.getId(), Product.Status.ACTIVE, oneRow)
                    .getTotalElements())
                    .isEqualTo(2);
            verify(products, never()).findByMerchantIdAndStatus(anyString(), any(), any(Pageable.class));
        }

        @Test
        void naming_a_shop_without_a_status_lists_that_shop_in_every_status() {
            Pageable page = PageRequest.of(0, 20);
            when(products.findByMerchantIdAndStoreId(PROVIDER, grill.getId(), page))
                    .thenReturn(new PageImpl<>(List.of()));

            catalog.listOwnedBy(PROVIDER, grill.getId(), null, page);

            verify(products).findByMerchantIdAndStoreId(PROVIDER, grill.getId(), page);
            verify(products, never()).findByMerchantId(anyString(), any(Pageable.class));
        }

        /** Another merchant's shop is indistinguishable from an id that was never issued. */
        @Test
        void a_shop_the_merchant_does_not_own_is_not_found_and_nothing_is_counted() {
            Store theirs = new Store(RIVAL, "Rival Press", Store.Vertical.SERVICES,
                    Store.ServiceCategory.PRINTING);

            assertThatThrownBy(() -> catalog.listOwnedBy(PROVIDER, theirs.getId(), Product.Status.ACTIVE,
                    PageRequest.of(0, 1)))
                    .isInstanceOf(StoreNotFoundException.class);
            verify(products, never()).findByMerchantIdAndStoreIdAndStatus(anyString(), any(), any(),
                    any(Pageable.class));
        }
    }

    @Nested
    @DisplayName("an offer's From price")
    class FromPrice {

        private ProductOptionGroup group(Product offer, int minSelect, int maxSelect, String... deltas) {
            ProductOptionGroup group = new ProductOptionGroup(offer.getId(), "Paper type", minSelect,
                    maxSelect, 0);
            List<ProductOption> options = new ArrayList<>();
            for (int i = 0; i < deltas.length; i++) {
                options.add(new ProductOption("Paper " + i, new BigDecimal(deltas[i]), false, i));
            }
            group.replaceOptions(options);
            return group;
        }

        private void optionsOf(ProductOptionGroup... groups) {
            when(optionGroups.findByProductIdInOrderByPositionAsc(any())).thenReturn(List.of(groups));
        }

        @Test
        void is_the_price_plus_the_cheapest_choice_a_customer_must_make() {
            Product offer = offer(press, Fulfilment.BOTH, Product.Status.ACTIVE);
            optionsOf(group(offer, 1, 1, "2.50", "0.75", "4.00"), group(offer, 0, 1, "1.00"));

            assertThat(catalog.view(offer).fromPrice()).isEqualTo(new BigDecimal("15.75"));
        }

        @Test
        void is_the_price_itself_when_nothing_required_adds_to_it() {
            Product offer = offer(press, Fulfilment.BOTH, Product.Status.ACTIVE);

            assertThat(catalog.view(offer).fromPrice()).isEqualTo(new BigDecimal("15.00"));
        }

        /** "No lamination -$1.00" lowers what the price endpoint charges, so it lowers "From" too. */
        @Test
        void counts_a_discount_any_customer_can_take() {
            Product offer = offer(press, Fulfilment.BOTH, Product.Status.ACTIVE);
            optionsOf(group(offer, 0, 1, "-1.00", "3.00"));

            assertThat(catalog.view(offer).fromPrice()).isEqualTo(new BigDecimal("14.00"));
        }

        @Test
        void a_choose_two_group_adds_its_two_cheapest() {
            Product offer = offer(press, Fulfilment.BOTH, Product.Status.ACTIVE);
            optionsOf(group(offer, 2, 3, "5.00", "1.00", "2.00"));

            assertThat(catalog.view(offer).fromPrice()).isEqualTo(new BigDecimal("18.00"));
        }

        @Test
        void never_goes_below_zero() {
            Product offer = offer(press, Fulfilment.BOTH, Product.Status.ACTIVE);
            optionsOf(group(offer, 1, 1, "-20.00"));

            assertThat(catalog.view(offer).fromPrice()).isEqualTo(new BigDecimal("0.00"));
        }

        @Test
        void a_goods_product_has_no_terms_and_no_from_price_and_its_options_are_never_read() {
            Product dish = offer(grill, null, Product.Status.ACTIVE);

            ProductView view = catalog.view(dish);

            assertThat(view.service()).isNull();
            assertThat(view.fromPrice()).isNull();
            verify(optionGroups, never()).findByProductIdInOrderByPositionAsc(any());
        }

        @Test
        void a_page_reads_every_offers_terms_and_options_in_one_query_each_and_keeps_its_order() {
            Product cards = offer(press, Fulfilment.BOTH, Product.Status.ACTIVE);
            Product dish = offer(grill, null, Product.Status.ACTIVE);
            Product banner = offer(press, Fulfilment.PICKUP, Product.Status.ACTIVE);

            List<ProductView> views = catalog.views(List.of(cards, dish, banner));

            assertThat(views).extracting(view -> view.product().getId())
                    .containsExactly(cards.getId(), dish.getId(), banner.getId());
            assertThat(views).extracting(view -> view.service() != null)
                    .containsExactly(true, false, true);
            verify(serviceTerms, times(1)).findAllById(any());
            verify(optionGroups, times(1)).findByProductIdInOrderByPositionAsc(any());
        }
    }
}
