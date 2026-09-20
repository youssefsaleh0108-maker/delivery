package com.delivery.tracking.route;

import java.util.List;
import java.util.Locale;

/**
 * The {@code lng,lat;lng,lat;…} list OSRM and Mapbox both take in a route URL.
 *
 * <p>Longitude first — the opposite of everything else in this service, and the reason
 * {@link GeoPoint} exists rather than loose doubles. {@link Locale#ROOT}, so a server whose default
 * locale writes decimal commas cannot turn one coordinate into two.
 */
final class LngLat {

    private LngLat() {
    }

    static String list(List<GeoPoint> stops) {
        StringBuilder coordinates = new StringBuilder();
        for (GeoPoint stop : stops) {
            if (!coordinates.isEmpty()) {
                coordinates.append(';');
            }
            coordinates.append(String.format(Locale.ROOT, "%f,%f", stop.lng(), stop.lat()));
        }
        return coordinates.toString();
    }
}
