package com.delivery.product.service;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicReference;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import com.delivery.product.domain.DeliveryZone;
import com.delivery.product.domain.DeliveryZoneRepository;
import com.delivery.product.domain.GeoPoint;

/**
 * Turns a point into a neighbourhood, and forgets the point.
 *
 * <p>This is the whole of the search log's location model. A customer's pin arrives with their
 * search, is compared against the centres of the delivery areas the back office has placed, and what
 * is kept is the id of the nearest one — "Hamra", a name thousands of people share — or nothing.
 * The coordinates are never written anywhere.
 *
 * <p><strong>Nearest, within a cap.</strong> Areas are centres, not polygons ({@link DeliveryZone}),
 * so "the area a pin falls in" can only mean the nearest placed centre. Beyond
 * {@code delivery.demand.search-log.area-cap-metres} a pin belongs to no area at all rather than to
 * the nearest one: a search from a village an hour away is not a signal about the nearest town, and
 * snapping it there would put a handful of searches — a handful of people — under one name. A pin
 * with no area is still logged, still counted for retention, and never reported to anybody.
 *
 * <p>The same rule places a shop, which is how the log knows whether an answering shop was in the
 * searcher's own area: both sides are read through {@link #areaOf}, so the comparison is between two
 * neighbourhoods rather than between a person and a shop.
 *
 * <p>The register is read once and cached for {@value #CACHE_FOR_SECONDS} seconds. Areas change when
 * the back office edits them, which is rarely; every search would otherwise read the whole table on a
 * background thread. A stale cache can only mis-file a search into the neighbouring area for a
 * minute, which is a coarse answer being slightly coarser.
 */
@Component
public class CoarseAreas {

    /** How long a read of the area register is reused. */
    static final int CACHE_FOR_SECONDS = 60;

    /** The narrowest and widest cap configuration may set, on {@code DeliveryZoneService}'s scale. */
    static final int MIN_CAP_METRES = 500;
    static final int MAX_CAP_METRES = 15_000;

    private final DeliveryZoneRepository zones;
    private final Clock clock;
    private final int capMetres;

    /** The placed areas as last read, and when. Replaced whole, never mutated. */
    private final AtomicReference<Snapshot> snapshot = new AtomicReference<>(Snapshot.EMPTY);

    public CoarseAreas(DeliveryZoneRepository zones, Clock clock,
                       @Value("${delivery.demand.search-log.area-cap-metres:3000}") int capMetres) {
        if (capMetres < MIN_CAP_METRES || capMetres > MAX_CAP_METRES) {
            // Refused at start-up rather than clamped, as DeliveryZoneService refuses its own cap: a
            // typo that widened this would file distant searches under a neighbourhood they are not
            // in, and nothing downstream could tell.
            throw new IllegalArgumentException("delivery.demand.search-log.area-cap-metres must be "
                    + "between " + MIN_CAP_METRES + " and " + MAX_CAP_METRES + ", not " + capMetres);
        }
        this.zones = zones;
        this.clock = clock;
        this.capMetres = capMetres;
    }

    /**
     * The area {@code point} belongs to: the nearest active, placed area within the cap.
     *
     * <p>No transaction of its own: the register is read through a Spring Data repository, which
     * opens one for the read, and every other call is served from the cache. That matters because
     * this runs on the recorder's background thread, where an open transaction would hold a pooled
     * connection that a storefront request is waiting for.
     *
     * @return empty for a null point, and for a point no placed area is near enough to name
     */
    public Optional<UUID> areaOf(GeoPoint point) {
        if (point == null) {
            return Optional.empty();
        }
        UUID nearest = null;
        double best = Double.MAX_VALUE;
        for (Placed area : placed()) {
            double metres = point.distanceMetresTo(area.centre());
            if (metres <= capMetres && metres < best) {
                best = metres;
                nearest = area.id();
            }
        }
        return Optional.ofNullable(nearest);
    }

    /** Whether any of {@code points} belongs to {@code areaId}. False for a null area. */
    public boolean anyIn(List<GeoPoint> points, UUID areaId) {
        if (areaId == null || points == null) {
            return false;
        }
        for (GeoPoint point : points) {
            if (areaOf(point).filter(areaId::equals).isPresent()) {
                return true;
            }
        }
        return false;
    }

    /** Forgets the cached register, so the next read is fresh. For tests and for an area edit. */
    public void forget() {
        snapshot.set(Snapshot.EMPTY);
    }

    private List<Placed> placed() {
        Instant now = clock.instant();
        Snapshot cached = snapshot.get();
        if (cached.readAt().plusSeconds(CACHE_FOR_SECONDS).isAfter(now)) {
            return cached.areas();
        }
        List<Placed> fresh = new ArrayList<>();
        for (DeliveryZone zone : zones.findByActiveTrueOrderBySortOrderAscNameAsc()) {
            GeoPoint centre = zone.centre();
            if (centre != null) {
                fresh.add(new Placed(zone.getId(), centre));
            }
        }
        List<Placed> immutable = List.copyOf(fresh);
        // Whichever thread wins, both hold a list read within the same moment.
        snapshot.set(new Snapshot(now, immutable));
        return immutable;
    }

    private record Placed(UUID id, GeoPoint centre) {
    }

    private record Snapshot(Instant readAt, List<Placed> areas) {

        /** Epoch, so the first call reads the register. */
        static final Snapshot EMPTY = new Snapshot(Instant.EPOCH, List.of());
    }

    /** How long a read of the area register is reused. */
    public Duration cacheFor() {
        return Duration.ofSeconds(CACHE_FOR_SECONDS);
    }

    /** How far from a placed centre a point may be and still belong to it. */
    public int capMetres() {
        return capMetres;
    }
}
