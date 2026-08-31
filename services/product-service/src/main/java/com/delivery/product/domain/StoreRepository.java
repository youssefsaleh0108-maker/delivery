package com.delivery.product.domain;

import java.math.BigDecimal;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface StoreRepository extends JpaRepository<Store, UUID> {

    Optional<Store> findBySlug(String slug);

    Optional<Store> findByIdAndMerchantId(UUID id, String merchantId);

    List<Store> findByMerchantIdOrderByCreatedAtDesc(String merchantId);

    Page<Store> findByMerchantIdOrderByCreatedAtDesc(String merchantId, Pageable pageable);

    boolean existsByMerchantId(String merchantId);

    /**
     * The storefront query.
     *
     * <p>Every filter is optional and expressed as "the parameter is null, or it matches". One query
     * and one plan, rather than a Specification tree. It is also why {@code search} arrives as an
     * already-built LIKE pattern rather than a raw term: a null pattern would make the comparison
     * null rather than true, and silently return nothing.
     *
     * <p>Prefer {@link #findStorefront} — the status is a parameter here only because a nested enum
     * constant is awkward to write as a JPQL literal, not because callers should choose it.
     */
    @Query("""
            SELECT s FROM Store s
            WHERE s.status = :status
              AND (:vertical IS NULL OR s.vertical = :vertical)
              AND (LOWER(s.name) LIKE :search)
              AND (:maxDeliveryFee IS NULL OR s.deliveryFee <= :maxDeliveryFee)
              AND (:maxEtaMinutes IS NULL OR s.etaMaxMinutes <= :maxEtaMinutes)
              AND (:minRating IS NULL OR s.rating >= :minRating)
              AND (:neighborhood IS NULL OR s.neighborhood = :neighborhood)
            """)
    Page<Store> findStorefrontWithStatus(@Param("status") Store.Status status,
                                         @Param("vertical") Store.Vertical vertical,
                                         @Param("search") String search,
                                         @Param("maxDeliveryFee") BigDecimal maxDeliveryFee,
                                         @Param("maxEtaMinutes") Integer maxEtaMinutes,
                                         @Param("minRating") BigDecimal minRating,
                                         @Param("neighborhood") String neighborhood,
                                         Pageable pageable);

    /**
     * The district chips, from the shops that actually declared one. Live shops only, so a draft
     * in a district nobody serves cannot conjure an empty chip.
     */
    @Query("""
            SELECT DISTINCT s.neighborhood FROM Store s
            WHERE s.status = com.delivery.product.domain.Store$Status.ACTIVE
              AND s.neighborhood IS NOT NULL
            ORDER BY s.neighborhood
            """)
    List<String> distinctNeighborhoods();

    /**
     * Live stores only. The ACTIVE filter is pinned here rather than left to callers: a DRAFT or
     * SUSPENDED store reaching a customer's screen is the one failure this query must not allow,
     * and an invariant that every call site has to remember is not an invariant.
     */
    default Page<Store> findStorefront(Store.Vertical vertical, String search,
                                       BigDecimal maxDeliveryFee, Integer maxEtaMinutes,
                                       BigDecimal minRating, String neighborhood,
                                       Pageable pageable) {
        return findStorefrontWithStatus(Store.Status.ACTIVE, vertical, search,
                maxDeliveryFee, maxEtaMinutes, minRating, neighborhood, pageable);
    }

    @Query("""
            SELECT s FROM Store s
            JOIN StoreFavorite f ON f.id.storeId = s.id
            WHERE f.id.userId = :userId
              AND s.status = :status
            ORDER BY f.createdAt DESC
            """)
    Page<Store> findFavoritesOfWithStatus(@Param("userId") String userId,
                                          @Param("status") Store.Status status,
                                          Pageable pageable);

    /** A customer's starred stores, most recently starred first. The home screen's top row. */
    default Page<Store> findFavoritesOf(String userId, Pageable pageable) {
        return findFavoritesOfWithStatus(userId, Store.Status.ACTIVE, pageable);
    }

    /**
     * Live stores with a pin inside a radius, nearest first, capped.
     *
     * <p><strong>Why PostGIS.</strong> The extension is enabled in this database — it is created by
     * {@code infra/postgres/init}, the image is {@code postgis/postgis:17-3.5}, and the orders and
     * tracking schemas already hold geography columns — and V20 asserts it rather than assuming it.
     * The alternative the brief allows, a bounding box in SQL plus haversine in Java, was rejected
     * for one reason: a {@code BETWEEN} on two {@code numeric} columns cannot use a single index
     * usefully, so it degrades to a scan of every live store and then throws most of them away. A
     * GiST index on a geography column answers {@code ST_DWithin} directly. The bounding box is what
     * you write when you have no spatial index; here there is one.
     *
     * <p><strong>Why this returns ids and not stores, and no distance.</strong> The database narrows
     * and caps; the service computes the number the customer actually sees, with
     * {@link GeoPoint#distanceMetresTo}. Two reasons:
     *
     * <ul>
     *   <li>This module's tests run without a database, so a distance and an ordering produced by
     *       SQL are a distance and an ordering nothing in the build can check. Owning both in Java
     *       means "the nearest of these three shops is listed first" is an assertion rather than a
     *       hope.
     *   <li>The candidate set is bounded twice over — by the radius and by {@code maxCandidates} —
     *       so sorting it in memory is tens of rows. {@link com.delivery.product.service.StoreService}
     *       already cuts offer lists this way for the same reason.
     * </ul>
     *
     * <p>{@code ST_Distance} on the spheroid and the haversine sphere differ by around 0.3%, so the
     * two orderings can only disagree between shops that are near enough to equidistant for the
     * difference not to be visible. Where they do, the Java answer wins — and because the same
     * number drives both the order and the label, the list can never contradict itself.
     *
     * <p>The radius passed here should carry a little slack over the one the caller means, so the
     * spheroid/sphere gap cannot drop a shop sitting exactly on the boundary before Java has had a
     * chance to judge it. {@code StoreService} adds it.
     *
     * <p>Native rather than JPQL because {@code ST_DWithin} has no JPQL spelling, and every PostGIS
     * name is {@code public.}-qualified because the extension lives in {@code public} while this
     * service's connection pins the search path to {@code product}. That qualification is also why
     * the ordering is a call to {@code ST_Distance} rather than the {@code <->} KNN operator: an
     * operator would need the {@code OPERATOR(public.<->)} spelling to resolve at all, and the
     * ordering here only exists to make {@code LIMIT} pick the right candidates — the index has
     * already done the narrowing in the {@code WHERE}, and Java does the ordering that ships.
     */
    @Query(value = """
            SELECT s.id
              FROM stores s
             WHERE s.status = 'ACTIVE'
               AND s.location IS NOT NULL
               AND public.ST_DWithin(
                       s.location,
                       public.ST_SetSRID(public.ST_MakePoint(:longitude, :latitude), 4326)::public.geography,
                       :radiusMetres)
             ORDER BY public.ST_Distance(
                       s.location,
                       public.ST_SetSRID(public.ST_MakePoint(:longitude, :latitude), 4326)::public.geography)
             LIMIT :maxCandidates
            """, nativeQuery = true)
    /**
     * Whether this shop's delivery circle covers the point. Three honest answers folded into
     * one: no radius set → yes (zones alone decide, the old behaviour); a radius but no pin →
     * yes (a circle without a centre binds nothing — the service refuses to create that state,
     * but data outlives rules); otherwise the spheroid says.
     */
    @Query(value = """
            SELECT CASE
                     WHEN s.delivery_radius_metres IS NULL THEN true
                     WHEN s.location IS NULL THEN true
                     ELSE public.ST_DWithin(
                            s.location,
                            public.ST_SetSRID(public.ST_MakePoint(:longitude, :latitude), 4326)::public.geography,
                            s.delivery_radius_metres)
                   END
              FROM stores s
             WHERE s.id = :id
            """, nativeQuery = true)
    Boolean deliversTo(@Param("id") UUID id,
                       @Param("latitude") double latitude,
                       @Param("longitude") double longitude);

    List<UUID> findActiveIdsNear(@Param("latitude") double latitude,
                                 @Param("longitude") double longitude,
                                 @Param("radiusMetres") double radiusMetres,
                                 @Param("maxCandidates") int maxCandidates);
}
