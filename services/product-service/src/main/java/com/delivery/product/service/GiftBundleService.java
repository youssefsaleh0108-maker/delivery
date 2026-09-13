package com.delivery.product.service;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.function.Function;
import java.util.stream.Collectors;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.product.domain.Product;
import com.delivery.product.domain.ProductRepository;
import com.delivery.product.domain.Store;
import com.delivery.product.domain.StoreRepository;
import com.delivery.product.service.CatalogService.CatalogRuleViolationException;
import com.delivery.product.service.CatalogService.ProductNotFoundException;

/**
 * The gift hub's "Featured Care Bundles" (Figma 112:1684): which products it shows, and the back
 * office's hand on that choice.
 *
 * <p><strong>A bundle is an ordinary product.</strong> A "Family Essentials" box a grocery already
 * sells, picked by the back office (V31). It is priced, stocked and ordered like any other product,
 * from one shop, so the hub can never show a price checkout would not charge — and a bundle from
 * several shops, which the one-shop basket cannot hold, cannot be expressed at all.
 *
 * <p><strong>Only what a customer could actually buy reaches the hub.</strong> The query narrows to
 * featured, live products; the shops are then checked here, where it is testable: a product whose
 * shop is a draft or has been suspended by an administrator never appears, and neither does one the
 * stock projection says is gone. A shop that is merely closed right now still appears — it is a
 * real shop the customer can order from later — but its card does not promise today.
 */
@Service
public class GiftBundleService {

    private static final Logger log = LoggerFactory.getLogger(GiftBundleService.class);

    /**
     * The most bundles the hub asks for. A shop window rather than a catalogue — the design draws
     * three — and a bound, so the one open read of this list cannot page the featured set.
     */
    static final int MAX_BUNDLES = 12;

    private final ProductRepository products;
    private final StoreRepository stores;

    public GiftBundleService(ProductRepository products, StoreRepository stores) {
        this.products = products;
        this.stores = stores;
    }

    /**
     * One featured product and the shop it comes from, as of the moment asked.
     *
     * @param availability       the shop's card state right now
     * @param sameDayDeliverable see {@link Store#deliversBeforeClosing}
     */
    public record GiftBundle(Product product, Store store, Store.Availability availability,
                             boolean sameDayDeliverable) {
    }

    /** The hub's bundles, newest pick first, as of {@code now}. */
    @Transactional(readOnly = true)
    public List<GiftBundle> featured(Instant now) {
        List<Product> picked = products.findFeaturedGifts(PageRequest.of(0, MAX_BUNDLES));
        if (picked.isEmpty()) {
            return List.of();
        }
        // One read for every shop on the list, not one per card.
        Map<UUID, Store> shops = stores.findAllById(
                        picked.stream().map(Product::getStoreId).distinct().toList())
                .stream()
                .collect(Collectors.toMap(Store::getId, Function.identity()));

        List<GiftBundle> bundles = new ArrayList<>();
        for (Product product : picked) {
            Store shop = shops.get(product.getStoreId());
            // Never a service shop's offer: services are not giftable (owner default 13) and the hub
            // is a goods window. setFeatured refuses to feature one; this half keeps the hub right
            // whatever the flag on the row says.
            if (shop == null || shop.getStatus() != Store.Status.ACTIVE || !product.isInStock()
                    || shop.getVertical() == Store.Vertical.SERVICES) {
                continue;
            }
            bundles.add(new GiftBundle(product, shop, shop.availabilityAt(now),
                    shop.deliversBeforeClosing(now)));
        }
        return bundles;
    }

    /**
     * Puts a product on the gift hub or takes it off. BACKOFFICE only — the controller says so.
     *
     * <p>Featuring is refused for a product that is not live (422): a draft or archived product on
     * the hub would be a card nobody can buy. A service shop's offer is refused too (422): services
     * are not giftable, so its card would lead to a checkout that has to say no. Taking one off
     * always works, whatever its state.
     *
     * @param actor the back-office user, recorded in the log so "who put this on the hub" has an
     *              answer beside the {@code gift_featured_at} the row keeps
     */
    @Transactional
    public Product setFeatured(UUID productId, boolean featured, String actor, Instant now) {
        Product product = products.findById(productId)
                .orElseThrow(() -> new ProductNotFoundException(productId));
        if (featured) {
            boolean serviceOffer = stores.findById(product.getStoreId())
                    .map(shop -> shop.getVertical() == Store.Vertical.SERVICES)
                    .orElse(false);
            if (serviceOffer) {
                throw new CatalogRuleViolationException(
                        "A service offer cannot be featured on the gift hub: services are not giftable.");
            }
            try {
                product.featureAsGift(now);
            } catch (IllegalStateException e) {
                throw new CatalogRuleViolationException(e.getMessage());
            }
        } else {
            product.unfeatureAsGift();
        }
        Product saved = products.save(product);
        log.info("Back office {} {} product {} on the gift hub", actor,
                featured ? "featured" : "unfeatured", productId);
        return saved;
    }
}
