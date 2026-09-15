package com.delivery.product.service;

import java.time.Clock;
import java.time.Instant;
import java.util.EnumSet;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.platform.outbox.OutboxRecorder;
import com.delivery.product.domain.OfferModerationAction;
import com.delivery.product.domain.OfferModerationActionRepository;
import com.delivery.product.domain.Product;
import com.delivery.product.domain.ProductRepository;
import com.delivery.product.domain.ServiceTermsRepository;
import com.delivery.product.domain.Store;
import com.delivery.product.domain.StoreRepository;
import com.delivery.product.event.CatalogEvents;
import com.delivery.product.service.CatalogService.CatalogRuleViolationException;
import com.delivery.product.service.CatalogService.ProductNotFoundException;
import com.delivery.product.service.CatalogService.ProductView;

/**
 * Back office's hand on service offers (V36): the list of every service shop's offers, taking an offer
 * down with a reason, restoring it, and the trail of both.
 *
 * <p>BACKOFFICE only, decided by {@code OfferModerationController}'s role checks. Nothing here is scoped to
 * an owner, because nothing here is an owner's.
 *
 * <p>Each act writes its trail row ({@link OfferModerationAction}) in the same transaction as the act.
 * If the row cannot be written, the transaction rolls back and the offer is as it was, so an act nobody
 * can account for never happens. Each act first locks the offer's row
 * ({@link ProductRepository#findForModerationById}), so two staff acting at once are taken in turn.
 *
 * <p>Service offers only; a goods product is refused (422). The goods merchant apps know nothing of a
 * hold. They would show their merchant an archived product with no word of why, and moderating goods is
 * not part of the services build.
 */
@Service
public class OfferModerationService {

    private static final Logger log = LoggerFactory.getLogger(OfferModerationService.class);

    /**
     * Back office's status filter. The product statuses, with ARCHIVED split in two: archived by the
     * provider, and taken down by back office. Every offer is in exactly one.
     */
    public enum StatusFilter {
        DRAFT(Product.Status.DRAFT),
        ACTIVE(Product.Status.ACTIVE),
        PAUSED(Product.Status.PAUSED),
        /** Archived by its provider, and not taken down. */
        ARCHIVED(Product.Status.ARCHIVED),
        /** Taken down by back office and not yet restored. Always ARCHIVED ({@link Product#takeDown}). */
        TAKEN_DOWN(Product.Status.ARCHIVED);

        private final Product.Status status;

        StatusFilter(Product.Status status) {
            this.status = status;
        }
    }

    /** An offer as back office sees it: its view, and the shop it sits in. */
    public record ModeratedOffer(ProductView view, Store store) {
    }

    /** Who acted, as their token says. The name is null when the token carried none. */
    public record Moderator(String id, String name) {
    }

    private final ProductRepository products;
    private final StoreRepository stores;
    private final ServiceTermsRepository serviceTerms;
    private final OfferModerationActionRepository actions;
    private final CatalogService catalog;
    private final OutboxRecorder outbox;
    private final Clock clock;

    public OfferModerationService(ProductRepository products, StoreRepository stores,
                                  ServiceTermsRepository serviceTerms,
                                  OfferModerationActionRepository actions, CatalogService catalog,
                                  OutboxRecorder outbox, Clock clock) {
        this.products = products;
        this.stores = stores;
        this.serviceTerms = serviceTerms;
        this.actions = actions;
        this.catalog = catalog;
        this.outbox = outbox;
        this.clock = clock;
    }

    /**
     * Every service shop's offers, newest first unless the page says otherwise, narrowed by any of: a
     * status (including taken down), a service category, a shop, and text in the offer's or the shop's
     * name.
     *
     * <p>Back office's catalogue lost service offers when V33 took them off the goods catalogue read,
     * and the services search shows only what a customer may see. This is the read back office moderates
     * from. It includes draft and suspended shops, closed categories, paused and archived offers, and
     * taken-down offers. It never includes a goods product.
     *
     * @param status          one status, or null for all of them
     * @param serviceCategory one category, open or closed, or null for all of them
     * @param storeId         one shop, or null for every shop; a shop that is not a service shop lists nothing
     * @param search          matched against the offer's name and its shop's name; blank matches everything
     */
    @Transactional(readOnly = true)
    public Page<ModeratedOffer> list(StatusFilter status, Store.ServiceCategory serviceCategory,
                                     UUID storeId, String search, Pageable pageable) {
        Set<Product.Status> statuses = status == null
                ? EnumSet.allOf(Product.Status.class)
                : EnumSet.of(status.status);
        Set<Store.ServiceCategory> categories = serviceCategory == null
                ? EnumSet.allOf(Store.ServiceCategory.class)
                : EnumSet.of(serviceCategory);
        Page<Product> page = products.findServiceOffersForBackoffice(statuses,
                status == StatusFilter.TAKEN_DOWN, status == StatusFilter.ARCHIVED, categories, storeId,
                SearchPatterns.like(search), ServiceOfferSearch.tieBroken(pageable));
        return withShops(page);
    }

    /**
     * Takes a service offer down: off sale for every customer at once, and held there until back office
     * restores it ({@link Product#takeDown}). Its provider reads the reason on the offer.
     *
     * <p>Recorded as {@code product.archived}, whose snapshot says ARCHIVED, as the provider's own archive
     * is recorded: a consumer that follows archives needs nothing new to take the offer off sale.
     *
     * @throws ProductNotFoundException     when no product has this id (404)
     * @throws CatalogRuleViolationException when the product is not a service offer, is already taken
     *                                       down, or the reason is blank or too long (422)
     */
    @Transactional
    public ModeratedOffer takeDown(UUID productId, Moderator moderator, String reason) {
        Product offer = lockedProduct(productId);
        Store shop = serviceShopOf(offer, "taken down");
        Instant now = clock.instant();
        OfferModerationAction act = record(offer, OfferModerationAction.Action.TAKE_DOWN, reason, moderator, now);
        try {
            offer.takeDown(act.getReason(), now);
        } catch (IllegalStateException | IllegalArgumentException e) {
            throw new CatalogRuleViolationException(e.getMessage());
        }
        actions.save(act);

        outbox.record(CatalogEvents.AGGREGATE_TYPE, offer.getId().toString(),
                CatalogEvents.PRODUCT_ARCHIVED,
                CatalogEvents.ProductSnapshot.of(offer, serviceTerms.findById(productId).orElse(null)));
        log.info("Backoffice {} took offer {} of store {} down", moderator.id(), productId, shop.getId());
        return new ModeratedOffer(catalog.view(offer), shop);
    }

    /**
     * Lifts back office's hold. The offer returns to what it was, and an offer that was on sale comes back
     * PAUSED, for its provider to resume under the publishing rules ({@link Product#restore}).
     *
     * <p>Recorded as {@code product.updated}, whose snapshot carries the status the offer is back in, as
     * pausing and resuming are recorded.
     *
     * @throws ProductNotFoundException     when no product has this id (404)
     * @throws CatalogRuleViolationException when the product is not a service offer, is not taken down, or
     *                                       the reason is blank or too long (422)
     */
    @Transactional
    public ModeratedOffer restore(UUID productId, Moderator moderator, String reason) {
        Product offer = lockedProduct(productId);
        Store shop = serviceShopOf(offer, "restored");
        OfferModerationAction act = record(offer, OfferModerationAction.Action.RESTORE, reason, moderator,
                clock.instant());
        try {
            offer.restore();
        } catch (IllegalStateException e) {
            throw new CatalogRuleViolationException(e.getMessage());
        }
        actions.save(act);

        outbox.record(CatalogEvents.AGGREGATE_TYPE, offer.getId().toString(),
                CatalogEvents.PRODUCT_UPDATED,
                CatalogEvents.ProductSnapshot.of(offer, serviceTerms.findById(productId).orElse(null)));
        log.info("Backoffice {} restored offer {} of store {} to {}", moderator.id(), productId,
                shop.getId(), offer.getStatus());
        return new ModeratedOffer(catalog.view(offer), shop);
    }

    /**
     * One offer's trail, newest act first. An offer never acted on has an empty one.
     *
     * @throws ProductNotFoundException when no product has this id (404)
     */
    @Transactional(readOnly = true)
    public List<OfferModerationAction> history(UUID productId) {
        if (!products.existsById(productId)) {
            throw new ProductNotFoundException(productId);
        }
        return actions.findByProductIdOrderByCreatedAtDesc(productId);
    }

    // ---------------------------------------------------------------- internals

    private Product lockedProduct(UUID id) {
        return products.findForModerationById(id).orElseThrow(() -> new ProductNotFoundException(id));
    }

    /** The offer's shop, which must be a service shop: only a service offer is moderated here. */
    private Store serviceShopOf(Product product, String act) {
        Store shop = stores.findById(product.getStoreId())
                .orElseThrow(() -> new StoreService.StoreNotFoundException(product.getStoreId().toString()));
        if (!shop.isServices()) {
            throw new CatalogRuleViolationException("Only a service offer can be " + act
                    + " by back office, and this product is in a goods shop.");
        }
        return shop;
    }

    /**
     * The trail row for an act, built before the act is applied, so a reason the trail cannot hold refuses
     * the whole act rather than leaving an offer changed with nothing to say why.
     */
    private static OfferModerationAction record(Product offer, OfferModerationAction.Action action,
                                                String reason, Moderator moderator, Instant at) {
        try {
            return new OfferModerationAction(offer, action, reason, moderator.id(), moderator.name(), at);
        } catch (IllegalArgumentException e) {
            throw new CatalogRuleViolationException(e.getMessage());
        }
    }

    /** A page of offers with their views and shops, keeping the page's numbering. */
    private Page<ModeratedOffer> withShops(Page<Product> page) {
        Map<UUID, Store> shops = new HashMap<>();
        stores.findAllById(page.getContent().stream().map(Product::getStoreId).collect(Collectors.toSet()))
                .forEach(shop -> shops.put(shop.getId(), shop));
        List<ModeratedOffer> offers = catalog.views(page.getContent()).stream()
                .map(view -> new ModeratedOffer(view, shops.get(view.product().getStoreId())))
                .toList();
        return new PageImpl<>(offers, page.getPageable(), page.getTotalElements());
    }
}
