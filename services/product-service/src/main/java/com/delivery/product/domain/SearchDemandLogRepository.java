package com.delivery.product.domain;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/**
 * The search log's two readers: the weekly roll-up and retention. Nothing else reads it.
 *
 * <p>There is deliberately no finder here that takes anything but a time window — no "by term", no
 * "by area and term", nothing that could be pointed at a single row. Every query is an aggregate over
 * a week, and the floor is applied in the SQL rather than after it, so a term under the floor is never
 * even materialised in this service's memory.
 */
public interface SearchDemandLogRepository extends JpaRepository<SearchDemandLog, UUID> {

    /**
     * What an area searched for in one week and nobody answered, or nobody answered near enough.
     *
     * @param kind        {@code 'NONE'} for searches that answered with no shop at all, {@code 'FAR'}
     *                    for searches that answered only with shops further than {@code farMetres}
     * @param floor       the fewest distinct searches a term needs before it may be reported
     * @param limit       how many terms an area keeps, best first
     * @return rows of {@code (area_id, term, searches)}, an area's best first
     */
    @Query(value = """
            SELECT l.area_id, l.term, COUNT(*) AS searches
            FROM search_demand_log l
            WHERE l.area_id IS NOT NULL
              AND l.searched_at >= :from
              AND l.searched_at < :until
              AND (
                   (:kind = 'NONE' AND l.result_count = 0)
                OR (:kind = 'FAR' AND l.result_count > 0
                    AND l.nearest_metres IS NOT NULL AND l.nearest_metres > :farMetres)
              )
            GROUP BY l.area_id, l.term
            HAVING COUNT(*) >= :floor
            ORDER BY l.area_id, searches DESC, l.term
            """, nativeQuery = true)
    List<Object[]> unmetRows(@Param("from") Instant from, @Param("until") Instant until,
                             @Param("kind") String kind, @Param("farMetres") int farMetres,
                             @Param("floor") long floor);

    /**
     * Forgets searches older than {@code cutoff}. Returns how many went.
     *
     * <p>The cutoff is computed in Java and bound, not written as SQL interval arithmetic, so the job
     * deletes by the same clock the rest of the service reads — the shape
     * {@code TrackingPartitionMaintenance} uses.
     */
    @Modifying
    @Query("DELETE FROM SearchDemandLog l WHERE l.searchedAt < :cutoff")
    int deleteOlderThan(@Param("cutoff") Instant cutoff);
}
