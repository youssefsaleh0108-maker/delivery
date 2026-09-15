package com.delivery.product.service;

import java.lang.reflect.Method;
import java.math.BigDecimal;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.EnumSet;
import java.util.List;
import java.util.Optional;
import java.util.Set;
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
import org.springframework.data.domain.Sort;
import org.springframework.mock.env.MockEnvironment;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.platform.outbox.OutboxRecorder;
import com.delivery.product.api.dto.CatalogDtos.ProductRequest;
import com.delivery.product.api.dto.CatalogDtos.ServiceTermsRequest;
import com.delivery.product.domain.CategoryRepository;
import com.delivery.product.domain.OfferModerationAction;
import com.delivery.product.domain.OfferModerationActionRepository;
import com.delivery.product.domain.Product;
import com.delivery.product.domain.ProductOptionGroupRepository;
import com.delivery.product.domain.ProductRepository;
import com.delivery.product.domain.ServiceTerms;
import com.delivery.product.domain.ServiceTermsRepository;
import com.delivery.product.domain.Store;
import com.delivery.product.domain.StoreDeliveryZoneRepository;
import com.delivery.product.domain.StoreRepository;
import com.delivery.product.event.CatalogEvents;
import com.delivery.product.event.CatalogEvents.ProductSnapshot;
import com.delivery.product.service.CatalogService.CatalogRuleViolationException;
import com.delivery.product.service.CatalogService.ProductNotFoundException;
import com.delivery.product.service.OfferModerationService.ModeratedOffer;
import com.delivery.product.service.OfferModerationService.Moderator;
import com.delivery.product.service.OfferModerationService.StatusFilter;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyBoolean;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Back office's take-down and restore of service offers, and what an offer's provider can do in between.
 *
 * <p>A real {@link OfferModerationService} over a real {@link CatalogService}, with mocked repositories.
 * The provider's publish, resume and pause are therefore refused by the rule the service applies, not by
 * a stub. What only a database can show is in {@code OfferModerationDatabaseTest}: the trail rolling back
 * with its act, the CHECK that stops a stale save, and what the list's SQL answers.
 */
@DisplayName("back office takes service offers down and restores them")
class OfferModerationTest {

    private static final String PROVIDER = "keycloak-sub-provider";
    private static final Instant NOW = Instant.parse("2026-09-14T09:30:00Z");
    private static final Moderator OPS = new Moderator("keycloak-sub-ops", "rana.ops");
    private static final String REASON = "Prints copies of official exam papers.";

    private ProductRepository products;
    private StoreRepository stores;
    private ServiceTermsRepository serviceTerms;
    private OfferModerationActionRepository actions;
    private OutboxRecorder outbox;
    private CatalogService catalog;
    private OfferModerationService moderation;
    private Store press;

    /** Live, and on the gift hub. */
    private Product offer;

    @BeforeEach
    void setUp() {
        products = mock(ProductRepository.class);
        stores = mock(StoreRepository.class);
        serviceTerms = mock(ServiceTermsRepository.class);
        actions = mock(OfferModerationActionRepository.class);
        outbox = mock(OutboxRecorder.class);

        press = new Store(PROVIDER, "Al Fakhry Press", Store.Vertical.SERVICES, Store.ServiceCategory.PRINTING);
        when(stores.findById(press.getId())).thenReturn(Optional.of(press));
        when(actions.save(any(OfferModerationAction.class))).thenAnswer(call -> call.getArgument(0));

        offer = offerOfThePress();
        offer.publish();
        offer.featureAsGift(NOW.minusSeconds(3_600));

        catalog = new CatalogService(products, mock(CategoryRepository.class), mock(StoreService.class),
                outbox, stores, serviceTerms, mock(StoreDeliveryZoneRepository.class),
                mock(ProductOptionGroupRepository.class), new ServiceCategories(new MockEnvironment()));
        moderation = new OfferModerationService(products, stores, serviceTerms, actions, catalog, outbox,
                Clock.fixed(NOW, ZoneOffset.UTC));
    }

    /** A draft pickup print offer with a photo, known to every read the acts and its provider's calls make. */
    private Product offerOfThePress() {
        Product product = new Product(PROVIDER, press.getId(), "Business card printing", null,
                new BigDecimal("15.00"), null);
        product.addImage("products/cards.jpg");
        ServiceTerms terms = new ServiceTerms(product.getId(), ServiceTerms.PricingType.FIXED, "cards", 500, 24,
                48, ServiceTerms.Fulfilment.PICKUP, ServiceTerms.AttachmentPolicy.NONE, null);
        when(products.findForModerationById(product.getId())).thenReturn(Optional.of(product));
        when(products.findByIdAndMerchantId(product.getId(), PROVIDER)).thenReturn(Optional.of(product));
        when(products.existsById(product.getId())).thenReturn(true);
        when(serviceTerms.findById(product.getId())).thenReturn(Optional.of(terms));
        when(serviceTerms.findAllById(List.of(product.getId()))).thenReturn(List.of(terms));
        return product;
    }

    private static ServiceTermsRequest pickupTerms() {
        return new ServiceTermsRequest(ServiceTerms.PricingType.FIXED, "cards", 500, 24, 48,
                ServiceTerms.Fulfilment.PICKUP, ServiceTerms.AttachmentPolicy.NONE, null);
    }

    @Nested
    @DisplayName("taking an offer down")
    class TakingDown {

        @Test
        @DisplayName("a live offer goes off sale and off the gift hub, held with the reason its provider reads")
        void a_live_offer_goes_off_sale_and_is_held() {
            ModeratedOffer result = moderation.takeDown(offer.getId(), OPS, "  " + REASON + "  ");

            assertThat(offer.getStatus()).isEqualTo(Product.Status.ARCHIVED);
            assertThat(offer.isTakenDown()).isTrue();
            assertThat(offer.getTakedownReason()).isEqualTo(REASON);
            assertThat(offer.getTakenDownAt()).isEqualTo(NOW);
            assertThat(offer.getStatusBeforeTakedown()).isEqualTo(Product.Status.ACTIVE);
            assertThat(offer.isGiftFeatured()).isFalse();
            assertThat(result.store()).isSameAs(press);
            assertThat(result.view().product()).isSameAs(offer);
            assertThat(result.view().service()).isNotNull();
        }

        @Test
        @DisplayName("the trail says who acted, when, why, what was done, and to which offer of which shop")
        void the_trail_names_who_when_why_what_and_whose() {
            moderation.takeDown(offer.getId(), OPS, REASON);

            ArgumentCaptor<OfferModerationAction> written = ArgumentCaptor.forClass(OfferModerationAction.class);
            verify(actions).save(written.capture());
            OfferModerationAction act = written.getValue();
            assertThat(act.getAction()).isEqualTo(OfferModerationAction.Action.TAKE_DOWN);
            assertThat(act.getActorId()).isEqualTo("keycloak-sub-ops");
            assertThat(act.getActorName()).isEqualTo("rana.ops");
            assertThat(act.getCreatedAt()).isEqualTo(NOW);
            assertThat(act.getReason()).isEqualTo(REASON);
            assertThat(act.getProductId()).isEqualTo(offer.getId());
            assertThat(act.getStoreId()).isEqualTo(press.getId());
        }

        @Test
        @DisplayName("the offer is read with its row locked, and the act is recorded as an archive")
        void the_offer_is_locked_and_the_act_recorded_as_an_archive() {
            moderation.takeDown(offer.getId(), OPS, REASON);

            verify(products).findForModerationById(offer.getId());
            ArgumentCaptor<Object> snapshot = ArgumentCaptor.forClass(Object.class);
            verify(outbox).record(eq(CatalogEvents.AGGREGATE_TYPE), eq(offer.getId().toString()),
                    eq(CatalogEvents.PRODUCT_ARCHIVED), snapshot.capture());
            assertThat(((ProductSnapshot) snapshot.getValue()).status()).isEqualTo(Product.Status.ARCHIVED);
            assertThat(((ProductSnapshot) snapshot.getValue()).service()).isNotNull();
        }

        @Test
        @DisplayName("an offer in any status can be taken down, and remembers the status it was in")
        void an_offer_in_any_status_can_be_taken_down() {
            Product draft = offerOfThePress();
            Product paused = offerOfThePress();
            paused.publish();
            paused.pause();
            Product archived = offerOfThePress();
            archived.archive();

            for (Product product : List.of(draft, paused, archived)) {
                Product.Status was = product.getStatus();
                moderation.takeDown(product.getId(), OPS, REASON);
                assertThat(product.getStatus()).as("was %s", was).isEqualTo(Product.Status.ARCHIVED);
                assertThat(product.getStatusBeforeTakedown()).as("was %s", was).isEqualTo(was);
            }
        }

        @Test
        @DisplayName("a goods product is refused, and nothing is written")
        void a_goods_product_is_refused() {
            Store grocer = new Store("merchant-grocer", "Abu Hassan Mini Market", Store.Vertical.GROCERY);
            when(stores.findById(grocer.getId())).thenReturn(Optional.of(grocer));
            Product milk = new Product(grocer.getMerchantId(), grocer.getId(), "Milk", null,
                    new BigDecimal("1.50"), null);
            milk.addImage("products/milk.jpg");
            milk.publish();
            when(products.findForModerationById(milk.getId())).thenReturn(Optional.of(milk));

            assertThatThrownBy(() -> moderation.takeDown(milk.getId(), OPS, REASON))
                    .isInstanceOf(CatalogRuleViolationException.class)
                    .hasMessageContaining("goods shop");

            assertThat(milk.getStatus()).isEqualTo(Product.Status.ACTIVE);
            assertThat(milk.isTakenDown()).isFalse();
            verify(actions, never()).save(any());
            verify(outbox, never()).record(anyString(), anyString(), anyString(), any());
        }

        @Test
        @DisplayName("an offer already taken down is refused, and keeps the reason its provider was given")
        void an_offer_already_taken_down_is_refused() {
            moderation.takeDown(offer.getId(), OPS, REASON);

            assertThatThrownBy(() -> moderation.takeDown(offer.getId(), OPS, "Another reason."))
                    .isInstanceOf(CatalogRuleViolationException.class)
                    .hasMessageContaining("already taken down");

            assertThat(offer.getTakedownReason()).isEqualTo(REASON);
            assertThat(offer.getStatusBeforeTakedown()).isEqualTo(Product.Status.ACTIVE);
            verify(actions, times(1)).save(any());
        }

        @Test
        @DisplayName("a missing, blank or overlong reason is refused before anything changes")
        void a_reason_is_required() {
            String tooLong = "x".repeat(Product.MAX_TAKEDOWN_REASON_LENGTH + 1);
            for (String reason : new String[] {null, "", "   ", tooLong}) {
                assertThatThrownBy(() -> moderation.takeDown(offer.getId(), OPS, reason))
                        .as("%s", reason)
                        .isInstanceOf(CatalogRuleViolationException.class);
            }
            assertThat(offer.getStatus()).isEqualTo(Product.Status.ACTIVE);
            assertThat(offer.isTakenDown()).isFalse();
            assertThat(offer.isGiftFeatured()).isTrue();
            verify(actions, never()).save(any());

            // The longest reason allowed is kept whole.
            moderation.takeDown(offer.getId(), OPS, "x".repeat(Product.MAX_TAKEDOWN_REASON_LENGTH));
            assertThat(offer.getTakedownReason()).hasSize(Product.MAX_TAKEDOWN_REASON_LENGTH);
        }

        @Test
        @DisplayName("an id that names no product is not found, for every act and for the trail")
        void an_unknown_id_is_not_found() {
            UUID nothing = UUID.randomUUID();

            assertThatThrownBy(() -> moderation.takeDown(nothing, OPS, REASON))
                    .isInstanceOf(ProductNotFoundException.class);
            assertThatThrownBy(() -> moderation.restore(nothing, OPS, REASON))
                    .isInstanceOf(ProductNotFoundException.class);
            assertThatThrownBy(() -> moderation.history(nothing))
                    .isInstanceOf(ProductNotFoundException.class);
            verify(actions, never()).save(any());
        }
    }

    @Nested
    @DisplayName("while an offer is taken down")
    class WhileTakenDown {

        @BeforeEach
        void takenDown() {
            moderation.takeDown(offer.getId(), OPS, REASON);
        }

        @Test
        @DisplayName("its provider cannot publish, resume or pause it, and is told back office's reason")
        void its_provider_cannot_put_it_back_on_sale() {
            assertThatThrownBy(() -> catalog.publish(offer.getId(), PROVIDER))
                    .isInstanceOf(CatalogRuleViolationException.class)
                    .hasMessageContaining(REASON);
            assertThatThrownBy(() -> catalog.resume(offer.getId(), PROVIDER))
                    .isInstanceOf(CatalogRuleViolationException.class)
                    .hasMessageContaining(REASON);
            assertThatThrownBy(() -> catalog.pause(offer.getId(), PROVIDER))
                    .isInstanceOf(CatalogRuleViolationException.class)
                    .hasMessageContaining(REASON);

            assertThat(offer.getStatus()).isEqualTo(Product.Status.ARCHIVED);
            assertThat(offer.isTakenDown()).isTrue();
        }

        @Test
        @DisplayName("its provider can still fix what back office objected to, which puts nothing on sale")
        void its_provider_can_still_fix_it() {
            catalog.update(offer.getId(), PROVIDER, new ProductRequest("Business cards, matte", null,
                    new BigDecimal("16.00"), null, null, null, null, pickupTerms()));

            assertThat(offer.getName()).isEqualTo("Business cards, matte");
            assertThat(offer.getStatus()).isEqualTo(Product.Status.ARCHIVED);
            assertThat(offer.isTakenDown()).isTrue();
        }

        @Test
        @DisplayName("its provider archiving it for good is kept through a restore")
        void archived_by_its_provider_stays_archived() {
            catalog.archive(offer.getId(), PROVIDER);
            assertThat(offer.isTakenDown()).isTrue();

            moderation.restore(offer.getId(), OPS, "Reviewed.");

            assertThat(offer.getStatus()).isEqualTo(Product.Status.ARCHIVED);
            assertThat(offer.isTakenDown()).isFalse();
        }
    }

    @Nested
    @DisplayName("restoring an offer")
    class Restoring {

        @Test
        @DisplayName("an offer that was on sale comes back paused, and its provider resumes it")
        void an_offer_that_was_on_sale_comes_back_paused() {
            moderation.takeDown(offer.getId(), OPS, REASON);

            ModeratedOffer result = moderation.restore(offer.getId(), OPS, "The provider replaced the photos.");

            assertThat(offer.getStatus()).isEqualTo(Product.Status.PAUSED);
            assertThat(offer.isTakenDown()).isFalse();
            assertThat(offer.getTakedownReason()).isNull();
            assertThat(offer.getTakenDownAt()).isNull();
            assertThat(offer.getStatusBeforeTakedown()).isNull();
            assertThat(result.view().product().getStatus()).isEqualTo(Product.Status.PAUSED);

            // Back office did not put it in front of customers. Its provider does, under the publishing rules.
            catalog.resume(offer.getId(), PROVIDER);
            assertThat(offer.getStatus()).isEqualTo(Product.Status.ACTIVE);
            // And it stays off the gift hub until somebody picks it again.
            assertThat(offer.isGiftFeatured()).isFalse();
        }

        @Test
        @DisplayName("a draft, a paused or an archived offer comes back as it was")
        void anything_else_comes_back_as_it_was() {
            Product draft = offerOfThePress();
            Product paused = offerOfThePress();
            paused.publish();
            paused.pause();
            Product archived = offerOfThePress();
            archived.publish();
            archived.archive();

            for (Product product : List.of(draft, paused, archived)) {
                Product.Status was = product.getStatus();
                moderation.takeDown(product.getId(), OPS, REASON);
                moderation.restore(product.getId(), OPS, "Reviewed and allowed.");
                assertThat(product.getStatus()).as("was %s", was).isEqualTo(was);
                assertThat(product.isTakenDown()).as("was %s", was).isFalse();
            }
        }

        @Test
        @DisplayName("the restore is on the trail, and recorded as an update carrying the status the offer is back in")
        void the_restore_is_on_the_trail() {
            moderation.takeDown(offer.getId(), OPS, REASON);
            moderation.restore(offer.getId(), new Moderator("keycloak-sub-lead", null),
                    "  The provider replaced the photos.  ");

            ArgumentCaptor<OfferModerationAction> written = ArgumentCaptor.forClass(OfferModerationAction.class);
            verify(actions, times(2)).save(written.capture());
            OfferModerationAction act = written.getAllValues().get(1);
            assertThat(act.getAction()).isEqualTo(OfferModerationAction.Action.RESTORE);
            assertThat(act.getReason()).isEqualTo("The provider replaced the photos.");
            assertThat(act.getActorId()).isEqualTo("keycloak-sub-lead");
            assertThat(act.getActorName()).isNull();
            assertThat(act.getCreatedAt()).isEqualTo(NOW);
            assertThat(act.getProductId()).isEqualTo(offer.getId());
            assertThat(act.getStoreId()).isEqualTo(press.getId());

            ArgumentCaptor<Object> snapshot = ArgumentCaptor.forClass(Object.class);
            verify(outbox).record(eq(CatalogEvents.AGGREGATE_TYPE), eq(offer.getId().toString()),
                    eq(CatalogEvents.PRODUCT_UPDATED), snapshot.capture());
            assertThat(((ProductSnapshot) snapshot.getValue()).status()).isEqualTo(Product.Status.PAUSED);
        }

        @Test
        @DisplayName("an offer that is not taken down is refused, and nothing is written")
        void an_offer_that_is_not_taken_down_is_refused() {
            assertThatThrownBy(() -> moderation.restore(offer.getId(), OPS, "Reviewed."))
                    .isInstanceOf(CatalogRuleViolationException.class)
                    .hasMessageContaining("not taken down");

            assertThat(offer.getStatus()).isEqualTo(Product.Status.ACTIVE);
            verify(actions, never()).save(any());
            verify(outbox, never()).record(anyString(), anyString(), anyString(), any());
        }

        @Test
        @DisplayName("a restore without a reason is refused, and the offer stays taken down")
        void a_restore_needs_a_reason() {
            moderation.takeDown(offer.getId(), OPS, REASON);

            assertThatThrownBy(() -> moderation.restore(offer.getId(), OPS, "   "))
                    .isInstanceOf(CatalogRuleViolationException.class);

            assertThat(offer.isTakenDown()).isTrue();
            assertThat(offer.getStatus()).isEqualTo(Product.Status.ARCHIVED);
            verify(actions, times(1)).save(any());
        }
    }

    @Nested
    @DisplayName("the trail and the list")
    class Reads {

        @Test
        @DisplayName("an offer's trail is read newest first")
        void an_offers_trail() {
            OfferModerationAction act = new OfferModerationAction(offer, OfferModerationAction.Action.TAKE_DOWN,
                    REASON, "keycloak-sub-ops", null, NOW);
            when(actions.findByProductIdOrderByCreatedAtDesc(offer.getId())).thenReturn(List.of(act));

            assertThat(moderation.history(offer.getId())).containsExactly(act);
        }

        @Test
        @DisplayName("each status reaches the query, with archived and taken down told apart")
        void each_status_reaches_the_query() {
            when(products.findServiceOffersForBackoffice(any(), anyBoolean(), anyBoolean(), any(), any(),
                    anyString(), any(Pageable.class))).thenReturn(Page.empty());
            PageRequest page = PageRequest.of(0, 20);

            moderation.list(null, null, null, null, page);
            verify(products).findServiceOffersForBackoffice(eq(EnumSet.allOf(Product.Status.class)), eq(false),
                    eq(false), eq(EnumSet.allOf(Store.ServiceCategory.class)), isNull(), eq("%"), any(Pageable.class));

            moderation.list(StatusFilter.TAKEN_DOWN, null, null, null, page);
            verify(products).findServiceOffersForBackoffice(eq(Set.of(Product.Status.ARCHIVED)), eq(true),
                    eq(false), any(), any(), anyString(), any(Pageable.class));

            moderation.list(StatusFilter.ARCHIVED, null, null, null, page);
            verify(products).findServiceOffersForBackoffice(eq(Set.of(Product.Status.ARCHIVED)), eq(false),
                    eq(true), any(), any(), anyString(), any(Pageable.class));

            moderation.list(StatusFilter.PAUSED, null, null, null, page);
            verify(products).findServiceOffersForBackoffice(eq(Set.of(Product.Status.PAUSED)), eq(false),
                    eq(false), any(), any(), anyString(), any(Pageable.class));
        }

        @Test
        @DisplayName("a category, a shop and text reach the query, and the page is tie-broken by id")
        void the_other_filters_reach_the_query() {
            when(products.findServiceOffersForBackoffice(any(), anyBoolean(), anyBoolean(), any(), any(),
                    anyString(), any(Pageable.class))).thenReturn(Page.empty());
            UUID shop = UUID.randomUUID();

            moderation.list(null, Store.ServiceCategory.CLEANING, shop, "50%_Off",
                    PageRequest.of(1, 10, Sort.by(Sort.Direction.DESC, "createdAt")));

            ArgumentCaptor<Pageable> page = ArgumentCaptor.forClass(Pageable.class);
            verify(products).findServiceOffersForBackoffice(any(), eq(false), eq(false),
                    eq(Set.of(Store.ServiceCategory.CLEANING)), eq(shop), eq("%50\\%\\_off%"), page.capture());
            assertThat(page.getValue().getPageNumber()).isEqualTo(1);
            assertThat(page.getValue().getPageSize()).isEqualTo(10);
            assertThat(page.getValue().getSort())
                    .containsExactly(Sort.Order.desc("createdAt"), Sort.Order.asc("id"));
        }

        @Test
        @DisplayName("each offer on a page comes with its view and its shop, and the page keeps its numbering")
        void each_offer_comes_with_its_view_and_its_shop() {
            when(products.findServiceOffersForBackoffice(any(), anyBoolean(), anyBoolean(), any(), any(),
                    anyString(), any(Pageable.class)))
                    .thenReturn(new PageImpl<>(List.of(offer), PageRequest.of(2, 1), 7));
            when(stores.findAllById(Set.of(press.getId()))).thenReturn(List.of(press));

            Page<ModeratedOffer> page = moderation.list(null, null, null, null, PageRequest.of(2, 1));

            assertThat(page.getTotalElements()).isEqualTo(7);
            assertThat(page.getNumber()).isEqualTo(2);
            assertThat(page.getContent()).singleElement().satisfies(moderated -> {
                assertThat(moderated.store()).isSameAs(press);
                assertThat(moderated.view().product()).isSameAs(offer);
                assertThat(moderated.view().service()).isNotNull();
            });
        }
    }

    @Nested
    @DisplayName("by shape")
    class ByShape {

        /**
         * A transaction boundary is not something a mocked suite can watch, so its shape is pinned, as
         * {@code StoreServiceTest} pins the first shop's. Each act is one writing transaction, and its trail
         * row is written inside it; the reads write nothing. {@code OfferModerationDatabaseTest} shows an act
         * rolling back when its trail row cannot be written.
         */
        @Test
        @DisplayName("each act is one writing transaction, and the reads are read-only")
        void each_act_is_one_writing_transaction() throws NoSuchMethodException {
            for (Method act : List.of(
                    OfferModerationService.class.getMethod("takeDown", UUID.class, Moderator.class, String.class),
                    OfferModerationService.class.getMethod("restore", UUID.class, Moderator.class, String.class))) {
                assertThat(act.getAnnotation(Transactional.class)).as("%s", act).isNotNull();
                assertThat(act.getAnnotation(Transactional.class).readOnly()).as("%s", act).isFalse();
            }
            for (Method read : List.of(
                    OfferModerationService.class.getMethod("list", StatusFilter.class,
                            Store.ServiceCategory.class, UUID.class, String.class, Pageable.class),
                    OfferModerationService.class.getMethod("history", UUID.class))) {
                assertThat(read.getAnnotation(Transactional.class).readOnly()).as("%s", read).isTrue();
            }
        }
    }
}
