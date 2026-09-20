package com.delivery.product.domain;

import java.math.BigDecimal;

/**
 * A map pin for a test whose subject is not the map.
 *
 * <p>{@link Store#publish} refuses a shop with no pin, so every fixture that wants a LISTED shop
 * now needs one — opening hours, offers, gift bundles, the storefront's ordering, all of it. Those
 * tests are not about where the shop is, and a coordinate pair spelled out in each of them would
 * read as though it mattered. It does not: {@link #BEIRUT} is simply somewhere real, and a test
 * that does care about distance states its own points ({@code NearbyStoreSearchTest} does).
 *
 * <p>Not a random point, and not (0, 0): {@link GeoPoint} refuses Null Island, and a random pin
 * would make a distance assertion somewhere else flap.
 */
public final class TestPin {

    /** Martyrs' Square, near enough. The platform's own city. */
    public static final GeoPoint BEIRUT =
            new GeoPoint(new BigDecimal("33.893800"), new BigDecimal("35.501800"));

    private TestPin() {
    }

    /**
     * Makes sure the shop has a pin so it may be listed, and hands it back for chaining.
     *
     * <p>Leaves an existing pin alone. A fixture that placed its shop somewhere on purpose —
     * {@code NearbyStoreSearchTest}'s Jounieh, Hamra and Achrafieh shops, and every distance
     * assertion built on them — must keep the point it chose; this only fills the gap for the
     * fixtures that never cared.
     */
    public static Store pinned(Store store) {
        if (store.location() == null) {
            store.pinAt(BEIRUT);
        }
        return store;
    }
}
