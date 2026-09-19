package com.delivery.product.domain;

import java.util.List;
import java.util.UUID;

import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.Repository;
import org.springframework.data.repository.query.Param;

/**
 * The customer item search's one query: which live products, in which live goods shops, match what the
 * customer typed ({@code ItemSearchService}).
 *
 * <p>A repository of its own rather than more methods on {@link ProductRepository}, because it answers
 * with ids, tiers and scores rather than products, and because its SQL is the one place the matching
 * rules live. Top-level, like every repository here: Spring's scan ignores one declared as a nested
 * interface, and a service built on it would fail only at deploy.
 */
public interface ItemSearchRepository extends Repository<Product, UUID> {

    /**
     * One product that matched, and how well.
     *
     * @param tier  0 when the barcode is equal; 1 when a folded term is a substring of the folded name;
     *              2 when every word of a folded term is; 3 when a folded term only sounds like part of
     *              the name (trigram word similarity at or above pg_trgm's threshold)
     * @param score the best word similarity of any term to the folded name, 0 to 1; 0 for a match on the
     *              barcode alone. Orders matches within a tier.
     */
    record Candidate(UUID productId, UUID storeId, int tier, double score) {
    }

    /**
     * The candidates, best first: tier, then score, then product id so that a refresh does not reshuffle
     * two equal matches. Mapped from {@link #findCandidateRows}; see there for the rules.
     */
    default List<Candidate> findCandidates(String t1, String t2, String t3, String barcode,
                                           boolean near, double latitude, double longitude,
                                           double radiusMetres, double circleSlack, int maxRows) {
        return findCandidateRows(t1, t2, t3, barcode, near, latitude, longitude, radiusMetres,
                circleSlack, maxRows).stream()
                .map(row -> new Candidate(
                        (UUID) row[0],
                        (UUID) row[1],
                        ((Number) row[2]).intValue(),
                        ((Number) row[3]).doubleValue()))
                .toList();
    }

    /**
     * Live products of live goods shops that match up to three terms or a barcode: rows of
     * {@code (product id, store id, tier, score)}, best first, at most {@code maxRows}.
     *
     * <p><strong>What may match.</strong> A product that is ACTIVE and in stock, in a shop that is ACTIVE
     * and is not a service shop. The last is a literal, as in every goods read
     * ({@link StoreRepository#findStorefrontWithStatus}): a print shop's "Pepsi flyers" offer is never an
     * item a customer can have delivered. With a point, the shop must be pinned within
     * {@code radiusMetres} of it, and when the shop drew a delivery circle (V24), the point must be inside
     * that too. Both carry {@code circleSlack} over the radius the caller means, for the reason
     * {@link StoreRepository#findActiveIdsNear} gives: the database measures on the spheroid and the
     * service judges every row again on the sphere, so a shop just inside by one and just outside by the
     * other is left for the service to decide. Without a point, every live goods shop is searched.
     *
     * <p><strong>How it matches.</strong> Each term and the product's name are compared folded
     * ({@code search_fold}, V37): lower case, one spelling for each Arabic letter family, Western
     * digits, no accents, vowel marks or apostrophes, and single spaces between words. The name is
     * folded once, into {@code products.search_name}; each term is folded here. The tiers are those of
     * {@link Candidate#tier}, and a row is returned only when it reaches one of them.
     *
     * <p><strong>Why the WHERE says it twice.</strong> The trigram index on {@code search_name} (V37) can
     * answer {@code LIKE '%...%'} and the word-similarity operator, but not {@code strpos} or a
     * subquery. So the WHERE first narrows by what the index can answer, and the rows it lets through are
     * then held to the exact tiers: the first word of a term appears in the name (which every substring
     * and every all-words match satisfies), or the term sounds like part of the name. A bitmap scan can
     * OR those together only when every branch is indexable, which is also why the barcode branch is
     * written as its own index (V37's {@code idx_products_barcode_live}) can serve.
     *
     * <p><strong>Parameters.</strong> Never null, and cast to a type, as in {@link StoreRepository}: an
     * untyped null is one PostgreSQL cannot infer a type for. So {@code ''} is an unused term slot and
     * {@code ''} is no barcode, and without a point {@code near} is false and the coordinates are
     * ignored. A term that folds to nothing (only punctuation) matches nothing: it becomes NULL here, and
     * every comparison with NULL fails. pg_trgm's names are qualified with {@code public.}, where the
     * extension lives; this service's search path holds only its own schema.
     *
     * <p>The folded terms come from a subquery in the FROM clause that PostgreSQL pulls up into the
     * query, so each one is a value computed once from the parameters rather than a column of another
     * table: that is what lets the index use them. {@code ItemSearchDatabaseTest} holds the plan to it
     * with sequential scans switched off, and checks every tier against a real database.
     *
     * @param t1           the first term, or {@code ''}
     * @param t2           the second term, or {@code ''}
     * @param t3           the third term, or {@code ''}
     * @param barcode      digits to match exactly, or {@code ''}
     * @param near         whether the point applies
     * @param radiusMetres the circle around the point, with the slack already added
     * @param circleSlack  what a shop's own delivery circle is multiplied by, for the same reason
     * @param maxRows      the {@code LIMIT}; the service asks for one more than it will use
     */
    @Query(value = """
            SELECT m.product_id, m.store_id, m.tier, m.score
              FROM (
                    SELECT p.id AS product_id,
                           p.store_id,
                           CASE
                             WHEN t.barcode <> '' AND p.barcode = t.barcode THEN 0
                             WHEN strpos(p.search_name, t.f1) > 0
                               OR strpos(p.search_name, t.f2) > 0
                               OR strpos(p.search_name, t.f3) > 0 THEN 1
                             WHEN (t.f1 IS NOT NULL AND NOT EXISTS (
                                      SELECT 1 FROM unnest(string_to_array(t.f1, ' ')) AS w(word)
                                       WHERE strpos(p.search_name, w.word) = 0))
                               OR (t.f2 IS NOT NULL AND NOT EXISTS (
                                      SELECT 1 FROM unnest(string_to_array(t.f2, ' ')) AS w(word)
                                       WHERE strpos(p.search_name, w.word) = 0))
                               OR (t.f3 IS NOT NULL AND NOT EXISTS (
                                      SELECT 1 FROM unnest(string_to_array(t.f3, ' ')) AS w(word)
                                       WHERE strpos(p.search_name, w.word) = 0)) THEN 2
                             WHEN t.f1 OPERATOR(public.<%) p.search_name
                               OR t.f2 OPERATOR(public.<%) p.search_name
                               OR t.f3 OPERATOR(public.<%) p.search_name THEN 3
                           END AS tier,
                           COALESCE(GREATEST(public.word_similarity(t.f1, p.search_name),
                                             public.word_similarity(t.f2, p.search_name),
                                             public.word_similarity(t.f3, p.search_name)), 0) AS score
                      FROM products p
                      JOIN stores s ON s.id = p.store_id
                     CROSS JOIN (SELECT NULLIF(search_fold(CAST(:t1 AS text)), '') AS f1,
                                        NULLIF(search_fold(CAST(:t2 AS text)), '') AS f2,
                                        NULLIF(search_fold(CAST(:t3 AS text)), '') AS f3,
                                        CAST(:barcode AS varchar) AS barcode) t
                     WHERE p.status = 'ACTIVE'
                       AND p.in_stock
                       AND s.status = 'ACTIVE'
                       AND s.vertical <> 'SERVICES'
                       AND (NOT CAST(:near AS boolean)
                            OR (s.location IS NOT NULL
                                AND public.ST_DWithin(
                                        s.location,
                                        public.ST_SetSRID(public.ST_MakePoint(:longitude, :latitude), 4326)::public.geography,
                                        :radiusMetres)
                                AND (s.delivery_radius_metres IS NULL
                                     OR public.ST_DWithin(
                                            s.location,
                                            public.ST_SetSRID(public.ST_MakePoint(:longitude, :latitude), 4326)::public.geography,
                                            s.delivery_radius_metres * CAST(:circleSlack AS double precision)))))
                       AND ((t.barcode <> '' AND p.barcode = t.barcode)
                            OR p.search_name LIKE '%' || split_part(t.f1, ' ', 1) || '%'
                            OR t.f1 OPERATOR(public.<%) p.search_name
                            OR p.search_name LIKE '%' || split_part(t.f2, ' ', 1) || '%'
                            OR t.f2 OPERATOR(public.<%) p.search_name
                            OR p.search_name LIKE '%' || split_part(t.f3, ' ', 1) || '%'
                            OR t.f3 OPERATOR(public.<%) p.search_name)
                   ) m
             WHERE m.tier IS NOT NULL
             ORDER BY m.tier, m.score DESC, m.product_id
             LIMIT :maxRows
            """, nativeQuery = true)
    List<Object[]> findCandidateRows(@Param("t1") String t1,
                                     @Param("t2") String t2,
                                     @Param("t3") String t3,
                                     @Param("barcode") String barcode,
                                     @Param("near") boolean near,
                                     @Param("latitude") double latitude,
                                     @Param("longitude") double longitude,
                                     @Param("radiusMetres") double radiusMetres,
                                     @Param("circleSlack") double circleSlack,
                                     @Param("maxRows") int maxRows);
}
