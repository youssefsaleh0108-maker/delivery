package com.delivery.product.service;

import java.math.BigDecimal;
import java.time.Clock;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.regex.Pattern;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.product.domain.GeoPoint;
import com.delivery.product.domain.ItemSearchRepository;
import com.delivery.product.domain.ItemSearchRepository.Candidate;
import com.delivery.product.domain.Product;
import com.delivery.product.domain.ProductRepository;
import com.delivery.product.domain.Store;
import com.delivery.product.domain.StoreRepository;
import com.delivery.product.service.StoreService.StoreView;

/**
 * "Who near me sells Pepsi?": products across every live goods shop, grouped by the shop that sells them.
 *
 * <p>The work is split as "near me" splits it ({@code StoreRepository#findActiveIdsNear}). The database
 * matches the words, narrows by status, stock, vertical and distance, ranks, and caps
 * ({@link ItemSearchRepository#findCandidateRows}). This class then judges every candidate again on the
 * rows as read, and decides:
 * <ul>
 *   <li>the product is ACTIVE and in stock, and its shop is ACTIVE and not a service shop. The ids and
 *       the rows come from different queries, so a product paused or a shop suspended between them is
 *       judged on what it is now. A draft or suspended shop, or a services offer, never reaches a
 *       customer from here;
 *   <li>with a point, the shop is pinned, within the search radius on the sphere
 *       ({@link GeoPoint#distanceMetresTo}, the distance the card shows), and, when it drew a delivery
 *       circle, the point is inside it;
 *   <li>the shop is not CLOSED now ({@link StoreService#viewAt}). Order Manager refuses a closed shop's
 *       order, so its items would be ones nobody can buy. BUSY and CLOSING_SOON stay: both still take
 *       orders.
 * </ul>
 *
 * <p>What is left is grouped by shop, because the customer chooses a shop to order from, not a product
 * in the abstract. A shop's items are its best matches first; the shops are ordered by their best match
 * (tier, then score), then by distance, or by rating when there is no point, then by id so the order is
 * the same on every refresh. Each group keeps its top {@value #ITEMS_PER_SHOP} items and says how many
 * matched in all, and the groups are paged here, in memory: there are at most
 * {@code max-candidates} of them.
 *
 * <p>The radius is the server's ({@code delivery.catalog.item-search.radius-metres}), never the
 * request's, like the Services tab's popular row: a client that could widen it could page every shop on
 * the platform by distance from any point. Without a point every live goods shop is searched, with no
 * distance, and the answer says {@code nearby: false}.
 */
@Service
public class ItemSearchService {

    /** The shortest term worth a query: one letter matches most of the catalogue. */
    static final int MIN_TERM_LENGTH = 2;

    /** Longer than any product name a customer would type. */
    static final int MAX_TERM_LENGTH = 100;

    /** The query's term slots. Text search uses one; a photo's name, Arabic name and brand use three. */
    static final int MAX_TERMS = 3;

    /** The largest page of shops one request may ask for. */
    static final int MAX_PAGE_SIZE = 20;

    /** How many of a shop's matches travel with it. The rest are counted in {@code matchedInStore}. */
    static final int ITEMS_PER_SHOP = 3;

    /** The bounds "near me" holds a radius to, applied to the setting. */
    static final int MIN_RADIUS_METRES = 50;
    static final int MAX_RADIUS_METRES = 50_000;

    /** The most candidates the setting may ask one search to read. */
    static final int MAX_CANDIDATE_CEILING = 1_000;

    /** EAN-8, UPC-A, EAN-13 and GTIN-14 all fit, and so does anything a merchant keyed in between. */
    private static final Pattern BARCODE = Pattern.compile("[0-9]{8,14}");

    /** A term or the whole query is shorter than {@value #MIN_TERM_LENGTH} characters, or empty. */
    public static final String SEARCH_TOO_SHORT = "SEARCH_TOO_SHORT";

    /** A term is longer than {@value #MAX_TERM_LENGTH} characters. */
    public static final String SEARCH_TOO_LONG = "SEARCH_TOO_LONG";

    /** More than {@value #MAX_TERMS} terms, counting {@code q}. */
    public static final String SEARCH_TOO_MANY_TERMS = "SEARCH_TOO_MANY_TERMS";

    /** A barcode that is not 8 to 14 digits. */
    public static final String SEARCH_BAD_BARCODE = "SEARCH_BAD_BARCODE";

    private final ItemSearchRepository search;
    private final ProductRepository products;
    private final StoreRepository stores;
    private final StoreService storeService;
    private final Clock clock;
    private final int radiusMetres;
    private final int maxCandidates;

    public ItemSearchService(ItemSearchRepository search, ProductRepository products,
                             StoreRepository stores, StoreService storeService, Clock clock,
                             @Value("${delivery.catalog.item-search.radius-metres:5000}")
                             int radiusMetres,
                             @Value("${delivery.catalog.item-search.max-candidates:300}")
                             int maxCandidates) {
        this.search = search;
        this.products = products;
        this.stores = stores;
        this.storeService = storeService;
        this.clock = clock;
        // Clamped rather than trusted, so a configuration mistake can neither empty the search for
        // ever nor make "near you" nationwide, nor pull the whole catalogue into memory.
        this.radiusMetres = Math.min(Math.max(radiusMetres, MIN_RADIUS_METRES), MAX_RADIUS_METRES);
        this.maxCandidates = Math.min(Math.max(maxCandidates, 1), MAX_CANDIDATE_CEILING);
    }

    // ---------------------------------------------------------------- the question

    /**
     * What to look for: up to {@value #MAX_TERMS} terms, a barcode, or both. Built only by {@link #of},
     * which refuses what cannot be searched, so a query that exists is one the database may be asked.
     *
     * @param terms   the terms, trimmed; {@code q} first when there is one
     * @param barcode the barcode's digits, or null
     */
    public record ItemQuery(List<String> terms, String barcode) {

        public ItemQuery {
            terms = List.copyOf(terms);
        }

        /**
         * The query a request asks for, or a {@link SearchRefusedException} naming why not.
         *
         * <p>{@code q} is what a customer typed; {@code terms} is how a caller that already knows its
         * words (a photo's name, Arabic name and brand) asks. Both fill the same slots, {@code q}
         * first. A blank {@code q} or barcode counts as absent, but a term that was sent must be a
         * term: an empty one is a client mistake, and searching for it would match everything.
         */
        public static ItemQuery of(String q, List<String> terms, String barcode) {
            List<String> slots = new ArrayList<>();
            if (q != null && !q.isBlank()) {
                slots.add(checkedTerm(q));
            }
            if (terms != null) {
                for (String term : terms) {
                    slots.add(checkedTerm(term));
                }
            }
            if (slots.size() > MAX_TERMS) {
                throw new SearchRefusedException(SEARCH_TOO_MANY_TERMS,
                        "A search can have at most " + MAX_TERMS + " terms.");
            }
            String digits = barcode == null || barcode.isBlank() ? null : barcode.trim();
            if (digits != null && !BARCODE.matcher(digits).matches()) {
                throw new SearchRefusedException(SEARCH_BAD_BARCODE, "A barcode is 8 to 14 digits.");
            }
            if (slots.isEmpty() && digits == null) {
                throw new SearchRefusedException(SEARCH_TOO_SHORT,
                        "Type at least " + MIN_TERM_LENGTH + " letters or digits to search.");
            }
            return new ItemQuery(slots, digits);
        }

        private static String checkedTerm(String term) {
            String trimmed = term == null ? "" : term.trim();
            // Characters as a reader counts them, so an emoji is one, not two UTF-16 units.
            int length = trimmed.codePointCount(0, trimmed.length());
            if (length < MIN_TERM_LENGTH) {
                throw new SearchRefusedException(SEARCH_TOO_SHORT,
                        "Type at least " + MIN_TERM_LENGTH + " letters or digits to search.");
            }
            if (length > MAX_TERM_LENGTH) {
                throw new SearchRefusedException(SEARCH_TOO_LONG,
                        "A search can be at most " + MAX_TERM_LENGTH + " characters.");
            }
            return trimmed;
        }

        /** The slot the query binds: the term, or {@code ''} when unused. Never null; see the query. */
        String slot(int index) {
            return index < terms.size() ? terms.get(index) : "";
        }
    }

    /** A search that cannot be run, with the code a client branches on. Mapped to 400. */
    public static class SearchRefusedException extends RuntimeException {

        private final String code;

        public SearchRefusedException(String code, String message) {
            super(message);
            this.code = code;
        }

        public String getCode() {
            return code;
        }
    }

    // ---------------------------------------------------------------- the answer

    /**
     * One shop and what it sells that matched.
     *
     * @param distanceMetres straight-line metres from the point on the sphere, or null without a point
     * @param items          its best {@value #ITEMS_PER_SHOP} matches, best first
     * @param matchedInStore how many of its products matched in all, counting those in {@code items}
     */
    public record ShopMatch(StoreView store, Double distanceMetres, List<Product> items,
                            int matchedInStore) {
    }

    /**
     * A page of shops, and what the page can honestly claim.
     *
     * @param truncated      true when more products matched than one search reads. The page then covers
     *                       the best {@code candidateLimit} matches only, so "no shop sells it" over a
     *                       truncated answer means "none among those".
     * @param candidateLimit how many matching products one search reads
     * @param nearby         whether the search was around a point. Without one no distance is known.
     */
    public record ItemSearchResult(Page<ShopMatch> page, boolean truncated, int candidateLimit,
                                   boolean nearby) {
    }

    /**
     * The shops that sell what {@code query} names, as a page.
     *
     * @param centre where the customer is, or null to search every live goods shop
     * @param page   zero-based; a negative page is the first
     * @param size   clamped to between one and {@value #MAX_PAGE_SIZE}
     */
    @Transactional(readOnly = true)
    public ItemSearchResult search(ItemQuery query, GeoPoint centre, int page, int size) {
        PageRequest pageable = PageRequest.of(Math.max(page, 0),
                Math.min(Math.max(size, 1), MAX_PAGE_SIZE));
        Instant now = clock.instant();
        boolean near = centre != null;

        List<Candidate> found = search.findCandidates(
                query.slot(0), query.slot(1), query.slot(2),
                query.barcode() == null ? "" : query.barcode(),
                near,
                near ? centre.latitude().doubleValue() : 0d,
                near ? centre.longitude().doubleValue() : 0d,
                radiusMetres * StoreService.RADIUS_SLACK,
                StoreService.RADIUS_SLACK,
                maxCandidates + 1);
        // One row more than the ceiling was asked for, so reaching it is seen rather than guessed at:
        // exactly maxCandidates rows could be every match there was. Best first, so the row left over
        // is the weakest match.
        boolean truncated = found.size() > maxCandidates;
        List<Candidate> candidates = truncated ? found.subList(0, maxCandidates) : found;
        if (candidates.isEmpty()) {
            return new ItemSearchResult(pageOf(List.of(), pageable), false, maxCandidates, near);
        }

        Map<UUID, Product> productsById = new HashMap<>();
        products.findAllById(candidates.stream().map(Candidate::productId).toList())
                .forEach(p -> productsById.put(p.getId(), p));
        Map<UUID, Store> storesById = new HashMap<>();
        stores.findAllById(new LinkedHashSet<>(candidates.stream().map(Candidate::storeId).toList()))
                .forEach(s -> storesById.put(s.getId(), s));

        // Each shop is judged once, however many of its products matched.
        Map<UUID, Optional<Shop>> shops = new LinkedHashMap<>();
        for (Candidate candidate : candidates) {
            Product product = productsById.get(candidate.productId());
            if (product == null
                    || product.getStatus() != Product.Status.ACTIVE
                    || !product.isInStock()) {
                continue;
            }
            // The row as read decides whose product this is, not the candidate's copy of it.
            UUID storeId = product.getStoreId();
            Optional<Shop> shop = shops.computeIfAbsent(storeId,
                    id -> judge(storesById.get(id), centre, now));
            shop.ifPresent(s -> s.hits.add(new Hit(candidate, product)));
        }

        List<Shop> listed = new ArrayList<>();
        for (Optional<Shop> shop : shops.values()) {
            shop.filter(s -> !s.hits.isEmpty()).ifPresent(listed::add);
        }
        listed.forEach(s -> s.hits.sort(BEST_HIT_FIRST));
        listed.sort(near ? BEST_SHOP_FIRST_BY_DISTANCE : BEST_SHOP_FIRST_BY_RATING);

        List<ShopMatch> matches = listed.stream()
                .map(s -> new ShopMatch(s.view, s.distanceMetres,
                        s.hits.stream().limit(ITEMS_PER_SHOP).map(Hit::product).toList(),
                        s.hits.size()))
                .toList();
        return new ItemSearchResult(pageOf(matches, pageable), truncated, maxCandidates, near);
    }

    /**
     * Whether a shop may be listed, judged on the row as read; empty when not.
     *
     * <p>Every rule the candidate query applies is applied again here, and this is what decides: the
     * query's circle carries slack, and a shop can change between the query and the read.
     */
    private Optional<Shop> judge(Store store, GeoPoint centre, Instant now) {
        if (store == null || store.getStatus() != Store.Status.ACTIVE || store.isServices()) {
            return Optional.empty();
        }
        Double metres = null;
        if (centre != null) {
            GeoPoint location = store.location();
            if (location == null) {
                // A shop with no pin has no distance, and inventing one would place it on the
                // strength of a made-up number. It is found by a search without a point.
                return Optional.empty();
            }
            metres = centre.distanceMetresTo(location);
            if (metres > radiusMetres) {
                return Optional.empty();
            }
            Integer circle = store.getDeliveryRadiusMetres();
            if (circle != null && metres > circle) {
                // The shop said how far it carries, and the customer is further than that.
                return Optional.empty();
            }
        }
        StoreView view = storeService.viewAt(store, now);
        if (view.availability() == Store.Availability.CLOSED) {
            return Optional.empty();
        }
        return Optional.of(new Shop(view, metres));
    }

    /** A shop being listed: its view, its distance when there is a point, and its matches. */
    private static final class Shop {
        private final StoreView view;
        private final Double distanceMetres;
        private final List<Hit> hits = new ArrayList<>();

        private Shop(StoreView view, Double distanceMetres) {
            this.view = view;
            this.distanceMetres = distanceMetres;
        }

        private Hit best() {
            return hits.get(0);
        }
    }

    private record Hit(Candidate candidate, Product product) {
    }

    /** Within a shop: the better tier, then the better score, then the product id. */
    private static final Comparator<Hit> BEST_HIT_FIRST = Comparator
            .comparingInt((Hit h) -> h.candidate().tier())
            .thenComparing(h -> h.candidate().score(), Comparator.reverseOrder())
            .thenComparing(h -> h.product().getId());

    /** Between shops: the better best match, the same way, before anything about the shop. */
    private static final Comparator<Shop> BEST_MATCH_FIRST = Comparator
            .comparingInt((Shop s) -> s.best().candidate().tier())
            .thenComparing(s -> s.best().candidate().score(), Comparator.reverseOrder());

    /** Around a point: then the nearer shop, then the shop id. */
    private static final Comparator<Shop> BEST_SHOP_FIRST_BY_DISTANCE = BEST_MATCH_FIRST
            .thenComparing(s -> s.distanceMetres)
            .thenComparing(s -> s.view.store().getId());

    /**
     * Without a point: then the better rated shop, a shop nobody has rated last (no rating is not a
     * good one), then the shop id.
     */
    private static final Comparator<Shop> BEST_SHOP_FIRST_BY_RATING = BEST_MATCH_FIRST
            .thenComparing(s -> s.view.store().getRating(),
                    Comparator.nullsLast(Comparator.<BigDecimal>reverseOrder()))
            .thenComparing(s -> s.view.store().getId());

    private static <T> Page<T> pageOf(List<T> all, PageRequest pageable) {
        int from = (int) Math.min(pageable.getOffset(), all.size());
        int to = Math.min(from + pageable.getPageSize(), all.size());
        return new PageImpl<>(all.subList(from, to), pageable, all.size());
    }
}
