package com.delivery.product.service;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.product.domain.GeoPoint;
import com.delivery.product.domain.Store;
import com.delivery.product.domain.StoreRepository;
import com.delivery.product.service.StoreService.NearbyStoreView;

/**
 * The Services tab's "Popular near you" row (126:285): service shops near the customer, ranked by the
 * orders they delivered lately.
 *
 * <p>What keeps the row honest, each for a reason:
 * <ul>
 *   <li><strong>Shops, not offers.</strong> The row draws provider cards, and a shop is popular for its
 *       orders, whichever of its offers they were for.
 *   <li><strong>Near.</strong> Pinned within {@code delivery.catalog.services.popular-radius-metres} of
 *       the point asked about, five kilometres unless configured. A busy print shop in another city is
 *       not "near you".
 *   <li><strong>Lately.</strong> Distinct orders delivered in the last {@code popular-window-days},
 *       thirty unless configured, counted from {@code delivered_order_lines}, the projection of
 *       {@code order.delivered}: a cancelled order never counts, and a shop that was busy last year and
 *       is quiet now is not popular now.
 *   <li><strong>Real.</strong> A shop below {@code popular-min-delivered-orders} (three) distinct orders
 *       is left out rather than padded. With none above it the row is empty, and the app shows
 *       "Services near you" instead (owner default 16).
 *   <li><strong>Listed.</strong> Live service shops in open categories only, the storefront's scope.
 *   <li><strong>No count leaves.</strong> The database ranks by the counts and hands back ids, and the
 *       answer is the cards in that order. A competitor's exact order volume is not the customer's to
 *       read, and a figure on the card would invite exactly that reading.
 * </ul>
 *
 * <p>The work is split as "near me" splits it ({@link StoreRepository#findActiveIdsNear}): PostGIS
 * narrows, counts and ranks, and this class judges every row again as read and measures the distance
 * the card shows. Unlike "near me", the order that ships is the database's, because only it knows the
 * counts.
 */
@Service
public class PopularServiceShops {

    /** The most shops one request may ask for. The row shows a handful. */
    static final int MAX_SHOPS = 20;

    /**
     * The bounds "near me" holds a radius to, applied to the setting, so a configuration mistake can
     * neither empty the row for ever nor make it nationwide.
     */
    static final int MIN_RADIUS_METRES = 50;
    static final int MAX_RADIUS_METRES = 50_000;

    private final StoreRepository stores;
    private final StoreService storeService;
    private final ServiceCategories serviceCategories;
    private final Clock clock;
    private final int radiusMetres;
    private final Duration window;
    private final long minDeliveredOrders;

    public PopularServiceShops(StoreRepository stores, StoreService storeService,
                               ServiceCategories serviceCategories, Clock clock,
                               @Value("${delivery.catalog.services.popular-radius-metres:5000}")
                               int radiusMetres,
                               @Value("${delivery.catalog.services.popular-window-days:30}")
                               int windowDays,
                               @Value("${delivery.catalog.services.popular-min-delivered-orders:3}")
                               long minDeliveredOrders) {
        this.stores = stores;
        this.storeService = storeService;
        this.serviceCategories = serviceCategories;
        this.clock = clock;
        this.radiusMetres = Math.min(Math.max(radiusMetres, MIN_RADIUS_METRES), MAX_RADIUS_METRES);
        // At least a day and at least one order, so a misconfigured zero cannot call a shop popular on
        // the strength of nobody's orders.
        this.window = Duration.ofDays(Math.max(1, windowDays));
        this.minDeliveredOrders = Math.max(1, minDeliveredOrders);
    }

    /**
     * The popular service shops around {@code centre}, most delivered first, each with its distance.
     *
     * <p>A read that may show no category answers empty without asking the database. Every row is judged
     * again as read, because the ids and the rows come from two queries: a shop suspended, re-filed under
     * a closed category or unpinned in between is judged on what it is now, and one the radius slack let
     * in but the sphere puts outside the circle is dropped. The database's ranking is kept.
     *
     * @param serviceCategory one open category, or null for every open one; a closed one shows nothing
     * @param limit           clamped to between one and {@value #MAX_SHOPS}
     */
    @Transactional(readOnly = true)
    public List<NearbyStoreView> near(GeoPoint centre, Store.ServiceCategory serviceCategory, int limit) {
        Set<Store.ServiceCategory> scope = scope(serviceCategory);
        if (scope.isEmpty()) {
            return List.of();
        }
        Instant now = clock.instant();
        List<UUID> ranked = stores.findPopularServiceShopIdsNear(
                centre.latitude().doubleValue(),
                centre.longitude().doubleValue(),
                radiusMetres * StoreService.RADIUS_SLACK,
                scope.stream().map(Enum::name).sorted().collect(Collectors.joining(",")),
                now.minus(window),
                minDeliveredOrders,
                Math.min(Math.max(limit, 1), MAX_SHOPS));
        if (ranked.isEmpty()) {
            return List.of();
        }

        Map<UUID, Store> byId = new HashMap<>();
        stores.findAllById(ranked).forEach(store -> byId.put(store.getId(), store));

        List<NearbyStoreView> row = new ArrayList<>(ranked.size());
        for (UUID id : ranked) {
            Store store = byId.get(id);
            if (store == null
                    || store.getStatus() != Store.Status.ACTIVE
                    || !store.isServices()
                    || !scope.contains(store.getServiceCategory())) {
                continue;
            }
            GeoPoint location = store.location();
            if (location == null) {
                continue;
            }
            double metres = centre.distanceMetresTo(location);
            if (metres > radiusMetres) {
                continue;
            }
            row.add(new NearbyStoreView(storeService.viewAt(store, now), metres));
        }
        return row;
    }

    /** Which categories the row may show: every open one, or the one named when that one is open. */
    private Set<Store.ServiceCategory> scope(Store.ServiceCategory named) {
        Set<Store.ServiceCategory> open = serviceCategories.enabled();
        if (named == null) {
            return open;
        }
        return open.contains(named) ? Set.of(named) : Set.of();
    }
}
