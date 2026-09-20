package com.delivery.product.domain;

import java.time.Instant;
import java.util.Collection;
import java.util.List;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/** The weekly roll-up: written by the job, read by one merchant's own areas. */
public interface SearchDemandWeekRepository extends JpaRepository<SearchDemandWeek, UUID> {

    /**
     * One week's terms for the areas a shop is allowed to see, best first.
     *
     * <p>The area ids come from the shop's own neighbourhood ({@code DeliveryZoneService.around}) and
     * never from the request, which is what stops a merchant reading the city.
     */
    List<SearchDemandWeek> findByWeekStartInAndAreaIdInOrderByAreaIdAscKindAscRankAsc(
            Collection<Instant> weekStarts, Collection<UUID> areaIds);

    /**
     * Which of {@code ids} name something the merchant's own shops already sell.
     *
     * <p>Matched by the term's folded words against {@code products.search_name} (V37), the same fold
     * the search itself ran on, so "nescafe" finds "Nescafé Classic 200g". One query rather than one
     * per term: the terms are already rows in this database, so they can be joined against rather
     * than shipped back and forth.
     */
    @Query(value = """
            SELECT w.id FROM search_demand_week w
            WHERE w.id IN (:ids)
              AND EXISTS (
                SELECT 1 FROM products p
                WHERE p.store_id IN (:storeIds)
                  AND p.status = 'ACTIVE'
                  AND strpos(p.search_name, ' ' || w.term) > 0)
            """, nativeQuery = true)
    List<UUID> alreadySold(@Param("ids") Collection<UUID> ids,
                           @Param("storeIds") Collection<UUID> storeIds);

    /** Everything computed for one week, so a re-run replaces it rather than doubling it. */
    @Modifying
    @Query("DELETE FROM SearchDemandWeek w WHERE w.weekStart = :weekStart")
    int deleteWeek(@Param("weekStart") Instant weekStart);

    /** Weeks the roll-up no longer keeps. */
    @Modifying
    @Query("DELETE FROM SearchDemandWeek w WHERE w.weekStart < :cutoff")
    int deleteOlderThan(@Param("cutoff") Instant cutoff);
}
