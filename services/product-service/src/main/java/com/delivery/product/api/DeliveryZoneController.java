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

import com.delivery.product.domain.DeliveryZone;
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
     * it before they have an address at all.
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
        DeliveryZone created =
                zones.create(request.name(), request.region(), request.sortOrder());
        return ResponseEntity.status(HttpStatus.CREATED).body(ZoneResponse.of(created));
    }

    @PutMapping("/{id}")
    @PreAuthorize("hasRole('BACKOFFICE')")
    public ZoneResponse rename(@PathVariable UUID id, @Valid @RequestBody ZoneRequest request) {
        return ZoneResponse.of(
                zones.rename(id, request.name(), request.region(), request.sortOrder()));
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
            @PositiveOrZero int sortOrder) {
    }

    public record ZoneResponse(UUID id, String name, String region, int sortOrder, boolean active) {
        static ZoneResponse of(DeliveryZone z) {
            return new ZoneResponse(z.getId(), z.getName(), z.getRegion(), z.getSortOrder(),
                    z.isActive());
        }
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
