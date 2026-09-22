package com.delivery.product.domain;

import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface MenuViewDayRepository extends JpaRepository<MenuViewDay, MenuViewDay.Key> {

    /**
     * Add {@code views} into one bucket, creating it if this is the day's first.
     *
     * <p>Native, and it has to be: the write is {@code +=} on a row that may not exist, which is
     * one statement in Postgres and a read-modify-write race in JPA. Two pods flushing the same
     * shop's morning at the same moment both land, because {@code EXCLUDED.views} is added to
     * whatever is already there rather than replacing it.
     *
     * <p>This is the only write path to the table. Nothing inserts a row per view, so there is no
     * second shape a reader of the schema has to account for.
     */
    @Modifying
    @Query(value = """
            INSERT INTO menu_view_day (store_id, viewed_on, day_part, source, views)
            VALUES (:storeId, :viewedOn, :dayPart, :source, :views)
            ON CONFLICT (store_id, viewed_on, day_part, source)
            DO UPDATE SET views = menu_view_day.views + EXCLUDED.views
            """, nativeQuery = true)
    void add(@Param("storeId") UUID storeId,
             @Param("viewedOn") LocalDate viewedOn,
             @Param("dayPart") String dayPart,
             @Param("source") String source,
             @Param("views") int views);

    /**
     * One shop's counters over a window, oldest first.
     *
     * <p>Scoped to a store by the caller, which has already decided this shop may be looked at.
     * The window is inclusive at both ends because both ends are days the merchant picked.
     */
    List<MenuViewDay> findByStoreIdAndViewedOnBetweenOrderByViewedOnAsc(UUID storeId,
                                                                        LocalDate from,
                                                                        LocalDate to);

    /** Retention: counters older than the cutoff. */
    @Modifying
    @Query("DELETE FROM MenuViewDay v WHERE v.viewedOn < :cutoff")
    int deleteOlderThan(@Param("cutoff") LocalDate cutoff);
}
