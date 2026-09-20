package com.delivery.tracking.route;

import java.time.Duration;

/**
 * The way through a list of stops, in order: how far, how long, who says so, and — when the
 * provider knows the roads — the line to draw.
 *
 * <p>{@code polyline6} is null for a provider that does not know where the roads are. That is not
 * a missing value to be filled in; it is the answer. A client draws a null-geometry path as dashed
 * straight segments between the stops and labels it approximate, and it never draws a curve of its
 * own, because a curve looks like a road. A provider that does know the roads and returned no
 * geometry has not answered at all (see {@link RouteProvider#path}), so a road is never drawn that
 * the provider did not return.
 *
 * @param distanceMetres metres along the whole path, every leg summed
 * @param travelTime     how long the provider thinks the whole path takes
 * @param provider       the {@link RouteProvider#name()} that computed it, as on every estimate
 * @param polyline6      the route's shape as an encoded polyline at 1e6 precision (the format OSRM
 *                       and Mapbox both emit with {@code geometries=polyline6}), or null for a
 *                       straight-line provider
 */
public record RoutePath(double distanceMetres, Duration travelTime, String provider,
                        String polyline6) {

    public RoutePath {
        if (distanceMetres < 0) {
            throw new IllegalArgumentException("Distance cannot be negative: " + distanceMetres);
        }
        if (travelTime.isNegative()) {
            throw new IllegalArgumentException("Travel time cannot be negative: " + travelTime);
        }
    }

    /** How the path is to be drawn, read off what the provider actually returned. */
    public PathGeometry geometry() {
        return polyline6 == null ? PathGeometry.STRAIGHT : PathGeometry.ROAD;
    }
}
