package com.delivery.product.service;

import java.math.BigDecimal;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.product.domain.DeliveryZone;
import com.delivery.product.domain.DeliveryZoneRepository;
import com.delivery.product.domain.GeoPoint;
import com.delivery.product.domain.Store;
import com.delivery.product.domain.StoreDeliveryZone;
import com.delivery.product.domain.StoreDeliveryZoneRepository;

/**
 * Delivery priced by area.
 *
 * <p>The rule that makes this safe to ship: <strong>a shop that has set no areas is unchanged.</strong>
 * It charges its flat fee and serves everybody, exactly as before. Zones are opt-in per shop, so
 * turning this on cannot start refusing orders a merchant was happily taking yesterday.
 *
 * <p>Once a shop does set areas, absence becomes a decision: an area with no row is one it does not
 * deliver to, and an order there is refused at placement rather than accepted and then abandoned by
 * a rider who will not make the trip.
 */
@Service
public class DeliveryZoneService {

    private static final Logger log = LoggerFactory.getLogger(DeliveryZoneService.class);

    private final DeliveryZoneRepository zones;
    private final StoreDeliveryZoneRepository storeZones;

    /** The farthest an area's centre may lie from a shop's pin and still be around it — see {@link #around}. */
    private final int neighbourhoodCapMetres;

    public DeliveryZoneService(DeliveryZoneRepository zones,
                               StoreDeliveryZoneRepository storeZones,
                               @Value("${delivery.demand.neighbourhood-cap-metres:5000}")
                               int neighbourhoodCapMetres) {
        if (neighbourhoodCapMetres < MIN_NEIGHBOURHOOD_CAP_METRES
                || neighbourhoodCapMetres > MAX_NEIGHBOURHOOD_CAP_METRES) {
            // Refused at start-up rather than clamped: a typo in a values file should stop the
            // deploy, not quietly widen every merchant's demand map to the next town.
            throw new IllegalArgumentException("delivery.demand.neighbourhood-cap-metres must be "
                    + "between " + MIN_NEIGHBOURHOOD_CAP_METRES + " and "
                    + MAX_NEIGHBOURHOOD_CAP_METRES + ", not " + neighbourhoodCapMetres);
        }
        this.zones = zones;
        this.storeZones = storeZones;
        this.neighbourhoodCapMetres = neighbourhoodCapMetres;
    }

    // ---------------------------------------------------------------- the zone register

    @Transactional(readOnly = true)
    public List<DeliveryZone> forPicker() {
        return zones.findByActiveTrueOrderBySortOrderAscNameAsc();
    }

    @Transactional(readOnly = true)
    public List<DeliveryZone> all() {
        return zones.findAllByOrderBySortOrderAscNameAsc();
    }

    /**
     * Adds an area to the register.
     *
     * @param centre roughly the middle of the area, for the merchant demand map; null leaves it
     *               unplaced, which keeps it off that map and out of every shop's neighbourhood
     */
    @Transactional
    public DeliveryZone create(String name, String region, int sortOrder, GeoPoint centre) {
        if (zones.existsByNameIgnoreCase(name)) {
            throw new ZoneConflictException("An area called '" + name + "' already exists");
        }
        DeliveryZone zone = new DeliveryZone(name, region, sortOrder);
        zone.placeAt(centre);
        return zones.save(zone);
    }

    /**
     * Edits what the back office edits about an area: its name, region and rank, and its centre when
     * the request says something about it.
     *
     * <p>The centre is the one part not replaced wholesale. A new centre moves the area, an explicit
     * {@code clearCentre} takes it off the demand map, and saying neither keeps the centre it has.
     * Every client written before centres existed — an older portal build, a cached web bundle, a
     * back-office tab left open — sends name, region and rank alone, and a rename or a reorder from
     * one of them must not silently drop the area off every merchant's map. Pricing never reads the
     * centre, so moving or clearing it changes no shop's terms.
     *
     * @param centre      the new centre, or null to say nothing about it
     * @param clearCentre true to take the area off the map. The controller refuses it alongside a
     *                    centre; were both to arrive here, the centre would win
     */
    @Transactional
    public DeliveryZone rename(UUID id, String name, String region, int sortOrder,
                               GeoPoint centre, boolean clearCentre) {
        DeliveryZone zone = require(id);
        // Allowed to keep its own name, refused if it would take somebody else's.
        zones.findByNameIgnoreCase(name)
                .filter(other -> !other.getId().equals(id))
                .ifPresent(other -> {
                    throw new ZoneConflictException("An area called '" + name + "' already exists");
                });
        zone.rename(name, region, sortOrder);
        if (centre != null) {
            zone.placeAt(centre);
        } else if (clearCentre) {
            zone.placeAt(null);
        }
        return zone;
    }

    /**
     * Takes an area out of the picker without deleting it.
     *
     * <p>Deleting would orphan every saved address that names it. Retiring stops new orders while
     * leaving the history readable, which is the same distinction the rest of this system draws
     * between "stopped" and "never existed".
     */
    @Transactional
    public DeliveryZone retire(UUID id) {
        DeliveryZone zone = require(id);
        zone.retire();
        log.info("Area {} retired; {} shops still price for it",
                zone.getName(), storeZones.findByZoneId(id).size());
        return zone;
    }

    @Transactional
    public DeliveryZone reinstate(UUID id) {
        DeliveryZone zone = require(id);
        zone.reinstate();
        return zone;
    }

    @Transactional(readOnly = true)
    public DeliveryZone require(UUID id) {
        return zones.findById(id).orElseThrow(() -> new ZoneNotFoundException(id));
    }

    // ---------------------------------------------------------------- a shop's coverage

    @Transactional(readOnly = true)
    public List<StoreDeliveryZone> coverageOf(UUID storeId) {
        return storeZones.findByStoreId(storeId);
    }

    /**
     * The areas a shop delivers to, as a customer is shown them: its shop page's "Delivery area"
     * map lists these by name and marks the ones the back office has placed.
     *
     * <p>Exactly the areas {@link #termsFor} serves, and that is the whole contract. The map tells a
     * customer "your address is inside" or "outside" from this list, and checkout is refused or
     * accepted by termsFor; were the two ever different sets, the shop page would promise an address
     * that placement then refuses. So:
     * <ul>
     *   <li><strong>every area the shop has a price for, retired ones included.</strong> termsFor
     *       honours a coverage row whatever became of its area, and a saved address that names a
     *       retired area still orders there (retiring only takes it out of the picker);
     *   <li><strong>empty means the areas do not limit the shop</strong> — no coverage rows, so
     *       termsFor answers every area, and no area at all, with the flat fee. It never means
     *       "delivers nowhere", exactly as on {@code /coverage}.
     * </ul>
     *
     * <p>Names and centres only. What the shop charges for each area stays on the merchant's own
     * coverage screen and on the per-area quote checkout asks for; the map answers where, not how
     * much. A shop's list of areas is no secret — any signed-in caller can already ask
     * {@code /terms} whether the shop serves any area it names.
     */
    @Transactional(readOnly = true)
    public List<DeliveryZone> servedAreasOf(UUID storeId) {
        List<UUID> served = storeZones.findByStoreId(storeId).stream()
                .map(StoreDeliveryZone::getZoneId)
                .toList();
        if (served.isEmpty()) {
            return List.of();
        }
        return zones.findByIdInOrderBySortOrderAscNameAsc(served);
    }

    @Transactional
    public StoreDeliveryZone setCoverage(UUID storeId, UUID zoneId, BigDecimal fee,
                                         BigDecimal minOrder, int etaExtraMinutes) {
        require(zoneId);
        StoreDeliveryZone existing = storeZones.findByStoreIdAndZoneId(storeId, zoneId).orElse(null);
        if (existing != null) {
            existing.update(fee, minOrder, etaExtraMinutes);
            return existing;
        }
        return storeZones.save(
                new StoreDeliveryZone(storeId, zoneId, fee, minOrder, etaExtraMinutes));
    }

    /** Stops delivering to an area. The shop keeps every other area it serves. */
    @Transactional
    public void dropCoverage(UUID storeId, UUID zoneId) {
        storeZones.deleteByStoreIdAndZoneId(storeId, zoneId);
    }

    // ---------------------------------------------------------------- the areas around a shop

    /**
     * How far from a pinned shop an area still counts as around it, for a shop that has not drawn a
     * delivery circle of its own.
     *
     * <p>Five kilometres: from Hamra that reaches Mar Mikhael and Badaro, the distance a city shop's
     * riders routinely carry, and stops well short of the next town (Jounieh is sixteen). A shop that
     * HAS drawn a circle is held to its own instead, up to the neighbourhood cap.
     */
    static final int DEFAULT_NEIGHBOURHOOD_METRES = 5_000;

    /** The narrowest cap configuration may set. Under half a kilometre is a street, not a neighbourhood. */
    static final int MIN_NEIGHBOURHOOD_CAP_METRES = 500;

    /**
     * The widest cap configuration may set: the widest delivery circle the pin picker lets a merchant
     * draw. Past that, "around the shop" is a district of districts.
     */
    static final int MAX_NEIGHBOURHOOD_CAP_METRES = 15_000;

    /**
     * The areas around a shop — the only areas its Demand Radar may show.
     *
     * <p>An active area is around a shop only when all of these hold:
     * <ul>
     *   <li>the shop has a pin and the area has a centre. Nothing can be measured from a shop whose
     *       place is unknown, or to an area the back office has not placed;
     *   <li>the centre lies within the neighbourhood cap of the pin: five kilometres unless
     *       {@code delivery.demand.neighbourhood-cap-metres} says otherwise; and
     *   <li>the shop delivers there (a coverage row), or the centre lies within the shop's own
     *       delivery radius — {@link #DEFAULT_NEIGHBOURHOOD_METRES} when it has drawn none.
     * </ul>
     *
     * <p>The cap is what keeps "around" the platform's decision rather than the merchant's. Both other
     * inputs are the merchant's to set: a coverage row can be added for any area on the platform, and
     * a delivery radius can be drawn fifty kilometres wide. Without the cap, a shop pricing every area
     * would read demand platform-wide.
     *
     * <p>A shop with no pin, or no placed area near its pin, gets an empty neighbourhood. The honest
     * answer is "we don't know what is around you yet", not a guess and not the whole city. A retired
     * area is around nobody, even where a shop still holds a price for it. Whether the shop is live is
     * the endpoint's rule, not this one's.
     *
     * <p>The region is the one most of these areas name, for the map's city label. A tie goes to the
     * region that appears first in the picker's order, so the label cannot flicker between polls.
     */
    @Transactional(readOnly = true)
    public Neighbourhood around(Store store) {
        GeoPoint pin = store.location();
        if (pin == null) {
            return new Neighbourhood(null, null, List.of());
        }
        Set<UUID> covered = storeZones.findByStoreId(store.getId()).stream()
                .map(StoreDeliveryZone::getZoneId)
                .collect(Collectors.toSet());
        int reach = Math.min(store.getDeliveryRadiusMetres() != null
                        ? store.getDeliveryRadiusMetres()
                        : DEFAULT_NEIGHBOURHOOD_METRES,
                neighbourhoodCapMetres);

        List<DeliveryZone> near = zones.findByActiveTrueOrderBySortOrderAscNameAsc().stream()
                .filter(zone -> {
                    GeoPoint centre = zone.centre();
                    if (centre == null) {
                        return false;
                    }
                    double metres = pin.distanceMetresTo(centre);
                    return metres <= neighbourhoodCapMetres
                            && (metres <= reach || covered.contains(zone.getId()));
                })
                .toList();

        return new Neighbourhood(regionOf(near), reach, near);
    }

    private static String regionOf(List<DeliveryZone> areas) {
        Map<String, Integer> counts = new LinkedHashMap<>();
        for (DeliveryZone area : areas) {
            if (area.getRegion() != null && !area.getRegion().isBlank()) {
                counts.merge(area.getRegion().trim(), 1, Integer::sum);
            }
        }
        String region = null;
        int most = 0;
        for (Map.Entry<String, Integer> entry : counts.entrySet()) {
            // Strictly greater: the first region to reach a count keeps it.
            if (entry.getValue() > most) {
                region = entry.getKey();
                most = entry.getValue();
            }
        }
        return region;
    }

    /**
     * A shop's neighbourhood.
     *
     * @param region       the region most of the areas name, or null when none names one
     * @param radiusMetres how far from the pin an area counts as near without a coverage row: the
     *                     shop's own radius or the default, never more than the cap. Null for a shop
     *                     with no pin, which has no neighbourhood
     * @param zones        active, placed areas within the cap of the pin, in the picker's order
     */
    public record Neighbourhood(String region, Integer radiusMetres, List<DeliveryZone> zones) {
    }

    // ---------------------------------------------------------------- the question that matters

    /**
     * What this shop charges to reach this area, if it goes there at all.
     *
     * <p>Three outcomes, and they are genuinely different:
     * <ul>
     *   <li>the shop prices by area and serves this one — its per-area terms;
     *   <li>the shop prices by area and does <em>not</em> serve this one — refused;
     *   <li>the shop does not price by area at all — its flat fee, serving everywhere.
     * </ul>
     *
     * <p>A null zone lands in the third case too. An order placed before the customer had picked an
     * area, or by a client that predates areas, still goes through at the flat fee rather than
     * failing — the same tolerance the store terms already extend to an order with no store.
     */
    @Transactional(readOnly = true)
    public Terms termsFor(Store store, UUID zoneId) {
        boolean pricesByArea = storeZones.existsByStoreId(store.getId());
        if (!pricesByArea || zoneId == null) {
            return Terms.flat(store);
        }

        return storeZones.findByStoreIdAndZoneId(store.getId(), zoneId)
                .map(z -> new Terms(
                        true,
                        z.getDeliveryFee(),
                        z.getMinOrder() == null ? store.getMinOrder() : z.getMinOrder(),
                        store.getEtaMinMinutes() + z.getEtaExtraMinutes(),
                        store.getEtaMaxMinutes() + z.getEtaExtraMinutes()))
                .orElseGet(() -> Terms.notServed(store));
    }

    /**
     * What a shop charges somewhere, and whether it goes there.
     *
     * @param served false when the shop prices by area and this area is not one of them
     */
    public record Terms(boolean served, BigDecimal deliveryFee, BigDecimal minOrder,
                        int etaMinMinutes, int etaMaxMinutes) {

        static Terms flat(Store store) {
            return new Terms(true, store.getDeliveryFee(), store.getMinOrder(),
                    store.getEtaMinMinutes(), store.getEtaMaxMinutes());
        }

        static Terms notServed(Store store) {
            return new Terms(false, store.getDeliveryFee(), store.getMinOrder(),
                    store.getEtaMinMinutes(), store.getEtaMaxMinutes());
        }
    }

    public static class ZoneNotFoundException extends RuntimeException {
        public ZoneNotFoundException(UUID id) {
            super("No delivery area " + id);
        }
    }

    public static class ZoneConflictException extends RuntimeException {
        public ZoneConflictException(String message) {
            super(message);
        }
    }
}
