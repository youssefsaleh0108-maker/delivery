package com.delivery.product.service;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.springframework.stereotype.Service;

import com.delivery.product.domain.CategoryRepository;
import com.delivery.product.domain.PhotoSearchUse.Kind;
import com.delivery.product.domain.Product;
import com.delivery.product.domain.ProductFindRepository;
import com.delivery.product.domain.ProductFindRepository.Found;
import com.delivery.product.domain.ProductRepository;
import com.delivery.product.domain.Store;
import com.delivery.product.service.CatalogService.CatalogRuleViolationException;
import com.delivery.product.vision.Descriptions;
import com.delivery.product.vision.FakeVisionProvider;
import com.delivery.product.vision.VisionProvider;
import com.delivery.product.vision.VisionProviders;

/**
 * A merchant photographs a pack and is told whether it is already in their own catalogue.
 *
 * <p>The other half of Merchant Blitz: the scan builds a catalogue from shelves, and this answers the
 * question a shopkeeper asks about one thing in their hand — "do I already have this, and where?" It
 * reads the photo with the same provider Blitz uses ({@link VisionProviders#active}), so it answers
 * with <strong>labelled samples</strong> until real recognition is on, exactly as Blitz does. A
 * customer's photo search never does that ({@link PhotoSearchService}): a merchant is told the lines
 * are examples and can see their own shelf beside them, while a customer would simply be misled.
 *
 * <p><strong>Scoped to the caller's own shops</strong>, and to every status in them: a paused or
 * archived product is exactly what the merchant needs to be told about, rather than being offered to
 * add a second copy of it ({@link ProductFindRepository#findInStoresRows}). A shop id that is not
 * theirs is a 404, as everywhere else; a service shop is refused as Blitz refuses it, since a photo
 * of a pack says nothing about the terms a service offer needs.
 *
 * <p>The quota is the merchant's own ({@code MERCHANT_FIND}: {@code merchant-per-day},
 * {@code per-account-per-minute}), counted just before the paid call, and the photo is dropped as soon
 * as the answer comes back ({@link PhotoReader}).
 */
@Service
public class PhotoFindService {

    /** The most matches offered. More than a handful is a list to scroll, not an answer. */
    static final int MAX_MATCHES = 5;

    /** How a match was found, for the client to say so. */
    public static final String BY_BARCODE = "BARCODE";
    public static final String BY_NAME = "NAME";

    /**
     * One of the merchant's own products the photo matched.
     *
     * @param matchedBy {@link #BY_BARCODE} when the barcode was equal, {@link #BY_NAME} otherwise
     */
    public record Match(Product product, String matchedBy) {
    }

    /**
     * What to prefill a new product with, when the merchant does not have it yet.
     *
     * @param barcode only when no product in these shops already carries it: a code that is already
     *                somebody's here would make two products that scan the same at the till
     */
    public record Suggestion(String name, String barcode, UUID categoryId) {
    }

    /**
     * @param provider which provider answered, and {@code sample} when it was the fake
     * @param left     the merchant's finds left over the rolling day
     */
    public record FindResult(String provider, boolean sample, Descriptions.Clean understood,
                             List<Match> matches, Suggestion suggestion, int left) {
    }

    private final VisionProviders providers;
    private final PhotoReader reader;
    private final PhotoQuota quota;
    private final StoreService stores;
    private final ProductFindRepository finder;
    private final ProductRepository products;
    private final CategoryRepository categories;

    public PhotoFindService(VisionProviders providers, PhotoReader reader, PhotoQuota quota,
                            StoreService stores, ProductFindRepository finder,
                            ProductRepository products, CategoryRepository categories) {
        this.providers = providers;
        this.reader = reader;
        this.quota = quota;
        this.stores = stores;
        this.finder = finder;
        this.products = products;
        this.categories = categories;
    }

    /**
     * Reads {@code photo} and looks for it in the merchant's own catalogue.
     *
     * @param storeId one of the caller's shops, or null for every goods shop they own
     * @throws StoreService.StoreNotFoundException   for a shop that is not the caller's (404)
     * @throws CatalogRuleViolationException         for a service shop, or a merchant with no goods
     *                                               shop to search (422), before anything is read
     * @throws PhotoSearchException                  every photo refusal, as photo search's
     */
    public FindResult find(String merchantId, byte[] photo, UUID storeId) {
        List<Store> shops = goodsShopsOf(merchantId, storeId);
        VisionProvider provider = providers.active();

        PhotoReader.Reading reading = reader.read(photo, provider,
                () -> quota.take(merchantId, Kind.MERCHANT_FIND));
        Descriptions.Clean understood = reading.description();
        boolean sample = FakeVisionProvider.NAME.equals(provider.name());
        if (!understood.isProduct()) {
            return new FindResult(provider.name(), sample, understood, List.of(), null, reading.left());
        }

        List<UUID> shopIds = shops.stream().map(Store::getId).toList();
        List<Match> matches = matches(shopIds, understood);
        return new FindResult(provider.name(), sample, understood, matches,
                suggestion(shops, shopIds, understood), reading.left());
    }

    /** The caller's goods shops: the one they named, or all of them. */
    private List<Store> goodsShopsOf(String merchantId, UUID storeId) {
        List<Store> owned = stores.ownedBy(merchantId);
        if (storeId != null) {
            Store shop = owned.stream()
                    .filter(store -> store.getId().equals(storeId))
                    .findFirst()
                    // The same answer another merchant's shop id gets anywhere else: not found.
                    .orElseThrow(() -> new StoreService.StoreNotFoundException(storeId.toString()));
            if (shop.isServices()) {
                throw new CatalogRuleViolationException("Finding a product by photo reads a pack, and "
                        + "this is a service shop. Its offers carry terms no photo can show.");
            }
            return List.of(shop);
        }
        List<Store> goods = owned.stream().filter(store -> !store.isServices()).toList();
        if (goods.isEmpty()) {
            throw new CatalogRuleViolationException("Open your shop before finding products by photo.");
        }
        return goods;
    }

    /** The photo's words against the shops' own products: the barcode first, then the name. */
    List<Match> matches(List<UUID> shopIds, Descriptions.Clean understood) {
        List<String> terms = new ArrayList<>();
        for (String word : List.of(understood.name() == null ? "" : understood.name(),
                understood.nameAr() == null ? "" : understood.nameAr(),
                understood.brand() == null ? "" : understood.brand())) {
            terms.add(word);
        }
        List<String> folded = products.foldForSearch(terms.get(0), terms.get(1), terms.get(2));
        List<SearchWords> slots = new ArrayList<>();
        for (String term : folded) {
            String searchable = PhotoSearchService.searchable(term);
            slots.add(searchable == null ? SearchWords.NONE : SearchWords.of(searchable));
        }
        String barcode = understood.barcode() == null ? "" : understood.barcode();
        if (barcode.isEmpty() && slots.stream().allMatch(SearchWords::isEmpty)) {
            return List.of();
        }

        List<Found> found = finder.findInStores(shopIds,
                slots.get(0).phrase(), slots.get(0).wordsForQuery(),
                slots.get(1).phrase(), slots.get(1).wordsForQuery(),
                slots.get(2).phrase(), slots.get(2).wordsForQuery(),
                barcode, MAX_MATCHES);
        if (found.isEmpty()) {
            return List.of();
        }

        Map<UUID, Product> byId = new LinkedHashMap<>();
        products.findAllById(found.stream().map(Found::productId).toList())
                .forEach(product -> byId.put(product.getId(), product));

        List<Match> matches = new ArrayList<>();
        for (Found row : found) {
            Product product = byId.get(row.productId());
            // Judged again on the row as read: a product moved to another shop since the query is not
            // this merchant's match any more.
            if (product == null || !shopIds.contains(product.getStoreId())) {
                continue;
            }
            matches.add(new Match(product, row.tier() == 0 ? BY_BARCODE : BY_NAME));
        }
        return matches;
    }

    /**
     * What "Add as a new product" starts from: the name as the reader spelled it, the section when one
     * of the shop's own is named exactly, and the barcode only when it is nobody's here yet.
     */
    private Suggestion suggestion(List<Store> shops, List<UUID> shopIds, Descriptions.Clean understood) {
        String name = understood.name() != null ? understood.name() : understood.nameAr();
        String barcode = understood.barcode();
        if (barcode != null && finder.barcodeTaken(shopIds, barcode)) {
            barcode = null;
        }
        UUID categoryId = null;
        if (shops.size() == 1) {
            // One shop, so "which shelf" has an answer. Across several shops a section id would
            // belong to whichever of them the merchant then picked, which may not be this one.
            categoryId = CategoryChoices.resolveAny(understood.keywords(),
                    CategoryChoices.forStore(categories, shops.get(0).getId()));
        }
        return new Suggestion(name, barcode, categoryId);
    }
}
