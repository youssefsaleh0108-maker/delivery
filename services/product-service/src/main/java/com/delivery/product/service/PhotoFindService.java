package com.delivery.product.service;

import java.time.Duration;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

import com.delivery.product.domain.CategoryRepository;
import com.delivery.product.domain.PhotoSearchUse.Kind;
import com.delivery.product.domain.Product;
import com.delivery.product.domain.ProductFindRepository;
import com.delivery.product.domain.ProductFindRepository.Found;
import com.delivery.product.domain.ProductRepository;
import com.delivery.product.domain.Store;
import com.delivery.product.service.CatalogService.CatalogRuleViolationException;
import com.delivery.product.vision.Descriptions;
import com.delivery.product.vision.VisionException;
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
 *
 * <p><strong>The match is time-bounded</strong>, as the customer's search is
 * ({@link ItemSearchService#search}). It runs after the reader slot has been given back, so nothing
 * limits how many of these run at once but the request threads; and it reads every product of the
 * merchant's shops with no index to serve the words. A shop with tens of thousands of products would
 * hold one of the ten pooled connections for as long as that took, which is a storefront's connection
 * as much as it is this merchant's. So the read runs in a short read-only transaction of its own whose
 * statements are bounded by {@code photo-search.statement-timeout}, and a cancelled one is answered
 * 503 {@link ItemSearchService#SEARCH_TIMED_OUT} rather than waited out.
 */
@Service
public class PhotoFindService {

    /** The most matches offered. More than a handful is a list to scroll, not an answer. */
    static final int MAX_MATCHES = 5;

    /** The shortest and the longest the match may be given, whatever the configuration says. */
    static final Duration MIN_STATEMENT_TIMEOUT = Duration.ofMillis(250);
    static final Duration MAX_STATEMENT_TIMEOUT = Duration.ofSeconds(10);

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
    private final TransactionTemplate matching;
    private final Duration statementTimeout;

    public PhotoFindService(VisionProviders providers, PhotoReader reader, PhotoQuota quota,
                            StoreService stores, ProductFindRepository finder,
                            ProductRepository products, CategoryRepository categories,
                            PlatformTransactionManager transactionManager,
                            @Value("${delivery.catalog.photo-search.statement-timeout:2s}")
                            Duration statementTimeout) {
        this.providers = providers;
        this.reader = reader;
        this.quota = quota;
        this.stores = stores;
        this.finder = finder;
        this.products = products;
        this.categories = categories;
        // A transaction of its own rather than an annotation, because find() must NOT be in one: it
        // makes a call to the provider that can take 25 seconds, and a pooled connection held across
        // that is one taken from every storefront.
        this.matching = new TransactionTemplate(transactionManager);
        this.matching.setReadOnly(true);
        // Clamped rather than trusted, so a configuration mistake can neither cancel every match nor
        // let one hold a connection for minutes.
        Duration timeout = statementTimeout == null ? MAX_STATEMENT_TIMEOUT : statementTimeout;
        this.statementTimeout = timeout.compareTo(MIN_STATEMENT_TIMEOUT) < 0 ? MIN_STATEMENT_TIMEOUT
                : timeout.compareTo(MAX_STATEMENT_TIMEOUT) > 0 ? MAX_STATEMENT_TIMEOUT : timeout;
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
        VisionProvider provider;
        try {
            provider = providers.active();
        } catch (VisionException e) {
            // A provider name that matches nothing: an operator's mistake, not this merchant's, and
            // an answer they can act on ("not available right now") rather than a 500.
            throw PhotoSearchException.unavailable();
        }

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

        List<Found> found = withinTimeout(() -> finder.findInStores(shopIds,
                slots.get(0).phrase(), slots.get(0).wordsForQuery(),
                slots.get(1).phrase(), slots.get(1).wordsForQuery(),
                slots.get(2).phrase(), slots.get(2).wordsForQuery(),
                barcode, MAX_MATCHES));
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
     * Runs {@code read} in a short read-only transaction whose statements the database itself cuts off
     * at {@code statementTimeout}.
     *
     * @throws ItemSearchService.SearchTimedOutException when it did cut one off: a 503 with
     *                                                   {@link ItemSearchService#SEARCH_TIMED_OUT} and
     *                                                   a Retry-After, since a cancelled statement
     *                                                   returns no rows at all and a partial answer
     *                                                   would read as "you do not have this yet"
     */
    private <T> T withinTimeout(java.util.function.Supplier<T> read) {
        try {
            return matching.execute(status -> {
                // Before the read, inside the same transaction, so SET LOCAL applies to it and is
                // undone on the way back to the pool.
                finder.limitStatementTime(Long.toString(statementTimeout.toMillis()));
                return read.get();
            });
        } catch (RuntimeException e) {
            if (ItemSearchService.cancelledByTheDatabase(e)) {
                throw new ItemSearchService.SearchTimedOutException(e);
            }
            throw e;
        }
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
