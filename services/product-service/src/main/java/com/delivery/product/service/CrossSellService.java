package com.delivery.product.service;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Sort;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.product.domain.DeliveredOrderLineRepository;
import com.delivery.product.domain.Product;
import com.delivery.product.domain.ProductRepository;

/**
 * The "People Also Ordered" rail, computed from what people actually ordered.
 *
 * <p><strong>The point of this class is what it refuses to do.</strong> This service knows every
 * product in every shop, so filling a rail is trivial — and every number on a rail filled that way
 * would be invented. So there are exactly two bases here, each labelled on the item that carries it,
 * and neither is a guess:
 *
 * <ul>
 *   <li>{@link Basis#BOUGHT_TOGETHER} — counted from {@code delivered_order_lines}, the projection
 *       of delivered baskets added in V22. The number returned is the real count of delivered
 *       baskets containing both products. It is evidence.
 *   <li>{@link Basis#SAME_AISLE} — other things on the same shelf, with no count, because there is
 *       no count. It is "more like this", and it says so.
 * </ul>
 *
 * <p>It is not collaborative filtering, and nothing here claims to be. There is no per-customer
 * model, no similarity between shoppers, and no attempt at one: item co-occurrence is what the
 * available data supports, so item co-occurrence is what is computed and what the field names say.
 *
 * <p><strong>The rail starts with no evidence at all, and there is no way around that.</strong>
 * {@code delivered_order_lines} begins filling from {@code order.delivered} the moment V22 is
 * deployed and cannot be backfilled — this service physically cannot read the orders schema. Until
 * baskets accumulate, every suggestion comes back marked {@code SAME_AISLE}. That is the truth, and
 * it is precisely why the label is on each item rather than on the endpoint.
 */
@Service
public class CrossSellService {

    /**
     * Headroom on the co-occurrence query.
     *
     * <p>Some of what it returns will have been archived since it was sold and will disappear at the
     * {@code ACTIVE} filter. Without slack, a shop that has retired two popular items would show a
     * short rail for no reason a reader could see. Capped so a large {@code limit} cannot turn into
     * an unbounded query.
     */
    private static final int EVIDENCE_OVERFETCH = 3;
    private static final int EVIDENCE_CEILING = 60;

    private final DeliveredOrderLineRepository deliveredLines;
    private final ProductRepository products;
    private final long minOrdersTogether;

    public CrossSellService(DeliveredOrderLineRepository deliveredLines, ProductRepository products,
                            /*
                             * Two baskets, not one. A single shared basket is one stranger's
                             * shopping trip, and presenting it as "people also ordered" would turn
                             * an anecdote into a claim about a population. Two is a low bar and
                             * still a bar; raise it once there is volume.
                             */
                            @Value("${delivery.catalog.cross-sell.min-orders-together:2}")
                            long minOrdersTogether) {
        this.deliveredLines = deliveredLines;
        this.products = products;
        this.minOrdersTogether = minOrdersTogether;
    }

    /** How a suggestion was arrived at. Returned on every item; never left for a client to infer. */
    public enum Basis {
        /** Counted from delivered baskets that contained both products. */
        BOUGHT_TOGETHER,
        /** Another product on the same shelf. No popularity is claimed or implied. */
        SAME_AISLE
    }

    /**
     * One suggestion and its provenance.
     *
     * @param ordersTogether how many delivered baskets held both products, or null for
     *                       {@link Basis#SAME_AISLE}. Null, not zero — zero would read as "measured
     *                       and found to be none", when the truth is that nothing was measured.
     */
    public record Suggestion(Product product, Basis basis, Long ordersTogether) {
    }

    /**
     * What to show beside a product.
     *
     * <p>Real co-purchase evidence first, then same-shelf fill up to the requested size. Mixed
     * rather than either/or: a shop's best-evidenced pairing and its fourth are not equally well
     * evidenced, and cutting a young shop's rail off at two items looks broken — but promoting the
     * fill to look like evidence is the lie this class exists to avoid. Every item carries its own
     * basis, so a client can style the two differently or drop the fill entirely.
     *
     * @param product the product being viewed. Never appears in the result.
     * @param limit   the most suggestions to return
     */
    @Transactional(readOnly = true)
    public List<Suggestion> boughtTogetherWith(Product product, int limit) {
        if (limit <= 0) {
            return List.of();
        }

        // Holds everything already spoken for. The product itself goes in first and
        // unconditionally: a rail that recommends the thing you are already looking at is the most
        // obvious way for this feature to look broken, and putting it here rather than in each
        // branch means no later branch can forget it.
        Set<UUID> excluded = new LinkedHashSet<>();
        excluded.add(product.getId());

        List<Suggestion> suggestions = new ArrayList<>(limit);

        Map<UUID, Long> evidence = evidenced(product.getId(), limit);
        if (!evidence.isEmpty()) {
            for (Product candidate : activeInStore(product.getStoreId(), evidence.keySet())) {
                if (excluded.contains(candidate.getId())) {
                    continue;
                }
                suggestions.add(new Suggestion(candidate, Basis.BOUGHT_TOGETHER,
                        evidence.get(candidate.getId())));
            }

            // Re-sorted here because the catalog re-read returns rows in its own order, not the
            // order of the counts. Ties break on id so the rail does not reshuffle between
            // refreshes, which reads as a bug even when the contents are identical.
            suggestions.sort(Comparator
                    .comparing(Suggestion::ordersTogether, Comparator.reverseOrder())
                    .thenComparing(s -> s.product().getId()));

            if (suggestions.size() > limit) {
                suggestions.subList(limit, suggestions.size()).clear();
            }
            suggestions.forEach(s -> excluded.add(s.product().getId()));
        }

        fillFromSameAisle(product, limit - suggestions.size(), excluded, suggestions);
        return List.copyOf(suggestions);
    }

    // ---------------------------------------------------------------- internals

    /** Product ids sharing delivered baskets with this one, strongest first, with their counts. */
    private Map<UUID, Long> evidenced(UUID productId, int limit) {
        int fetch = Math.min(limit * EVIDENCE_OVERFETCH, EVIDENCE_CEILING);

        List<Object[]> rows = deliveredLines.findBoughtWith(
                productId, minOrdersTogether, PageRequest.of(0, Math.max(fetch, 1)));

        Map<UUID, Long> counts = new LinkedHashMap<>(rows.size());
        for (Object[] row : rows) {
            counts.put((UUID) row[0], ((Number) row[1]).longValue());
        }
        return counts;
    }

    /**
     * Re-reads candidates from the live catalog.
     *
     * <p>The projection remembers what was sold, which is not the same as what is on sale: a product
     * archived since is simply absent from this result, which is the correct outcome — the
     * alternative is offering a customer something the shop no longer sells. Same reasoning as Buy
     * Again in {@link CatalogService#readAllActive}.
     */
    private List<Product> activeInStore(UUID storeId, Set<UUID> ids) {
        if (ids.isEmpty()) {
            return List.of();
        }
        return products.findActiveInStoreByIds(storeId, ids, PageRequest.of(0, ids.size()))
                .getContent();
    }

    /**
     * Tops the rail up with other products from the same shop.
     *
     * <p>The same aisle first, because "another pizza" beats "a bin bag" when you are looking at a
     * pizza; then the whole shop when the aisle runs dry or the product has no category at all.
     *
     * <p>Ordered by name, and that is a deliberate non-choice. There is no popularity signal for
     * these — that is the whole distinction from the branch above — so the order is alphabetical and
     * obviously arbitrary rather than something dressed up to look ranked.
     */
    private void fillFromSameAisle(Product product, int wanted, Set<UUID> excluded,
                                   List<Suggestion> into) {
        if (wanted <= 0) {
            return;
        }

        Sort byName = Sort.by(Sort.Direction.ASC, "name");
        // Over-fetch by the exclusion count, so filtering out what is already on the rail cannot
        // leave it short of what was asked for.
        int fetch = wanted + excluded.size();

        // "%" rather than null: findActiveInStore takes an already-built LIKE pattern, and a null
        // there fails the whole query — see SearchPatterns.
        List<Product> shelf = new ArrayList<>(products.findActiveInStore(
                product.getStoreId(), product.getCategoryId(), "%",
                PageRequest.of(0, fetch, byName)).getContent());

        if (product.getCategoryId() != null && countAfterExclusions(shelf, excluded) < wanted) {
            shelf.addAll(products.findActiveInStore(
                    product.getStoreId(), null, "%",
                    PageRequest.of(0, fetch, byName)).getContent());
        }

        int added = 0;
        for (Product candidate : shelf) {
            if (added == wanted) {
                return;
            }
            // add() returning false means this one is the product itself, an already-evidenced
            // suggestion, or a duplicate from the widened second query.
            if (!excluded.add(candidate.getId())) {
                continue;
            }
            into.add(new Suggestion(candidate, Basis.SAME_AISLE, null));
            added++;
        }
    }

    private static long countAfterExclusions(List<Product> shelf, Set<UUID> excluded) {
        return shelf.stream().filter(p -> !excluded.contains(p.getId())).count();
    }
}
