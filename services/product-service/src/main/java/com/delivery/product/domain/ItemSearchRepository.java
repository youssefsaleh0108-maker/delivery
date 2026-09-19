package com.delivery.product.domain;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.Repository;
import org.springframework.data.repository.query.Param;

/**
 * The customer item search's queries: which live products, in which live goods shops open now, match
 * what the customer typed ({@code ItemSearchService}).
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
     * @param tier           0 when the barcode is equal; 1 when the folded term is in the folded name;
     *                       2 when every word of it is; 3 when its longest word only sounds like part of
     *                       the name (pg_trgm's strict word similarity, at or above its threshold)
     * @param score          orders matches within a tier, 0 to 1: for tier 1, 1 when the term is whole
     *                       words of the name, 0.9 when it starts a word, 0.5 inside one; for tiers 2 and
     *                       3, the strict word similarity; 0 for a match on the barcode alone
     * @param matchedInStore how many of this shop's products matched in all, however many the query kept
     */
    record Candidate(UUID productId, UUID storeId, int tier, double score, int matchedInStore) {
    }

    /**
     * The candidates, best first. Mapped from {@link #findCandidateRows}; see there for the rules.
     */
    default List<Candidate> findCandidates(String p1, String w1, String p2, String w2, String p3,
                                           String w3, String barcode, boolean near, double latitude,
                                           double longitude, double radiusMetres, double circleSlack,
                                           Instant now, int perStore, int maxRows) {
        return findCandidateRows(p1, w1, p2, w2, p3, w3, barcode, near, latitude, longitude, radiusMetres,
                circleSlack, now, perStore, maxRows).stream()
                .map(row -> new Candidate(
                        (UUID) row[0],
                        (UUID) row[1],
                        ((Number) row[2]).intValue(),
                        ((Number) row[3]).doubleValue(),
                        ((Number) row[4]).intValue()))
                .toList();
    }

    /**
     * Live products of live goods shops, open now, that match up to three terms or a barcode: rows of
     * {@code (product id, store id, tier, score, matched in store)}, at most {@code perStore} for each
     * shop and {@code maxRows} in all, best first.
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
     * <p><strong>Closed shops are left out here</strong>, before the caps, so that at night the few shops
     * still open are not crowded out of the answer by closed ones the service would drop anyway. Closed
     * means what {@code Store.availabilityAt} means by it: no opening window of the shop's covers the
     * time at the shop, read in the shop's own zone ({@code search_local_time}, V37) from the same
     * {@code now} the service judges with. The service still decides every shop it lists; this may only
     * skip one both call closed. A zone this database cannot read the way the service does leaves the
     * shop in, for the service to judge.
     *
     * <p><strong>How it matches.</strong> The service folds each term ({@code search_fold}, V37, through
     * {@link ProductRepository#foldForSearch}) and passes it as {@code p}, the folded phrase, and {@code w},
     * its words of two characters or more, longest first; a one-character word ("1" or "l" of "1.5 l")
     * is matched only as part of the phrase. The name was folded once, into {@code products.search_name},
     * which has a space at each end, so a whole word is always {@code ' word '}. A word of three
     * characters or more matches anywhere in the name; a word of two matches only a whole word, so
     * "رز" (rice) finds rice and not every word that contains those two letters, and the two letters
     * every Arabic word with the article starts with ("ال") read almost nothing. A phrase whose first or
     * last word is that short must start or end on a word boundary there. Then:
     * <ul>
     *   <li>tier 0: the barcode is equal;
     *   <li>tier 1: the phrase is in the name;
     *   <li>tier 2: every word is;
     *   <li>tier 3: the longest word, when it has four characters or more, sounds like a word of the name:
     *       pg_trgm's strict word similarity at its default 0.5. Strict, because plain word similarity
     *       reached 0.6 whenever the first three letters agreed, so "milk" found "mild cheddar", "rice"
     *       "ricotta" and "tuna" "tunisian"; typos ("pepsy", "choclate") still reach 0.5.
     * </ul>
     *
     * <p><strong>Which rows are kept.</strong> Each shop keeps its best {@code perStore} matches (tier,
     * score, product id), and says how many matched in all ({@code matched in store}, a count over the
     * shop, before that cut). Then the rows are ordered as the service orders shops: tier, score, the
     * nearer shop (on the sphere, as the service measures, so the two agree on who is nearer), the better
     * rated one (which is what decides without a point), then the ids; and the first {@code maxRows} are
     * returned. So past the cap it is the farther shops and the weaker matches that are left out, never
     * the nearest shop selling the same thing, and one shop with forty kinds of Pepsi takes three rows,
     * not forty.
     *
     * <p><strong>Cost.</strong> The words decide what is read, not the catalogue. {@code hit} is served
     * by the trigram index (V37) alone, with one pattern per term, on its longest word: a word of three
     * characters or more by its trigrams, a word of two by the trigrams at its start and end. It is
     * materialized, so the planner cannot trade it for walking every product of every nearby shop, which
     * costs a filter per product and grows with how dense the neighbourhood is. The shops are judged
     * once each, not once per product. The service bounds the rest: at most three terms of at most five
     * words, and a statement timeout.
     *
     * <p><strong>Parameters.</strong> Never null, and cast to a type, as in {@link StoreRepository}: an
     * untyped null is one PostgreSQL cannot infer a type for. So {@code ''} is an unused term slot and
     * {@code ''} is no barcode, and without a point {@code near} is false and the coordinates are
     * ignored. {@code ''} becomes NULL here, and every comparison with NULL fails, so an unused slot
     * matches nothing and costs nothing: a pattern that is NULL reads no index entries. pg_trgm's and
     * PostGIS's names are qualified with {@code public.}, where the extensions live; this service's search
     * path holds only its own schema.
     *
     * <p>The terms' values come from {@code t}, which is inlined (NOT MATERIALIZED) into every query that
     * reads it, so each one is an expression of the parameters rather than a column of another table:
     * that is what lets the index use them, in the plan for this search's values and in the generic plan
     * a prepared statement moves to. {@code ItemSearchDatabaseTest} holds both plans to the index, and
     * checks every tier, the caps and the order against a real database.
     *
     * @param p1           the first term, folded, or {@code ''}
     * @param w1           its words of two characters or more, longest first, space-separated
     * @param barcode      digits to match exactly, or {@code ''}
     * @param near         whether the point applies
     * @param radiusMetres the circle around the point, with the slack already added
     * @param circleSlack  what a shop's own delivery circle is multiplied by, for the same reason
     * @param now          the instant "open now" is judged at: the service's, so both judge the same one
     * @param perStore     how many of one shop's matches are returned
     * @param maxRows      the {@code LIMIT}; the service asks for one more than it will use
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
                       -- The index's pattern, on the longest word: anywhere, or a whole word of two.
                       CASE WHEN char_length(split_part(r.w1, ' ', 1)) >= 3 THEN '%' || split_part(r.w1, ' ', 1) || '%'
                            ELSE '% ' || split_part(r.w1, ' ', 1) || ' %' END AS l1,
                       CASE WHEN char_length(split_part(r.w2, ' ', 1)) >= 3 THEN '%' || split_part(r.w2, ' ', 1) || '%'
                            ELSE '% ' || split_part(r.w2, ' ', 1) || ' %' END AS l2,
                       CASE WHEN char_length(split_part(r.w3, ' ', 1)) >= 3 THEN '%' || split_part(r.w3, ' ', 1) || '%'
                            ELSE '% ' || split_part(r.w3, ' ', 1) || ' %' END AS l3,
                       -- The word that may only sound like the name's: the longest, from four characters.
                       CASE WHEN char_length(split_part(r.w1, ' ', 1)) >= 4 THEN split_part(r.w1, ' ', 1) END AS z1,
                       CASE WHEN char_length(split_part(r.w2, ' ', 1)) >= 4 THEN split_part(r.w2, ' ', 1) END AS z2,
                       CASE WHEN char_length(split_part(r.w3, ' ', 1)) >= 4 THEN split_part(r.w3, ' ', 1) END AS z3
                  FROM raw r
            ),
            hit AS MATERIALIZED (
                SELECT p.id, p.store_id, p.search_name, p.barcode
                  FROM products p, t
                 WHERE p.status = 'ACTIVE'
                   AND p.in_stock
                   AND ((t.barcode IS NOT NULL AND p.barcode = t.barcode)
                        OR p.search_name LIKE t.l1 OR t.z1 OPERATOR(public.<<%) p.search_name
                        OR p.search_name LIKE t.l2 OR t.z2 OPERATOR(public.<<%) p.search_name
                        OR p.search_name LIKE t.l3 OR t.z3 OPERATOR(public.<<%) p.search_name)
            ),
            shop AS MATERIALIZED (
                SELECT s.id,
                       s.rating,
                       CASE WHEN CAST(:near AS boolean)
                            THEN public.ST_Distance(
                                     s.location,
                                     public.ST_SetSRID(public.ST_MakePoint(:longitude, :latitude), 4326)::public.geography,
                                     false)
                            ELSE 0 END AS distance
                  FROM stores s
                  JOIN (SELECT DISTINCT store_id FROM hit) d ON d.store_id = s.id
                  LEFT JOIN LATERAL (SELECT search_local_time(s.timezone, CAST(:now AS timestamptz)) AS at
                                     OFFSET 0) z ON true
                 WHERE s.status = 'ACTIVE'
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
                   AND (z.at IS NULL
                        OR EXISTS (SELECT 1 FROM store_hours h
                                    WHERE h.store_id = s.id
                                      AND h.day_of_week = CAST(EXTRACT(ISODOW FROM z.at) AS smallint)
                                      AND h.opens_at <= CAST(z.at AS time)
                                      AND h.closes_at > CAST(z.at AS time)))
            ),
            graded AS MATERIALIZED (
                SELECT h.id, h.store_id, sh.rating, sh.distance,
                       COALESCE(k.tier, 3) AS tier,
                       CAST(CASE k.tier
                              WHEN 0 THEN 0
                              WHEN 1 THEN GREATEST(
                                  CASE WHEN strpos(h.search_name, ' ' || t.p1 || ' ') > 0 THEN 1.0
                                       WHEN strpos(h.search_name, ' ' || t.p1) > 0 THEN 0.9
                                       WHEN strpos(h.search_name, t.n1) > 0 THEN 0.5 END,
                                  CASE WHEN strpos(h.search_name, ' ' || t.p2 || ' ') > 0 THEN 1.0
                                       WHEN strpos(h.search_name, ' ' || t.p2) > 0 THEN 0.9
                                       WHEN strpos(h.search_name, t.n2) > 0 THEN 0.5 END,
                                  CASE WHEN strpos(h.search_name, ' ' || t.p3 || ' ') > 0 THEN 1.0
                                       WHEN strpos(h.search_name, ' ' || t.p3) > 0 THEN 0.9
                                       WHEN strpos(h.search_name, t.n3) > 0 THEN 0.5 END)
                              WHEN 2 THEN GREATEST(public.strict_word_similarity(t.p1, h.search_name),
                                                   public.strict_word_similarity(t.p2, h.search_name),
                                                   public.strict_word_similarity(t.p3, h.search_name))
                              ELSE f.sound
                            END AS double precision) AS score
                  FROM hit h
                  JOIN shop sh ON sh.id = h.store_id
                 CROSS JOIN t
                 -- Tiers 0 to 2, worked out once per product (OFFSET 0 keeps the planner from copying
                 -- the expression into every place that reads it).
                 CROSS JOIN LATERAL (
                       SELECT CASE
                                WHEN t.barcode IS NOT NULL AND h.barcode = t.barcode THEN 0
                                WHEN strpos(h.search_name, t.n1) > 0
                                  OR strpos(h.search_name, t.n2) > 0
                                  OR strpos(h.search_name, t.n3) > 0 THEN 1
                                WHEN (t.w1 IS NOT NULL AND NOT EXISTS (
                                         SELECT 1 FROM unnest(string_to_array(t.w1, ' ')) AS x(word)
                                          WHERE strpos(h.search_name, CASE WHEN char_length(x.word) >= 3 THEN x.word
                                                                           ELSE ' ' || x.word || ' ' END) = 0))
                                  OR (t.w2 IS NOT NULL AND NOT EXISTS (
                                         SELECT 1 FROM unnest(string_to_array(t.w2, ' ')) AS x(word)
                                          WHERE strpos(h.search_name, CASE WHEN char_length(x.word) >= 3 THEN x.word
                                                                           ELSE ' ' || x.word || ' ' END) = 0))
                                  OR (t.w3 IS NOT NULL AND NOT EXISTS (
                                         SELECT 1 FROM unnest(string_to_array(t.w3, ' ')) AS x(word)
                                          WHERE strpos(h.search_name, CASE WHEN char_length(x.word) >= 3 THEN x.word
                                                                           ELSE ' ' || x.word || ' ' END) = 0)) THEN 2
                              END AS tier
                       OFFSET 0) k
                 -- Tier 3: how the longest word sounds, only for a product no better tier took, once.
                 -- 0.5 is pg_trgm's strict word similarity threshold, which the index's <<% applies.
                 CROSS JOIN LATERAL (
                       SELECT CASE WHEN k.tier IS NULL
                                   THEN GREATEST(public.strict_word_similarity(t.z1, h.search_name),
                                                 public.strict_word_similarity(t.z2, h.search_name),
                                                 public.strict_word_similarity(t.z3, h.search_name))
                              END AS sound
                       OFFSET 0) f
                 WHERE k.tier IS NOT NULL
                    OR f.sound >= 0.5
            )
            SELECT r.id, r.store_id, r.tier, r.score, r.matched_in_store
              FROM (SELECT g.id, g.store_id, g.tier, g.score, g.distance, g.rating,
                           row_number() OVER (PARTITION BY g.store_id
                                              ORDER BY g.tier, g.score DESC, g.id) AS rank_in_store,
                           count(*) OVER (PARTITION BY g.store_id) AS matched_in_store
                      FROM graded g) r
             WHERE r.rank_in_store <= :perStore
             ORDER BY r.tier, r.score DESC, r.distance, r.rating DESC NULLS LAST, r.store_id, r.id
             LIMIT :maxRows
            """, nativeQuery = true)
    List<Object[]> findCandidateRows(@Param("p1") String p1,
                                     @Param("w1") String w1,
                                     @Param("p2") String p2,
                                     @Param("w2") String w2,
                                     @Param("p3") String p3,
                                     @Param("w3") String w3,
                                     @Param("barcode") String barcode,
                                     @Param("near") boolean near,
                                     @Param("latitude") double latitude,
                                     @Param("longitude") double longitude,
                                     @Param("radiusMetres") double radiusMetres,
                                     @Param("circleSlack") double circleSlack,
                                     @Param("now") Instant now,
                                     @Param("perStore") int perStore,
                                     @Param("maxRows") int maxRows);

    /**
     * Bounds how long each statement of the current transaction may run, from the next one on: SET
     * LOCAL statement_timeout, which PostgreSQL enforces itself and undoes at commit or rollback, so the
     * connection goes back to the pool with its own setting. A statement that runs past it is cancelled
     * with SQLSTATE 57014, which {@code ItemSearchService} answers as a 503.
     *
     * <p>A SELECT of {@code set_config} rather than a SET, because a repository runs queries; the answer
     * is the setting as applied, which nobody needs.
     *
     * @param millis whole milliseconds, as text, which is what {@code set_config} takes
     */
    @Query(value = "SELECT set_config('statement_timeout', CAST(:millis AS text), true)", nativeQuery = true)
    String limitStatementTime(@Param("millis") String millis);
}
