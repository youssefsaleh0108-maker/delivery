package com.delivery.product.domain;

import java.math.BigDecimal;
import java.time.Instant;
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
     *
     * <p><strong>Never a service shop, whatever the parameters say.</strong> This is the goods
     * storefront: Home, its search, the shop lists and the category counts. Every installed app asks
     * it for "all verticals" by sending none, and reads an unknown vertical as RESTAURANT, so a print
     * shop listed here would be drawn as a restaurant. The exclusion is a literal rather than a
     * default a caller could switch off. Service shops are listed by
     * {@link #findServicesStorefront}, which exists so that this query never has to.
     */
    @Query("""
            SELECT s FROM Store s
            WHERE s.status = :status
              AND s.vertical <> com.delivery.product.domain.Store$Vertical.SERVICES
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
     * The Services tab's list: live service shops in the given categories, with the storefront's
     * other filters.
     *
     * <p>Its own query rather than a switch inside {@link #findStorefrontWithStatus}, so that one can
     * refuse service shops unconditionally. {@code categories} is never empty: {@code StoreService}
     * answers an empty page itself when no category may be shown, rather than bind an empty
     * {@code IN} list, which databases and Hibernate versions do not agree how to render.
     *
     * @param categories the open categories the read may show — the one it named, or all of them
     */
    @Query("""
            SELECT s FROM Store s
            WHERE s.status = com.delivery.product.domain.Store$Status.ACTIVE
              AND s.vertical = com.delivery.product.domain.Store$Vertical.SERVICES
              AND s.serviceCategory IN :categories
              AND (LOWER(s.name) LIKE :search)
              AND (:maxDeliveryFee IS NULL OR s.deliveryFee <= :maxDeliveryFee)
              AND (:maxEtaMinutes IS NULL OR s.etaMaxMinutes <= :maxEtaMinutes)
              AND (:minRating IS NULL OR s.rating >= :minRating)
              AND (:neighborhood IS NULL OR s.neighborhood = :neighborhood)
            """)
    Page<Store> findServicesStorefront(
            @Param("categories") java.util.Collection<Store.ServiceCategory> categories,
            @Param("search") String search,
            @Param("maxDeliveryFee") BigDecimal maxDeliveryFee,
            @Param("maxEtaMinutes") Integer maxEtaMinutes,
            @Param("minRating") BigDecimal minRating,
            @Param("neighborhood") String neighborhood,
            Pageable pageable);

    /**
     * The district chips, from the shops that actually declared one. Live shops only, so a draft
     * in a district nobody serves cannot conjure an empty chip.
     *
     * <p>Goods shops only. The chips narrow the goods browse, so a district where only a tailor
     * trades would be a chip that opens onto nothing — or, on an app built before services existed,
     * onto a tailor drawn as a restaurant.
     */
    @Query("""
            SELECT DISTINCT s.neighborhood FROM Store s
            WHERE s.status = com.delivery.product.domain.Store$Status.ACTIVE
              AND s.vertical <> com.delivery.product.domain.Store$Vertical.SERVICES
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

    /**
     * A customer's starred stores in one status, most recently starred first.
     *
     * <p>Prefer {@link #findFavoritesOf}, for the same reason as {@link #findStorefront}.
     *
     * <p><strong>Never a service shop, whatever the parameters say.</strong> This is Home's "Your
     * favourites" rail, and service shops are never on Home (owner default 14). Every installed app
     * reads an unknown vertical as RESTAURANT, so a print shop starred here would be drawn on Home as
     * a restaurant; and a shop in a category that has since closed would be shown, which a closed
     * category never is (owner default 1). The star itself is kept. This decides only where it is
     * listed, so a later Services read can list it without the customer starring it again.
     */
    @Query("""
            SELECT s FROM Store s
            JOIN StoreFavorite f ON f.id.storeId = s.id
            WHERE f.id.userId = :userId
              AND s.status = :status
              AND s.vertical <> com.delivery.product.domain.Store$Vertical.SERVICES
            ORDER BY f.createdAt DESC
            """)
    Page<Store> findFavoritesOfWithStatus(@Param("userId") String userId,
                                          @Param("status") Store.Status status,
                                          Pageable pageable);

    /**
     * A customer's starred goods shops, most recently starred first. The home screen's top row; see
     * {@link #findFavoritesOfWithStatus} for why a service shop is never in it.
     */
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
     *
     * <p><strong>The neighbourhood browse's filters are in the {@code WHERE} too, ahead of the
     * {@code LIMIT}.</strong> Applied only afterwards, in Java, they narrowed the nearest
     * {@code maxCandidates} shops instead of the radius: a matching shop just past the ceiling went
     * missing and the answer said nothing matched. Each predicate here mirrors
     * {@code StoreService.NearbyFilters#admits}, which still judges the rows as read and decides.
     * "Open now" is not here at all: availability is walked out of opening hours in Java, and a SQL
     * twin of that walk would be a second answer to "is it open", free to disagree with the card.
     *
     * <p>No parameter is ever bound null. An untyped null in native SQL is one PostgreSQL cannot
     * infer a type for, and how a driver binds it varies — so each optional filter arrives as a value
     * with a switch ({@code ''} meaning "no status" or "no district", a boolean for the others), and
     * every parameter is {@code CAST} to its column's type so the planner never has to guess.
     *
     * @param powerStatus        {@code ''} for no power filter, else a {@link Store.PowerStatus} name
     * @param powerDeclaredSince the oldest declaration that still counts as now; used only with a
     *                           power filter
     * @param neighborhood       {@code ''} for no district filter, else the exact district
     * @param newOnly            whether {@code listedSince} applies
     * @param listedSince        the earliest first listing that counts as new
     * @param vertical           {@code ''} for every goods vertical and no service shop, else one
     *                           {@link Store.Vertical} name — see {@code StoreService.ShopScope}
     * @param serviceCategories  the open service categories a SERVICES read may show, comma-separated;
     *                           {@code ''} shows no service shop. A string rather than a list so an
     *                           empty set is still a typed, non-null value, and so no service shop can
     *                           slip through a list the driver bound oddly.
     * @param maxCandidates      the {@code LIMIT}; the service asks for one more than it will use
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
               AND (CAST(:powerStatus AS varchar) = ''
                    OR (s.power_status = CAST(:powerStatus AS varchar)
                        AND s.power_updated_at >= CAST(:powerDeclaredSince AS timestamptz)))
               AND (CAST(:neighborhood AS varchar) = ''
                    OR s.neighborhood = CAST(:neighborhood AS varchar))
               AND (NOT CAST(:verifiedLocalOnly AS boolean) OR s.verified_local)
               AND (NOT CAST(:newOnly AS boolean)
                    OR s.published_at >= CAST(:listedSince AS timestamptz))
               AND (CASE WHEN CAST(:vertical AS varchar) = ''
                         THEN s.vertical <> 'SERVICES'
                         ELSE s.vertical = CAST(:vertical AS varchar)
                    END)
               AND (s.vertical <> 'SERVICES'
                    OR s.service_category = ANY (
                           string_to_array(CAST(:serviceCategories AS varchar), ',')))
             ORDER BY public.ST_Distance(
                       s.location,
                       public.ST_SetSRID(public.ST_MakePoint(:longitude, :latitude), 4326)::public.geography)
             LIMIT :maxCandidates
            """, nativeQuery = true)
    List<UUID> findActiveIdsNear(@Param("latitude") double latitude,
                                 @Param("longitude") double longitude,
                                 @Param("radiusMetres") double radiusMetres,
                                 @Param("powerStatus") String powerStatus,
                                 @Param("powerDeclaredSince") Instant powerDeclaredSince,
                                 @Param("neighborhood") String neighborhood,
                                 @Param("verifiedLocalOnly") boolean verifiedLocalOnly,
                                 @Param("newOnly") boolean newOnly,
                                 @Param("listedSince") Instant listedSince,
                                 @Param("vertical") String vertical,
                                 @Param("serviceCategories") String serviceCategories,
                                 @Param("maxCandidates") int maxCandidates);

    /**
     * The Services tab's "Popular near you" row: live service shops pinned inside a radius, in open
     * categories, ranked by the distinct orders they delivered since a moment, most first.
     *
     * <p>Only ids leave the database, in rank order, and no count. The counts rank the row and stay
     * here: a competitor's order volume is not something a customer's app should be handed, so
     * {@code PopularServiceShops} is given nothing it could pass on.
     *
     * <p>Each clause, and why:
     * <ul>
     *   <li>{@code COUNT(DISTINCT l.order_id)}: orders, not lines or units, so one order of three
     *       offers, or of 5,000 flyers, is one order.
     *   <li>{@code l.delivered_at >= :deliveredSince}: recent orders only. The table is the projection
     *       of {@code order.delivered}, so an order placed and then cancelled never counts at all.
     *   <li>{@code HAVING}: below the floor a shop is left out, never padded.
     *   <li>ACTIVE, SERVICES, an open category and a pin inside the radius: the scope and circle "near
     *       me" uses ({@link #findActiveIdsNear}), ahead of the {@code LIMIT}, so a busy shop across the
     *       country cannot take a place a nearby one should have had.
     *   <li>A tie goes to the better rated shop, unrated last, then to the id, so the row does not
     *       reshuffle on every refresh.
     * </ul>
     *
     * <p>Native for {@code ST_DWithin}, with {@link #findActiveIdsNear}'s {@code public.}
     * qualification, typed casts and never-null parameters, and its slack: the caller widens the radius
     * a little and judges every row again on the sphere, as the card measures it.
     *
     * @param serviceCategories the open categories the row may show, comma-separated; never empty
     * @param deliveredSince    the oldest delivery that still counts
     * @param maxShops          the {@code LIMIT}
     */
    @Query(value = """
            SELECT s.id
              FROM stores s
              JOIN delivered_order_lines l ON l.store_id = s.id
             WHERE s.status = 'ACTIVE'
               AND s.vertical = 'SERVICES'
               AND s.service_category = ANY (
                       string_to_array(CAST(:serviceCategories AS varchar), ','))
               AND s.location IS NOT NULL
               AND public.ST_DWithin(
                       s.location,
                       public.ST_SetSRID(public.ST_MakePoint(:longitude, :latitude), 4326)::public.geography,
                       :radiusMetres)
               AND l.delivered_at >= CAST(:deliveredSince AS timestamptz)
             GROUP BY s.id, s.rating
            HAVING COUNT(DISTINCT l.order_id) >= :minDeliveredOrders
             ORDER BY COUNT(DISTINCT l.order_id) DESC, s.rating DESC NULLS LAST, s.id
             LIMIT :maxShops
            """, nativeQuery = true)
    List<UUID> findPopularServiceShopIdsNear(@Param("latitude") double latitude,
                                             @Param("longitude") double longitude,
                                             @Param("radiusMetres") double radiusMetres,
                                             @Param("serviceCategories") String serviceCategories,
                                             @Param("deliveredSince") Instant deliveredSince,
                                             @Param("minDeliveredOrders") long minDeliveredOrders,
                                             @Param("maxShops") int maxShops);

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
}
