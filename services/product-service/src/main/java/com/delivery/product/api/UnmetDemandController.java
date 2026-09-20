package com.delivery.product.api;

import java.util.UUID;

import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.delivery.platform.security.CurrentUser;
import com.delivery.product.api.dto.DemandDtos.UnmetDemandResponse;
import com.delivery.product.domain.Store;
import com.delivery.product.service.MerchantUnmetDemand;
import com.delivery.product.service.StoreService;

/**
 * The Demand Radar's second read: what the shop's neighbourhood looked for and could not find.
 *
 * <p>Under {@code /api/products/demand} beside the item search, because it is the search log's
 * question: the density half of the radar is Order Manager's ({@code /api/orders/demand/density}),
 * and the screen draws both. {@code demand} is a literal segment, which Spring prefers to
 * {@code ProductController}'s {@code /{id}}, exactly as {@code search} and {@code scans} are.
 *
 * <p><strong>The same access rule as the neighbourhood read it is built on</strong>
 * ({@code DeliveryZoneController#around}): MERCHANT for their own shop, BACKOFFICE for any, and a
 * shop that is not live is a 404 for both. Another merchant's shop answers 404 as well — the same
 * answer as a shop that does not exist — so the endpoint confirms nothing about the ids it is handed.
 * MERCHANT_STAFF is refused by the role rule, as it is for every other number a shop sees about its
 * neighbours.
 *
 * <p>A draft shop is refused for a reason worth naming: a draft costs nothing to create and nobody
 * orders from it, so serving one would let anybody pin a test shop anywhere on the map and read what
 * that street has been searching for.
 *
 * <p>Which areas are answered is decided here from the shop's own pin, never from the request, so
 * nothing a client sends can widen what it sees.
 */
@RestController
@RequestMapping("/api/products/demand")
public class UnmetDemandController {

    private final MerchantUnmetDemand unmet;
    private final StoreService stores;

    public UnmetDemandController(MerchantUnmetDemand unmet, StoreService stores) {
        this.unmet = unmet;
        this.stores = stores;
    }

    /**
     * {@code GET /api/products/demand/unmet/{storeId}}: this week and last, for the shop's areas.
     *
     * <p>Empty lists are the ordinary answer for a quiet week, and the response says why: it carries
     * {@code areasAround} (zero when the platform does not know where the shop is) and
     * {@code minimumSearches} (the floor a term must clear before anybody is told about it), so the
     * screen can tell a merchant which of the two silences they are looking at.
     */
    @GetMapping("/unmet/{storeId}")
    @PreAuthorize("hasAnyRole('MERCHANT','BACKOFFICE')")
    public UnmetDemandResponse unmet(@PathVariable UUID storeId) {
        Store store = stores.read(storeId.toString(), null);
        boolean live = store.getStatus() == Store.Status.ACTIVE;
        boolean mayLook = CurrentUser.hasRole("BACKOFFICE")
                || CurrentUser.requireId().equals(store.getMerchantId());
        if (!live || !mayLook) {
            throw new StoreService.StoreNotFoundException(storeId.toString());
        }
        return UnmetDemandResponse.of(unmet.forStore(store));
    }
}
