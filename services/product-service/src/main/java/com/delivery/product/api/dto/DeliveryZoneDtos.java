package com.delivery.product.api.dto;

import java.math.BigDecimal;
import java.util.UUID;

import com.delivery.product.domain.DeliveryZone;

/**
 * The shape of a delivery area, wherever the API writes one.
 */
public final class DeliveryZoneDtos {

    private DeliveryZoneDtos() {
    }

    /**
     * One delivery area, in the one shape every endpoint writes it: the area picker
     * ({@code GET /api/delivery-zones}), the Backoffice's list and edits, a shop's neighbourhood,
     * and the areas a shop delivers to on its store read ({@code StoreResponse.deliveryZones}). One
     * record rather than a copy per endpoint, so a client parses them all with one model and they
     * cannot drift apart.
     *
     * <p>An area is a name the customer picks for their address ("Hamra"), and whether a shop goes
     * there is decided by that pick alone, never by distance. The centre is roughly the middle of
     * the neighbourhood, entered by the Backoffice (V30) — a place to put the name on a map, NOT a
     * boundary — and null until the area has been placed. Both or neither. {@code active} is false
     * for an area retired from the picker, which still resolves for the addresses that name it.
     */
    public record ZoneResponse(UUID id, String name, String region, int sortOrder, boolean active,
                               BigDecimal centerLat, BigDecimal centerLng) {

        public static ZoneResponse of(DeliveryZone z) {
            return new ZoneResponse(z.getId(), z.getName(), z.getRegion(), z.getSortOrder(),
                    z.isActive(), z.getCenterLat(), z.getCenterLng());
        }
    }
}
