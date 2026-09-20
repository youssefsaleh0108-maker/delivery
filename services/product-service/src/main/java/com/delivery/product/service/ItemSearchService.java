package com.delivery.product.service;

import java.math.BigDecimal;
import java.sql.SQLException;
import java.time.Clock;
import java.time.Duration;
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
 * matches the words, narrows by status, stock, vertical, distance and opening hours, ranks, keeps each
 * shop's best {@value #ITEMS_PER_SHOP} matches and counts the rest, and caps
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
 * the same on every refresh: the order the query kept its rows in, so what a cut leaves out is what
 * this would have listed last. Each group keeps its top {@value #ITEMS_PER_SHOP} items and says how
 * many matched in all, and the groups are paged here, in memory: there are at most
 * {@code max-candidates} of them.
 *
 * <p>The radius is the server's ({@code delivery.catalog.item-search.radius-metres}), never the
 * request's, like the Services tab's popular row: a client that could widen it could page every shop on
 * the platform by distance from any point. Without a point every live goods shop is searched, with no
 * distance, and the answer says {@code nearby: false}.
 *
 * <p><strong>What one search may cost.</strong> The query reads what the words select through the
 * trigram index, so the words are held to what the index can narrow by: a term folds to at most
 * {@value #MAX_WORDS} words of two characters or more, and has at least one ({@link SearchWords}; a
 * one-character word is matched only inside the phrase). The words are counted as the database folds
 * them, after one round trip that reads no table. Every statement runs under
 * {@code delivery.catalog.item-search.statement-timeout}; one that runs past it is cancelled by the
 * database and the search answers 503 {@code SEARCH_TIMED_OUT}. The controller limits how often one
 * account searches ({@link ItemSearchThrottle}).
 */
@Service
public class ItemSearchService {

    /** The shortest term worth a query: one letter matches most of the catalogue. */
    static final int MIN_TERM_LENGTH = 2;

    /** Longer than any product name a customer would type. */
    static final int MAX_TERM_LENGTH = 100;

    /** The query's term slots. Text search uses one; a photo's name, Arabic name and brand use three. */
    static final int MAX_TERMS = 3;

    /**
     * The most words a term may fold to, counting those of two characters or more. Five covers a
     * product as people name it ("nido full cream milk 2kg"), and each word is a check on every row the
     * index lets through.
     */
    static final int MAX_WORDS = 5;

    /** The largest page of shops one request may ask for. */
    static final int MAX_PAGE_SIZE = 20;

    /** How many of a shop's matches travel with it. The rest are counted in {@code matchedInStore}. */
    static final int ITEMS_PER_SHOP = 3;

    /** The bounds "near me" holds a radius to, applied to the setting. */
    static final int MIN_RADIUS_METRES = 50;
    static final int MAX_RADIUS_METRES = 50_000;

    /** The most candidates the setting may ask one search to read. */
    static final int MAX_CANDIDATE_CEILING = 1_000;

    /** The bounds a statement timeout is held to, applied to the setting. */
    static final Duration MIN_STATEMENT_TIMEOUT = Duration.ofMillis(100);
    static final Duration MAX_STATEMENT_TIMEOUT = Duration.ofSeconds(15);

    /** How long a client is told to wait after a search the database gave up on. */
    static final long TIMED_OUT_RETRY_AFTER_SECONDS = 5;

    /** EAN-8, UPC-A, EAN-13 and GTIN-14 all fit, and so does anything a merchant keyed in between. */
    private static final Pattern BARCODE = Pattern.compile("[0-9]{8,14}");

    /** PostgreSQL's query_canceled: a statement timeout, or a cancel. */
    private static final String QUERY_CANCELED = "57014";

    /**
     * A term or the whole query is shorter than {@value #MIN_TERM_LENGTH} characters, or empty, or folds
     * to no word of two characters or more ("a.").
     */
    public static final String SEARCH_TOO_SHORT = "SEARCH_TOO_SHORT";

    /** A term is longer than {@value #MAX_TERM_LENGTH} characters. */
    public static final String SEARCH_TOO_LONG = "SEARCH_TOO_LONG";

    /** More than {@value #MAX_TERMS} terms, counting {@code q}. */
    public static final String SEARCH_TOO_MANY_TERMS = "SEARCH_TOO_MANY_TERMS";

    /** A term folds to more than {@value #MAX_WORDS} words of two characters or more. */
    public static final String SEARCH_TOO_MANY_WORDS = "SEARCH_TOO_MANY_WORDS";

    /** A barcode that is not 8 to 14 digits. */
    public static final String SEARCH_BAD_BARCODE = "SEARCH_BAD_BARCODE";

    /** The database gave up on the search at the statement timeout; 503. */
    public static final String SEARCH_TIMED_OUT = "SEARCH_TIMED_OUT";

    private final ItemSearchRepository search;
    private final ProductRepository products;
    private final StoreRepository stores;
    private final StoreService storeService;
    private final Clock clock;
    private final int radiusMetres;
    private final int maxCandidates;
    private final Duration statementTimeout;

    public ItemSearchService(ItemSearchRepository search, ProductRepository products,
                             StoreRepository stores, StoreService storeService, Clock clock,
                             @Value("${delivery.catalog.item-search.radius-metres:5000}")
                             int radiusMetres,
                             @Value("${delivery.catalog.item-search.max-candidates:300}")
                             int maxCandidates,
                             @Value("${delivery.catalog.item-search.statement-timeout:2s}")
                             Duration statementTimeout) {
        this.search = search;
        this.products = products;
        this.stores = stores;
        this.storeService = storeService;
        this.clock = clock;
        // Clamped rather than trusted, so a configuration mistake can neither empty the search for
        // ever nor make "near you" nationwide, nor pull the whole catalogue into memory, nor let one
        // search hold a connection for minutes.
        this.radiusMetres = Math.min(Math.max(radiusMetres, MIN_RADIUS_METRES), MAX_RADIUS_METRES);
        this.maxCandidates = Math.min(Math.max(maxCandidates, 1), MAX_CANDIDATE_CEILING);
        Duration timeout = statementTimeout == null ? MAX_STATEMENT_TIMEOUT : statementTimeout;
        this.statementTimeout = timeout.compareTo(MIN_STATEMENT_TIMEOUT) < 0 ? MIN_STATEMENT_TIMEOUT
                : timeout.compareTo(MAX_STATEMENT_TIMEOUT) > 0 ? MAX_STATEMENT_TIMEOUT : timeout;
    }

    // ---------------------------------------------------------------- the question

    /**
     * What to look for: up to {@value #MAX_TERMS} terms, a barcode, or both. Built only by {@link #of},
     * which refuses what cannot be searched as typed; the words are checked again once folded, by
     * {@link ItemSearchService#search}.
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

        /** The slot the fold is asked for: the term, or {@code ''} when unused. Never null. */
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

    /**
     * The database cancelled the search at the statement timeout. Mapped to 503 with
     * {@link #SEARCH_TIMED_OUT} and a Retry-After, rather than a partial answer: a cancelled statement
     * returns no rows at all, and running a narrower one in its place would spend more of the time
     * just found to be short.
     */
    public static class SearchTimedOutException extends RuntimeException {

        public SearchTimedOutException(Throwable cause) {
            super("The search took too long. Try again in a moment.", cause);
        }

        public String getCode() {
            return SEARCH_TIMED_OUT;
        }

        public long getRetryAfterSeconds() {
            return TIMED_OUT_RETRY_AFTER_SECONDS;
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
     * @param truncated      true when more matched than one search reads. The page then covers the
     *                       best {@code candidateLimit} matches only (at most {@value #ITEMS_PER_SHOP} of
     *                       each shop, the nearest shops first), so "no shop sells it" over a truncated
     *                       answer means "none among those".
     * @param candidateLimit how many matching products one search reads
     * @param nearby         whether the search was around a point. Without one no distance is known.
     * @param searched       what the search ran on and what the whole answer reached, not just this page
     */
    public record ItemSearchResult(Page<ShopMatch> page, boolean truncated, int candidateLimit,
                                   boolean nearby, Searched searched) {

        /** An answer nobody asked the second question of. For tests and callers that do not need it. */
        public ItemSearchResult(Page<ShopMatch> page, boolean truncated, int candidateLimit,
                                boolean nearby) {
            this(page, truncated, candidateLimit, nearby, Searched.NOTHING);
        }
    }

    /**
     * What the search actually ran on, and how far it had to go — the demand log's whole view of a
     * search, and the only thing it is ever given.
     *
     * <p>Over every shop that matched rather than the page asked for. A page is what the customer is
     * shown; this is what the answer was, and "nobody within two kilometres sells this" is a claim
     * about every match — the nearest shop easily sits on page two when a further shop matched a word
     * better.
     *
     * @param term    the terms as the database folded them, joined by a space in slot order; empty
     *                when the search had no words (a barcode on its own)
     * @param shops   how many shops matched in all
     * @param nearest metres to the nearest of them; null without a point, or with no match
     * @param pins    where they are. Public information about shops, held only long enough for the
     *                recorder to ask which neighbourhood each is in — and gathered only on the first
     *                page, which is the only page that is recorded
     */
    public record Searched(String term, int shops, Double nearest, List<GeoPoint> pins) {

        /** No words, no shops: what a search that read nothing reached. */
        public static final Searched NOTHING = new Searched("", 0, null, List.of());

        public Searched {
            term = term == null ? "" : term;
            pins = pins == null ? List.of() : List.copyOf(pins);
        }
    }

    /**
     * The shops that sell what {@code query} names, as a page.
     *
     * @param centre where the customer is, or null to search every live goods shop
     * @param page   zero-based; a negative page is the first
     * @param size   clamped to between one and {@value #MAX_PAGE_SIZE}
     * @throws SearchRefusedException  when a term folds to no word to match, or to too many
     * @throws SearchTimedOutException when the database gave up at the statement timeout
     */
    @Transactional(readOnly = true)
    public ItemSearchResult search(ItemQuery query, GeoPoint centre, int page, int size) {
        try {
            // Before anything else in the transaction, so every statement of it is bounded.
            search.limitStatementTime(Long.toString(statementTimeout.toMillis()));
            return searchWithinTimeout(query, centre, page, size);
        } catch (RuntimeException e) {
            if (cancelledByTheDatabase(e)) {
                throw new SearchTimedOutException(e);
            }
            throw e;
        }
    }

    /**
     * An answer with no shops, in the shape {@link #search} gives it: for a caller with nothing it can
     * search for, such as a photo of something that is not a product. Reads nothing.
     */
    public ItemSearchResult nothing(GeoPoint centre, int size) {
        PageRequest pageable = PageRequest.of(0, Math.min(Math.max(size, 1), MAX_PAGE_SIZE));
        return new ItemSearchResult(pageOf(List.of(), pageable), false, maxCandidates, centre != null);
    }

    private ItemSearchResult searchWithinTimeout(ItemQuery query, GeoPoint centre, int page, int size) {
        PageRequest pageable = PageRequest.of(Math.max(page, 0),
                Math.min(Math.max(size, 1), MAX_PAGE_SIZE));
        Instant now = clock.instant();
        boolean near = centre != null;
        List<SearchWords> slots = wordsOf(query);

        List<Candidate> found = search.findCandidates(
                slots.get(0).phrase(), slots.get(0).wordsForQuery(),
                slots.get(1).phrase(), slots.get(1).wordsForQuery(),
                slots.get(2).phrase(), slots.get(2).wordsForQuery(),
                query.barcode() == null ? "" : query.barcode(),
                near,
                near ? centre.latitude().doubleValue() : 0d,
                near ? centre.longitude().doubleValue() : 0d,
                radiusMetres * StoreService.RADIUS_SLACK,
                StoreService.RADIUS_SLACK,
                now,
                ITEMS_PER_SHOP,
                maxCandidates + 1);
        // One row more than the ceiling was asked for, so reaching it is seen rather than guessed at:
        // exactly maxCandidates rows could be every match there was. Best first, so the row left over
        // is the weakest match of the farthest shop.
        boolean truncated = found.size() > maxCandidates;
        List<Candidate> candidates = truncated ? found.subList(0, maxCandidates) : found;
        // The folded words, kept for the demand log: an answer with no shops in it is the row that
        // matters most, so the term travels on the empty answer as much as on a full one.
        String term = foldedTerm(slots);
        if (candidates.isEmpty()) {
            return new ItemSearchResult(pageOf(List.of(), pageable), false, maxCandidates, near,
                    new Searched(term, 0, null, List.of()));
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
            Optional<Shop> judged = shops.computeIfAbsent(candidate.storeId(),
                    id -> judge(storesById.get(id), centre, now));
            if (judged.isEmpty()) {
                continue;
            }
            Shop shop = judged.get();
            // The database's count, the same on every row of the shop.
            shop.matched = Math.max(shop.matched, candidate.matchedInStore());
            Product product = productsById.get(candidate.productId());
            // The row as read decides, not the candidate's copy of it: a product paused, sold out or
            // moved since the query is not this shop's match, and is not counted either.
            if (product == null
                    || product.getStatus() != Product.Status.ACTIVE
                    || !product.isInStock()
                    || !candidate.storeId().equals(product.getStoreId())) {
                shop.dropped++;
                continue;
            }
            shop.hits.add(new Hit(candidate, product));
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
                        Math.max(s.matched - s.dropped, s.hits.size())))
                .toList();
        return new ItemSearchResult(pageOf(matches, pageable), truncated, maxCandidates, near,
                searchedOf(term, listed, pageable.getPageNumber() == 0));
    }

    /**
     * What the whole answer reached, read off the shops that survived judging rather than the page.
     *
     * <p>Costs a pass over at most {@code max-candidates} shops already in memory and no query at
     * all, which is why the search is allowed to work it out: anything that needed a read would be
     * the demand log slowing a search, and the demand log is not allowed to do that.
     *
     * <p>The pins are built only for the first page, because only the first page is recorded —
     * scrolling is the same search, so {@code ItemSearchController} discards everything this returns
     * for a later page. Gathering a list of up to {@code max-candidates} coordinates to throw away
     * is small, but it is work done on a request thread for a feature that has promised not to cost
     * a search anything.
     */
    private static Searched searchedOf(String term, List<Shop> listed, boolean firstPage) {
        Double nearest = null;
        List<GeoPoint> pins = firstPage ? new ArrayList<>(listed.size()) : List.of();
        for (Shop shop : listed) {
            GeoPoint pin = shop.view.store().location();
            if (firstPage && pin != null) {
                pins.add(pin);
            }
            if (shop.distanceMetres != null && (nearest == null || shop.distanceMetres < nearest)) {
                nearest = shop.distanceMetres;
            }
        }
        return new Searched(term, listed.size(), nearest, pins);
    }

    /**
     * The query's words as the database folded them, joined by a space in slot order.
     *
     * <p>One string for one search, because a search is one signal: a photo read as "pampers",
     * "حفاضات" and "size 4" is one person looking for nappies, not three. Empty for a search of no
     * words at all — a barcode on its own — which the demand log has nothing to say about.
     */
    private static String foldedTerm(List<SearchWords> slots) {
        StringBuilder term = new StringBuilder();
        for (SearchWords slot : slots) {
            if (slot.isEmpty()) {
                continue;
            }
            if (term.length() > 0) {
                term.append(' ');
            }
            term.append(slot.phrase());
        }
        return term.toString();
    }

    /**
     * The query's three slots, each folded by the database and checked: a term with no word of two
     * characters or more cannot be searched, nor one with more than {@value #MAX_WORDS}. An unused slot
     * is {@link SearchWords#NONE}; a barcode alone asks the database nothing here.
     */
    private List<SearchWords> wordsOf(ItemQuery query) {
        if (query.terms().isEmpty()) {
            return List.of(SearchWords.NONE, SearchWords.NONE, SearchWords.NONE);
        }
        List<String> folded = products.foldForSearch(query.slot(0), query.slot(1), query.slot(2));
        List<SearchWords> slots = new ArrayList<>();
        for (int i = 0; i < MAX_TERMS; i++) {
            if (i >= query.terms().size()) {
                slots.add(SearchWords.NONE);
                continue;
            }
            SearchWords words = SearchWords.of(folded.get(i));
            if (words.isEmpty()) {
                throw new SearchRefusedException(SEARCH_TOO_SHORT, "Type at least one word of "
                        + SearchWords.MIN_WORD_LENGTH + " letters or digits to search.");
            }
            if (words.words().size() > MAX_WORDS) {
                throw new SearchRefusedException(SEARCH_TOO_MANY_WORDS,
                        "A search can have at most " + MAX_WORDS + " words.");
            }
            slots.add(words);
        }
        return slots;
    }

    /** Whether {@code e} is the database cancelling a statement, at the timeout or on request. */
    static boolean cancelledByTheDatabase(Throwable e) {
        // However the layers above JDBC wrapped it (Spring's and JPA's timeout exceptions, or a
        // generic one around the driver's), the driver's own error says 57014. Bounded, in case a
        // chain of causes loops.
        Throwable cause = e;
        for (int depth = 0; cause != null && depth < 32; depth++, cause = cause.getCause()) {
            if (cause instanceof org.springframework.dao.QueryTimeoutException
                    || cause instanceof jakarta.persistence.QueryTimeoutException
                    || cause instanceof SQLException sql && QUERY_CANCELED.equals(sql.getSQLState())) {
                return true;
            }
        }
        return false;
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

    /**
     * A shop being listed: its view, its distance when there is a point, its matches, and the
     * database's count of them, less those found not live on reading.
     */
    private static final class Shop {
        private final StoreView view;
        private final Double distanceMetres;
        private final List<Hit> hits = new ArrayList<>();
        private int matched;
        private int dropped;

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
