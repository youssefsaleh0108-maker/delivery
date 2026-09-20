package com.delivery.product.domain;

import java.util.Collection;
import java.util.List;
import java.util.UUID;

import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.Repository;
import org.springframework.data.repository.query.Param;

/**
 * "Which of my own products is this?": one merchant's shops searched for what a photo was read as
 * ({@code PhotoFindService}).
 *
 * <p>A repository of its own rather than more methods on {@link ProductRepository}, for the reason
 * {@link ItemSearchRepository} is one: it answers with ids, tiers and scores rather than products, and
 * its SQL is where the matching rules live. Top-level, like every repository here.
 */
public interface ProductFindRepository extends Repository<Product, UUID> {

    /**
     * One of the merchant's products that matched, and how.
     *
     * @param tier  0 when the barcode is equal; then the item search's own tiers on the name
     * @param score orders matches within a tier, 0 to 1
     */
    record Found(UUID productId, UUID storeId, int tier, double score) {
    }

    /** The matches, best first. Mapped from {@link #findInStoresRows}; see there for the rules. */
    default List<Found> findInStores(Collection<UUID> storeIds, String p1, String w1, String p2,
                                     String w2, String p3, String w3, String barcode, int maxRows) {
        return findInStoresRows(storeIds, p1, w1, p2, w2, p3, w3, barcode, maxRows).stream()
                .map(row -> new Found(
                        (UUID) row[0],
                        (UUID) row[1],
                        ((Number) row[2]).intValue(),
                        ((Number) row[3]).doubleValue()))
                .toList();
    }

    /**
     * The merchant's own products that match a photo: rows of {@code (product id, store id, tier,
     * score)}, at most {@code maxRows}, best first.
     *
     * <p><strong>Scoped to the shops passed in</strong>, which the service has already checked belong
     * to the caller — one shop when the request named one, otherwise every goods shop the merchant
     * owns. Another merchant's products cannot appear, because no other merchant's shop id is ever in
     * this list.
     *
     * <p><strong>Every status.</strong> Unlike the customer item search
     * ({@link ItemSearchRepository#findCandidateRows}) this does not filter to ACTIVE and in stock: a
     * merchant photographing a pack wants to be told "you have it, it is paused" rather than be
     * offered to add a second copy of it. The status travels with the row and the client shows it.
     *
     * <p><strong>How it matches</strong>, exactly as the item search does, on {@code search_name}
     * (V37): tier 0 the barcode is equal (served by {@code idx_products_store_barcode}); tier 1 the
     * folded phrase is in the folded name; tier 2 every word of it is (a word of two characters as a
     * whole word); tier 3 its longest word, from four characters, sounds like a word of the name
     * (pg_trgm's strict word similarity at its 0.5 threshold). The three term slots are the photo's
     * name, Arabic name and brand.
     *
     * <p><strong>Cost.</strong> One merchant's shops, so the shop's size bounds the read and no index
     * on the words is needed — the partial trigram index covers only live products anyway. The service
     * caps the terms, as the item search does.
     *
     * <p>Parameters are never null and are cast to a type, as in {@link ItemSearchRepository}: {@code ''}
     * is an unused term slot and {@code ''} is no barcode. pg_trgm's names are qualified with
     * {@code public.}, where the extensions live.
     */
    @Query(value = """
            WITH raw AS NOT MATERIALIZED (
                SELECT NULLIF(CAST(:p1 AS text), '') AS p1,
                       NULLIF(CAST(:w1 AS text), '') AS w1,
                       NULLIF(CAST(:p2 AS text), '') AS p2,
                       NULLIF(CAST(:w2 AS text), '') AS w2,
                       NULLIF(CAST(:p3 AS text), '') AS p3,
                       NULLIF(CAST(:w3 AS text), '') AS w3,
                       NULLIF(CAST(:barcode AS varchar), '') AS barcode
            ),
            t AS NOT MATERIALIZED (
                SELECT r.p1, r.w1, r.p2, r.w2, r.p3, r.w3, r.barcode,
                       -- The phrase as it must appear: on a word boundary at an end whose word is short.
                       CASE WHEN char_length(split_part(r.p1, ' ', 1)) >= 3 THEN '' ELSE ' ' END || r.p1
                         || CASE WHEN char_length(substring(r.p1 FROM '[^ ]+$')) >= 3 THEN '' ELSE ' ' END AS n1,
                       CASE WHEN char_length(split_part(r.p2, ' ', 1)) >= 3 THEN '' ELSE ' ' END || r.p2
                         || CASE WHEN char_length(substring(r.p2 FROM '[^ ]+$')) >= 3 THEN '' ELSE ' ' END AS n2,
                       CASE WHEN char_length(split_part(r.p3, ' ', 1)) >= 3 THEN '' ELSE ' ' END || r.p3
                         || CASE WHEN char_length(substring(r.p3 FROM '[^ ]+$')) >= 3 THEN '' ELSE ' ' END AS n3,
                       -- The word that may only sound like a word of the name: the longest, from four
                       -- characters. No apostrophe anywhere in this SQL: the query parser counts quotes
                       -- without understanding comments, and one inside a comment reads as unterminated.
                       CASE WHEN char_length(split_part(r.w1, ' ', 1)) >= 4 THEN split_part(r.w1, ' ', 1) END AS z1,
                       CASE WHEN char_length(split_part(r.w2, ' ', 1)) >= 4 THEN split_part(r.w2, ' ', 1) END AS z2,
                       CASE WHEN char_length(split_part(r.w3, ' ', 1)) >= 4 THEN split_part(r.w3, ' ', 1) END AS z3
                  FROM raw r
            ),
            graded AS MATERIALIZED (
                SELECT p.id, p.store_id, p.name,
                       COALESCE(k.tier, 3) AS tier,
                       CAST(CASE k.tier
                              WHEN 0 THEN 1
                              WHEN 1 THEN GREATEST(
                                  CASE WHEN strpos(p.search_name, ' ' || t.p1 || ' ') > 0 THEN 1.0
                                       WHEN strpos(p.search_name, ' ' || t.p1) > 0 THEN 0.9
                                       WHEN strpos(p.search_name, t.n1) > 0 THEN 0.5 END,
                                  CASE WHEN strpos(p.search_name, ' ' || t.p2 || ' ') > 0 THEN 1.0
                                       WHEN strpos(p.search_name, ' ' || t.p2) > 0 THEN 0.9
                                       WHEN strpos(p.search_name, t.n2) > 0 THEN 0.5 END,
                                  CASE WHEN strpos(p.search_name, ' ' || t.p3 || ' ') > 0 THEN 1.0
                                       WHEN strpos(p.search_name, ' ' || t.p3) > 0 THEN 0.9
                                       WHEN strpos(p.search_name, t.n3) > 0 THEN 0.5 END)
                              WHEN 2 THEN GREATEST(public.strict_word_similarity(t.p1, p.search_name),
                                                   public.strict_word_similarity(t.p2, p.search_name),
                                                   public.strict_word_similarity(t.p3, p.search_name))
                              ELSE f.sound
                            END AS double precision) AS score
                  FROM products p
                 CROSS JOIN t
                 CROSS JOIN LATERAL (
                       SELECT CASE
                                WHEN t.barcode IS NOT NULL AND p.barcode = t.barcode THEN 0
                                WHEN strpos(p.search_name, t.n1) > 0
                                  OR strpos(p.search_name, t.n2) > 0
                                  OR strpos(p.search_name, t.n3) > 0 THEN 1
                                WHEN (t.w1 IS NOT NULL AND NOT EXISTS (
                                         SELECT 1 FROM unnest(string_to_array(t.w1, ' ')) AS x(word)
                                          WHERE strpos(p.search_name, CASE WHEN char_length(x.word) >= 3 THEN x.word
                                                                           ELSE ' ' || x.word || ' ' END) = 0))
                                  OR (t.w2 IS NOT NULL AND NOT EXISTS (
                                         SELECT 1 FROM unnest(string_to_array(t.w2, ' ')) AS x(word)
                                          WHERE strpos(p.search_name, CASE WHEN char_length(x.word) >= 3 THEN x.word
                                                                           ELSE ' ' || x.word || ' ' END) = 0))
                                  OR (t.w3 IS NOT NULL AND NOT EXISTS (
                                         SELECT 1 FROM unnest(string_to_array(t.w3, ' ')) AS x(word)
                                          WHERE strpos(p.search_name, CASE WHEN char_length(x.word) >= 3 THEN x.word
                                                                           ELSE ' ' || x.word || ' ' END) = 0)) THEN 2
                              END AS tier
                       OFFSET 0) k
                 CROSS JOIN LATERAL (
                       SELECT CASE WHEN k.tier IS NULL
                                   THEN GREATEST(public.strict_word_similarity(t.z1, p.search_name),
                                                 public.strict_word_similarity(t.z2, p.search_name),
                                                 public.strict_word_similarity(t.z3, p.search_name))
                              END AS sound
                       OFFSET 0) f
                 WHERE p.store_id IN (:storeIds)
                   AND (k.tier IS NOT NULL OR f.sound >= 0.5)
            )
            SELECT g.id, g.store_id, g.tier, g.score
              FROM graded g
             ORDER BY g.tier, g.score DESC, g.name, g.id
             LIMIT :maxRows
            """, nativeQuery = true)
    List<Object[]> findInStoresRows(@Param("storeIds") Collection<UUID> storeIds,
                                    @Param("p1") String p1,
                                    @Param("w1") String w1,
                                    @Param("p2") String p2,
                                    @Param("w2") String w2,
                                    @Param("p3") String p3,
                                    @Param("w3") String w3,
                                    @Param("barcode") String barcode,
                                    @Param("maxRows") int maxRows);

    /** Whether any of these shops already has a product with this barcode. */
    @Query(value = "SELECT EXISTS (SELECT 1 FROM products p WHERE p.store_id IN (:storeIds) "
            + "AND p.barcode = CAST(:barcode AS varchar))", nativeQuery = true)
    boolean barcodeTaken(@Param("storeIds") Collection<UUID> storeIds,
                         @Param("barcode") String barcode);

    /**
     * Bounds how long each statement of the current transaction may run, from the next one on, exactly
     * as {@link ItemSearchRepository#limitStatementTime} does for the customer's search — and for the
     * same reason: {@link #findInStoresRows} reads every product of the merchant's shops and measures
     * words against each, with no index to serve it, and a merchant with a large catalogue would
     * otherwise hold one of the ten pooled connections for as long as that took, after the reader slot
     * this request held was already given back.
     *
     * <p>SET LOCAL, which PostgreSQL undoes at commit or rollback, so the connection returns to the
     * pool with the server's own setting. A statement that runs past it is cancelled with SQLSTATE
     * 57014, which {@code PhotoFindService} answers as a 503.
     *
     * @param millis whole milliseconds, as text, which is what {@code set_config} takes
     */
    @Query(value = "SELECT set_config('statement_timeout', CAST(:millis AS text), true)", nativeQuery = true)
    String limitStatementTime(@Param("millis") String millis);
}
