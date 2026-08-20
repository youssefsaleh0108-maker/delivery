package com.delivery.product.service;

import java.math.BigDecimal;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.product.domain.DeliveryZone;
import com.delivery.product.domain.DeliveryZoneRepository;
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

    public DeliveryZoneService(DeliveryZoneRepository zones,
                               StoreDeliveryZoneRepository storeZones) {
        this.zones = zones;
        this.storeZones = storeZones;
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

    @Transactional
    public DeliveryZone create(String name, String region, int sortOrder) {
        if (zones.existsByNameIgnoreCase(name)) {
            throw new ZoneConflictException("An area called '" + name + "' already exists");
        }
        return zones.save(new DeliveryZone(name, region, sortOrder));
    }

    @Transactional
    public DeliveryZone rename(UUID id, String name, String region, int sortOrder) {
        DeliveryZone zone = require(id);
        // Allowed to keep its own name, refused if it would take somebody else's.
        zones.findByNameIgnoreCase(name)
                .filter(other -> !other.getId().equals(id))
                .ifPresent(other -> {
                    throw new ZoneConflictException("An area called '" + name + "' already exists");
                });
        zone.rename(name, region, sortOrder);
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
