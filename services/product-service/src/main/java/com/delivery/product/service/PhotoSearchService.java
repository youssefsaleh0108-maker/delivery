package com.delivery.product.service;

import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Optional;
import java.util.Set;

import org.springframework.core.env.Environment;
import org.springframework.stereotype.Service;

import com.delivery.product.domain.GeoPoint;
import com.delivery.product.domain.PhotoSearchUse.Kind;
import com.delivery.product.domain.ProductRepository;
import com.delivery.product.service.ItemSearchService.ItemQuery;
import com.delivery.product.service.ItemSearchService.ItemSearchResult;
import com.delivery.product.vision.Descriptions;
import com.delivery.product.vision.VisionProvider;
import com.delivery.product.vision.VisionProviders;

/**
 * A customer searches the shops by photo: the photo is read as words, and the words are searched as
 * the item search searches what a customer types ({@link ItemSearchService}).
 *
 * <p><strong>Only ever a real reader.</strong> The provider is {@link VisionProviders#real}, never the
 * fake that {@code active()} falls back to for Blitz: a sample answer for a customer would be shops
 * selling something the customer never photographed, with no label to say so. Until the owner switches
 * real recognition on — and while {@code customer-enabled} is off — {@link #available} is false, the app
 * draws no camera ({@code GET /api/products/search/capabilities}), and the endpoint answers 503
 * {@code PHOTO_SEARCH_UNAVAILABLE} without reading anything or calling anyone. Text search is untouched.
 *
 * <p><strong>The flow.</strong> {@link PhotoReader} reads the photo under its concurrency limit and
 * counts the use ({@link PhotoQuota}, {@code CUSTOMER_SEARCH}) just before the provider is asked. A
 * photo of no product is an answer: an empty page. Otherwise the search runs on the name, the Arabic
 * name and the brand, with the barcode when one was legible — the item search's three term slots and its
 * barcode tier. If that finds nothing, it runs again on the generic keywords ("cola", "مشروب غازي") and
 * the answer says {@code similar}: not what was photographed, but the same kind of thing.
 *
 * <p><strong>Words the search accepts.</strong> The item search refuses what a person could not have
 * meant to type (a term under two characters, more than five words), and a reader's words are not
 * typed: "Nido Fortified Full Cream Milk Powder 900g" is seven. So each term is spelled here as the
 * search spells it ({@code search_fold}, through {@link ProductRepository#foldForSearch}) and cut to
 * its first five words, and those spellings are what is searched and what {@code nextQuery} hands back
 * for the next page, which the app asks of the text search ({@code POST /items}): the fold of a folded
 * term is itself, so page two matches exactly as page one did, and the photo is sent once.
 */
@Service
public class PhotoSearchService {

    /** The switch that keeps customers off while merchants use the reader. Read per call. */
    static final String CUSTOMER_ENABLED = "delivery.catalog.photo-search.customer-enabled";

    /**
     * What a photo came to.
     *
     * @param understood what the photo was read as, sanitised
     * @param result     the page of shops; empty for a photo of no product
     * @param similar    true when nothing matched the product itself and these match its keywords
     * @param nextQuery  what was searched, for the next page; null when nothing could be
     * @param left       the account's photo searches left over the rolling day
     */
    public record PhotoSearchResult(Descriptions.Clean understood, ItemSearchResult result, boolean similar,
                                    ItemQuery nextQuery, int left) {
    }

    private final VisionProviders providers;
    private final PhotoReader reader;
    private final PhotoQuota quota;
    private final ItemSearchService itemSearch;
    private final ProductRepository products;
    private final Environment environment;

    public PhotoSearchService(VisionProviders providers, PhotoReader reader, PhotoQuota quota,
                              ItemSearchService itemSearch, ProductRepository products,
                              Environment environment) {
        this.providers = providers;
        this.reader = reader;
        this.quota = quota;
        this.itemSearch = itemSearch;
        this.products = products;
        this.environment = environment;
    }

    /** Whether customers may search by photo right now: switched on, and a real reader ready. */
    public boolean available() {
        return customerEnabled() && providers.real().isPresent();
    }

    /** The customer's photo searches left today, without counting one. */
    public int left(String accountId) {
        return quota.left(accountId, Kind.CUSTOMER_SEARCH);
    }

    /**
     * Reads {@code photo} and searches for what it shows.
     *
     * @param centre where the customer is, or null to search every live goods shop
     * @param size   shops on the first page; the next pages are the text search's
     * @throws PhotoSearchException every refusal: unavailable, a limit, a busy reader, an unreadable
     *                              photo, a refusal or a failure of the provider
     */
    public PhotoSearchResult search(String accountId, byte[] photo, GeoPoint centre, int size) {
        VisionProvider provider = customerEnabled() ? providers.real().orElse(null) : null;
        if (provider == null) {
            throw PhotoSearchException.unavailable();
        }
        PhotoReader.Reading reading = reader.read(photo, provider,
                () -> quota.take(accountId, Kind.CUSTOMER_SEARCH));
        Descriptions.Clean understood = reading.description();
        if (!understood.isProduct()) {
            return new PhotoSearchResult(understood, itemSearch.nothing(centre, size), false, null,
                    reading.left());
        }

        Optional<ItemQuery> exact = queryOf(
                nonNull(understood.name(), understood.nameAr(), understood.brand()), understood.barcode());
        ItemSearchResult found = null;
        if (exact.isPresent()) {
            found = itemSearch.search(exact.get(), centre, 0, size);
            if (found.page().getTotalElements() > 0) {
                return new PhotoSearchResult(understood, found, false, exact.get(), reading.left());
            }
        }

        Optional<ItemQuery> loose = queryOf(understood.keywords(), null);
        if (loose.isPresent()) {
            ItemSearchResult similar = itemSearch.search(loose.get(), centre, 0, size);
            boolean anySimilar = similar.page().getTotalElements() > 0;
            if (anySimilar || found == null) {
                // "No exact match, but here are similar items" only when there ARE items: over an
                // empty page that line promises something the page does not have. An empty keyword
                // answer, reached because the reading gave nothing exact to search for, is just an
                // empty answer.
                return new PhotoSearchResult(understood, similar, anySimilar, loose.get(),
                        reading.left());
            }
        }
        return found == null
                ? new PhotoSearchResult(understood, itemSearch.nothing(centre, size), false, null, reading.left())
                : new PhotoSearchResult(understood, found, false, exact.get(), reading.left());
    }

    private boolean customerEnabled() {
        return environment.getProperty(CUSTOMER_ENABLED, Boolean.class, Boolean.TRUE);
    }

    private static List<String> nonNull(String... values) {
        List<String> kept = new ArrayList<>();
        for (String value : values) {
            if (value != null) {
                kept.add(value);
            }
        }
        return kept;
    }

    /**
     * The query for up to {@value ItemSearchService#MAX_TERMS} of {@code candidates}, each as the search
     * spells it and cut to what the search accepts, and the barcode; empty when none survives and there
     * is no barcode. Duplicates (a brand that is also the name) are searched once.
     */
    Optional<ItemQuery> queryOf(List<String> candidates, String barcode) {
        Set<String> terms = new LinkedHashSet<>();
        List<String> pending = new ArrayList<>(candidates);
        while (!pending.isEmpty() && terms.size() < ItemSearchService.MAX_TERMS) {
            // The fold takes three at a time; a keyword that folds to nothing makes room for the next.
            List<String> batch = new ArrayList<>(pending.subList(0, Math.min(3, pending.size())));
            pending = new ArrayList<>(pending.subList(batch.size(), pending.size()));
            while (batch.size() < 3) {
                batch.add("");
            }
            for (String folded : products.foldForSearch(batch.get(0), batch.get(1), batch.get(2))) {
                String term = searchable(folded);
                if (term != null && terms.size() < ItemSearchService.MAX_TERMS) {
                    terms.add(term);
                }
            }
        }
        if (terms.isEmpty() && barcode == null) {
            return Optional.empty();
        }
        return Optional.of(ItemQuery.of(null, List.copyOf(terms), barcode));
    }

    /**
     * A folded term cut to what the item search accepts: its words in order until the fifth of two
     * characters or more, and no more than {@value ItemSearchService#MAX_TERM_LENGTH} characters; null
     * when it has no word of two characters, which the search cannot match.
     */
    static String searchable(String folded) {
        if (folded == null || folded.isBlank()) {
            return null;
        }
        StringBuilder kept = new StringBuilder();
        int words = 0;
        for (String word : folded.strip().split(" ")) {
            if (word.isEmpty()) {
                continue;
            }
            boolean counted = word.codePointCount(0, word.length()) >= SearchWords.MIN_WORD_LENGTH;
            if (counted && words == ItemSearchService.MAX_WORDS) {
                break;
            }
            String next = kept.isEmpty() ? word : kept + " " + word;
            if (next.codePointCount(0, next.length()) > ItemSearchService.MAX_TERM_LENGTH) {
                break;
            }
            kept.setLength(0);
            kept.append(next);
            if (counted) {
                words++;
            }
        }
        String term = kept.toString();
        if (words == 0 || term.codePointCount(0, term.length()) < ItemSearchService.MIN_TERM_LENGTH) {
            return null;
        }
        return term;
    }
}
