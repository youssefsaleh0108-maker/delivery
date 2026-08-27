package com.delivery.tracking.route;

import java.util.Optional;

/**
 * A WGS-84 coordinate.
 *
 * <p>A type rather than a pair of loose doubles because the two are trivially transposable and
 * nothing in a signature like {@code estimate(double, double, double, double)} stops it. A
 * lat/lng swap does not fail — it silently relocates the delivery, and the ETA reports the wrong
 * answer confidently, which is the failure this codebase least wants.
 */
public record GeoPoint(double lat, double lng) {

    public GeoPoint {
        // Validated at construction rather than at the edge, so a coordinate that reached us from
        // a message rather than from a validated request body is checked too.
        if (lat < -90 || lat > 90) {
            throw new IllegalArgumentException("Latitude out of range: " + lat);
        }
        if (lng < -180 || lng > 180) {
            throw new IllegalArgumentException("Longitude out of range: " + lng);
        }
    }

    /**
     * A point from a nullable pair, empty unless both halves are present.
     *
     * <p>Half a coordinate is not a location, and treating a missing longitude as zero would put
     * the point in the Gulf of Guinea — the classic null-island bug, which looks like data rather
     * than like an absence.
     */
    public static Optional<GeoPoint> of(Double lat, Double lng) {
        if (lat == null || lng == null) {
            return Optional.empty();
        }
        return Optional.of(new GeoPoint(lat, lng));
    }
}
