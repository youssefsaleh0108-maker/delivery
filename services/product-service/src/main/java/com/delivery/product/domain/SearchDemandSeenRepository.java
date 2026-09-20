package com.delivery.product.domain;

import java.time.Instant;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/**
 * The people behind a week's terms, counted and never named.
 *
 * <p>Three operations and no fourth: remember that somebody asked, count how many somebodies a term
 * had, and forget the weeks that are past. There is deliberately no finder that takes a key — asking
 * "is this value in the table" would be the one question that turns an unlinkable HMAC into a test
 * for a person somebody already suspects.
 */
public interface SearchDemandSeenRepository extends JpaRepository<SearchDemandSeen, String> {

    /**
     * Writes the row if this person has not already asked for this term, in this area, this week.
     *
     * <p>{@code ON CONFLICT DO NOTHING} rather than a read followed by a write: the recorder runs on
     * its own thread beside however many replicas, and the primary key is the only thing that can
     * decide a tie without a lock. A row that was already there is not an error and not a retry.
     *
     * @return 1 when this was the first time, 0 when it was not
     */
    @Modifying
    @Query(value = """
            INSERT INTO search_demand_seen (seen_key, key_id, week_start, area_id, term, created_at)
            VALUES (:seenKey, :keyId, :weekStart, :areaId, :term, :createdAt)
            ON CONFLICT (seen_key) DO NOTHING
            """, nativeQuery = true)
    int remember(@Param("seenKey") String seenKey, @Param("keyId") String keyId,
                 @Param("weekStart") Instant weekStart, @Param("areaId") UUID areaId,
                 @Param("term") String term, @Param("createdAt") Instant createdAt);

    /** How many people asked for one term, in one area, in one week, under one secret. */
    long countByWeekStartAndAreaIdAndTermAndKeyId(Instant weekStart, UUID areaId, String term,
                                                  String keyId);

    /**
     * Forgets the weeks nothing will be recomputed for.
     *
     * <p>The cutoff is a week start, not an age: these rows exist to bound one week's floor, so they
     * are kept for that week and the one after — as far back as the roll-up ever goes — and no
     * longer. They outlive nothing they are not needed for.
     */
    @Modifying
    @Query("DELETE FROM SearchDemandSeen s WHERE s.weekStart < :cutoff")
    int deleteOlderThan(@Param("cutoff") Instant cutoff);
}
