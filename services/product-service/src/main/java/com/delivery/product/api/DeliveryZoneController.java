package com.delivery.product.api;

import java.math.BigDecimal;
import java.util.List;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.PositiveOrZero;
import jakarta.validation.constraints.Size;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.delivery.product.api.dto.DeliveryZoneDtos.ZoneResponse;
import com.delivery.product.domain.DeliveryZone;
import com.delivery.product.domain.GeoPoint;
import com.delivery.product.domain.Store;
import com.delivery.product.domain.StoreDeliveryZone;
import com.delivery.product.service.DeliveryZoneService;
import com.delivery.product.service.StoreService;
import com.delivery.platform.security.CurrentUser;

/**
 * Delivery areas: the platform's list of them, and what each shop charges to reach each one.
 *
 * <p>Three audiences. The Backoffice owns the list of areas, because two shops calling the same
 * neighbourhood by different names would make "do you deliver to me" unanswerable. A merchant sets
 * their own coverage and prices. A customer only reads the list, to say where they are.
 */
@RestController
@RequestMapping("/api/delivery-zones")
public class DeliveryZoneController {

    private final DeliveryZoneService zones;
    private final StoreService stores;

    public DeliveryZoneController(DeliveryZoneService zones, StoreService stores) {
        this.zones = zones;
        this.stores = stores;
    }

    // ---------------------------------------------------------------- everybody

    /**
     * The areas a customer can pick from.
     *
     * <p>Open to any signed-in user: it is a list of neighbourhood names, and a customer has to see
     * it before they have an address at all. The optional centres ride along; a neighbourhood's
     * middle is public geography, not anybody's data.
     */
    @GetMapping
    public List<ZoneResponse> picker() {
        return zones.forPicker().stream().map(ZoneResponse::of).toList();
    }

    // ---------------------------------------------------------------- backoffice

    /** Including retired ones, which the picker hides. */
    @GetMapping("/all")
    @PreAuthorize("hasRole('BACKOFFICE')")
    public List<ZoneResponse> all() {
        return zones.all().stream().map(ZoneResponse::of).toList();
    }

    @PostMapping
    @PreAuthorize("hasRole('BACKOFFICE')")
    public ResponseEntity<ZoneResponse> create(@Valid @RequestBody ZoneRequest request) {
        DeliveryZone created = zones.create(request.name(), request.region(), request.sortOrder(),
                request.centre());
        return ResponseEntity.status(HttpStatus.CREATED).body(ZoneResponse.of(created));
    }

    /**
     * Edits an area's name, region and rank, and its centre when the request says something about
     * it: a request with no centre keeps the one the area has, and {@code "clearCentre": true} takes
     * it off the demand map. {@link DeliveryZoneService#rename} says why the centre is not replaced
     * wholesale like the rest.
     */
    @PutMapping("/{id}")
    @PreAuthorize("hasRole('BACKOFFICE')")
    public ZoneResponse rename(@PathVariable UUID id, @Valid @RequestBody ZoneRequest request) {
        return ZoneResponse.of(zones.rename(id, request.name(), request.region(),
                request.sortOrder(), request.centre(), request.clearsCentre()));
    }

    /** Takes an area out of the picker. Saved addresses that name it keep working. */
    @PostMapping("/{id}/retire")
    @PreAuthorize("hasRole('BACKOFFICE')")
    public ZoneResponse retire(@PathVariable UUID id) {
        return ZoneResponse.of(zones.retire(id));
    }

    @PostMapping("/{id}/reinstate")
    @PreAuthorize("hasRole('BACKOFFICE')")
    public ZoneResponse reinstate(@PathVariable UUID id) {
        return ZoneResponse.of(zones.reinstate(id));
    }

    // ---------------------------------------------------------------- merchant

    /**
     * Where this shop delivers, and for how much.
     *
     * <p>An empty list means the shop does not price by area at all: it charges its flat fee and
     * serves everywhere. That is the state every shop starts in, and it is deliberately not the
     * same as "delivers nowhere".
     */
    @GetMapping("/coverage/{storeId}")
    @PreAuthorize("hasAnyRole('MERCHANT','BACKOFFICE')")
    public List<CoverageResponse> coverage(@PathVariable UUID storeId) {
        Store store = requireOwnedStore(storeId);
        return zones.coverageOf(store.getId()).stream()
                .map(z -> CoverageResponse.of(z, zones.require(z.getZoneId())))
                .toList();
    }

    @PutMapping("/coverage/{storeId}/{zoneId}")
    @PreAuthorize("hasAnyRole('MERCHANT','BACKOFFICE')")
    public CoverageResponse setCoverage(@PathVariable UUID storeId,
                                        @PathVariable UUID zoneId,
                                        @Valid @RequestBody CoverageRequest request) {
        Store store = requireOwnedStore(storeId);
        StoreDeliveryZone saved = zones.setCoverage(store.getId(), zoneId,
                request.deliveryFee(), request.minOrder(), request.etaExtraMinutes());
        return CoverageResponse.of(saved, zones.require(zoneId));
    }

    /**
     * Stops delivering to an area.
     *
     * <p>Dropping the last one puts the shop back to a flat fee everywhere rather than leaving it
     * unable to deliver anywhere — which would be a strange thing to have done by removing a row.
     */
    @DeleteMapping("/coverage/{storeId}/{zoneId}")
    @PreAuthorize("hasAnyRole('MERCHANT','BACKOFFICE')")
    public ResponseEntity<Void> dropCoverage(@PathVariable UUID storeId,
                                             @PathVariable UUID zoneId) {
        Store store = requireOwnedStore(storeId);
        zones.dropCoverage(store.getId(), zoneId);
        return ResponseEntity.noContent().build();
    }

    /**
     * The areas around a shop: the neighbourhoods its Demand Radar covers.
     *
     * <p>Order Manager asks this on the merchant's behalf, with the merchant's own token forwarded,
     * and then counts demand in exactly these areas and no others. The neighbourhood is decided
     * HERE, where shops and areas live, and never taken from a client: a list of area ids sent by
     * the app would let any merchant read demand anywhere on the platform. What counts as "around"
     * — placed areas within a fixed distance of the shop's pin — is {@link DeliveryZoneService#around}.
     *
     * <p>MERCHANT for their own shop, BACKOFFICE for any. Another merchant's shop answers 404, the
     * same as a shop that does not exist, so the endpoint confirms nothing about the ids it is
     * handed. Staff accounts (MERCHANT_STAFF) are refused by the role rule: the density this feeds
     * is owner-only, like every order-backed number a shop sees.
     *
     * <p>Live shops only, for the owner and the back office alike: a shop that is not ACTIVE answers
     * 404 too. A draft costs nothing to create and nobody orders from it, so serving one would let a
     * test shop — pinned anywhere, pricing any area — read the demand around other people's shops
     * before it has traded at all. The shop is read as nobody in particular, which already refuses a
     * shop that is not live; the status is checked here as well, where the rule can be seen.
     */
    @GetMapping("/around/{storeId}")
    @PreAuthorize("hasAnyRole('MERCHANT','BACKOFFICE')")
    public NeighbourhoodResponse around(@PathVariable UUID storeId) {
        Store store = stores.read(storeId.toString(), null);
        boolean live = store.getStatus() == Store.Status.ACTIVE;
        boolean mayLook = CurrentUser.hasRole("BACKOFFICE")
                || CurrentUser.requireId().equals(store.getMerchantId());
        if (!live || !mayLook) {
            throw new StoreService.StoreNotFoundException(storeId.toString());
        }
        DeliveryZoneService.Neighbourhood around = zones.around(store);
        return new NeighbourhoodResponse(store.getId(), store.getMerchantId(), around.region(),
                around.radiusMetres(), around.zones().stream().map(ZoneResponse::of).toList());
    }

    /**
     * Ownership, enforced here rather than trusted from the path.
     *
     * <p>BACKOFFICE may touch any shop; a merchant may touch only their own. Without this, knowing
     * a store id would be enough to reprice somebody else's delivery.
     */
    private Store requireOwnedStore(UUID storeId) {
        Store store = stores.read(storeId.toString(), null);
        if (CurrentUser.hasRole("BACKOFFICE")) {
            return store;
        }
        if (!CurrentUser.requireId().equals(store.getMerchantId())) {
            throw new StoreService.StoreNotFoundException(storeId.toString());
        }
        return store;
    }

    // ---------------------------------------------------------------- order placement

    /**
     * What this shop charges to reach this area — the question Order Manager asks at placement.
     *
     * <p>Separate from `GET /api/stores/{id}` because it answers something that endpoint cannot: the
     * fee is no longer a property of the shop alone once areas exist, it is a property of the shop
     * <em>and</em> where the order is going.
     *
     * <p>{@code served: false} is the interesting answer, and it is a 200 rather than a 404: the
     * shop exists and the area exists, they simply do not meet. Order Manager turns that into a
     * refusal the customer can act on.
     */
    @GetMapping("/terms/{storeId}")
    public TermsResponse terms(@PathVariable UUID storeId,
                               @org.springframework.web.bind.annotation.RequestParam(required = false)
                               UUID zoneId) {
        Store store = stores.read(storeId.toString(), null);
        DeliveryZoneService.Terms terms = zones.termsFor(store, zoneId);
        return new TermsResponse(store.getId(), terms.served(), terms.deliveryFee(),
                terms.minOrder(), terms.etaMinMinutes(), terms.etaMaxMinutes());
    }

    public record TermsResponse(UUID storeId, boolean served, BigDecimal deliveryFee,
                                BigDecimal minOrder, int etaMinMinutes, int etaMaxMinutes) {
    }

    // ---------------------------------------------------------------- shapes

    public record ZoneRequest(
            @NotBlank @Size(max = 120) String name,
            @Size(max = 120) String region,
            @PositiveOrZero int sortOrder,
            /**
             * Roughly the middle of the area, for the merchant demand map. Both or neither.
             *
             * <p>Leaving both out, or sending both as null, keeps the centre an edited area already
             * has: every client written before centres existed sends neither, and a rename from one
             * of them must not take the area off the map. {@code clearCentre} removes a centre.
             */
            BigDecimal centerLat,
            BigDecimal centerLng,
            /**
             * True takes the area off the demand map; absent or false says nothing about the centre.
             * Refused alongside a centre, which contradicts it.
             */
            Boolean clearCentre) {

        /**
         * The centre as a checked point, or null. Half a centre, a value out of range and the
         * (0, 0) of an unset field are refused here with a 400 — see {@link GeoPoint}.
         */
        GeoPoint centre() {
            return GeoPoint.ofNullable(centerLat, centerLng);
        }

        /**
         * Whether the request takes the centre off. A centre sent with it is refused with a 400, like
         * any other coordinate that cannot be used, rather than resolved by guessing which was meant.
         */
        boolean clearsCentre() {
            if (!Boolean.TRUE.equals(clearCentre)) {
                return false;
            }
            if (centerLat != null || centerLng != null) {
                throw new GeoPoint.InvalidCoordinateException(
                        "Send a centre or clearCentre, not both");
            }
            return true;
        }
    }

    /**
     * A shop's neighbourhood.
     *
     * @param merchantId   the shop's owner, so Order Manager can check on its own side that the
     *                     merchant asking for density owns the shop they named, and leave that
     *                     owner's own trade out of the count
     * @param region       the region most of these areas belong to — the city label on the map;
     *                     null when none of them names one
     * @param radiusMetres how far from the shop's pin an area counts as near without a coverage row,
     *                     never more than the neighbourhood cap; null for a shop with no pin, whose
     *                     neighbourhood is empty
     * @param zones        active, placed areas within the cap of the pin, in the picker's order
     */
    public record NeighbourhoodResponse(UUID storeId, String merchantId, String region,
                                        Integer radiusMetres, List<ZoneResponse> zones) {
    }

    public record CoverageRequest(
            @jakarta.validation.constraints.NotNull @PositiveOrZero BigDecimal deliveryFee,
            /** Null means "use the shop's own minimum" rather than "no minimum". */
            @PositiveOrZero BigDecimal minOrder,
            @PositiveOrZero int etaExtraMinutes) {
    }

    public record CoverageResponse(UUID zoneId, String zoneName, String region,
                                   BigDecimal deliveryFee, BigDecimal minOrder,
                                   int etaExtraMinutes) {
        static CoverageResponse of(StoreDeliveryZone z, DeliveryZone zone) {
            return new CoverageResponse(zone.getId(), zone.getName(), zone.getRegion(),
                    z.getDeliveryFee(), z.getMinOrder(), z.getEtaExtraMinutes());
        }
    }
}
