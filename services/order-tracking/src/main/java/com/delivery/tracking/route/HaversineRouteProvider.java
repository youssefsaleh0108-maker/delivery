package com.delivery.tracking.route;

import java.time.Duration;
import java.util.Optional;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

/**
 * The dev routing provider: great-circle distance at a configured average speed.
 *
 * <p><strong>This is not a route.</strong> It measures the straight line between two points and
 * divides by a number from a config file. It does not know about roads, one-way streets, rivers,
 * bridges, traffic or the fact that the customer's building is on the far side of a motorway. In a
 * dense city the real driven distance is commonly 20–40% longer than this, and the error is not
 * random — it is always an underestimate, so every ETA it produces is optimistic.
 *
 * <p>It exists so the whole chain — projection, fix, distance, arrival instant, screen — can be
 * exercised and tested before anyone has bought a routing account, exactly as the SMS connector's
 * dev passthrough does for messaging. The owner has supplied no routing key; see the service report.
 *
 * <p>Two things keep it from being mistaken for the real thing. Its {@link #name()} says DEV and is
 * returned in every API response that carries one of its estimates, so no screen can render the
 * number without being told where it came from. And the average speed is a single deliberately
 * blunt figure rather than a per-segment model, because a more elaborate approximation would look
 * more credible without being any more true.
 */
@Component
public class HaversineRouteProvider implements RouteProvider {

    public static final String NAME = "HAVERSINE_DEV";

    /**
     * IUGG mean Earth radius in metres.
     *
     * <p>The mean radius rather than the equatorial one: the equatorial figure is ~0.34% high at
     * temperate latitudes, and while that is far inside this provider's real error budget, a
     * constant that is knowably wrong invites someone to trust the digits after it.
     */
    private static final double EARTH_MEAN_RADIUS_METRES = 6_371_008.8;

    private final double averageSpeedMetresPerSecond;

    public HaversineRouteProvider(
            // Door-to-door, not top speed: an urban scooter's average once junctions, handovers and
            // waiting at a counter are included. The default is roughly what a city courier
            // achieves; it is a knob because it is the only thing here that can be tuned against
            // observed delivery times.
            @Value("${delivery.tracking.routing.average-speed-kmh:18}") double averageSpeedKmh) {
        if (averageSpeedKmh <= 0) {
            // Fail at startup rather than dividing by zero on a customer's tracking screen.
            throw new IllegalArgumentException(
                    "delivery.tracking.routing.average-speed-kmh must be positive, was "
                            + averageSpeedKmh);
        }
        this.averageSpeedMetresPerSecond = averageSpeedKmh * 1000d / 3600d;
    }

    @Override
    public String name() {
        return NAME;
    }

    /** Always. It needs nothing but arithmetic — which is exactly why it is the dev provider. */
    @Override
    public boolean isConfigured() {
        return true;
    }

    @Override
    public Optional<RouteEstimate> estimate(GeoPoint from, GeoPoint to) {
        double metres = distanceMetres(from, to);
        long seconds = Math.round(metres / averageSpeedMetresPerSecond);
        return Optional.of(new RouteEstimate(metres, Duration.ofSeconds(seconds), NAME));
    }

    /**
     * Great-circle distance in metres.
     *
     * <p>Haversine rather than the spherical law of cosines: the cosine form loses precision for
     * short distances, and almost every distance this platform measures is short.
     */
    public static double distanceMetres(GeoPoint from, GeoPoint to) {
        double lat1 = Math.toRadians(from.lat());
        double lat2 = Math.toRadians(to.lat());
        double deltaLat = Math.toRadians(to.lat() - from.lat());
        double deltaLng = Math.toRadians(to.lng() - from.lng());

        double a = Math.pow(Math.sin(deltaLat / 2), 2)
                + Math.cos(lat1) * Math.cos(lat2) * Math.pow(Math.sin(deltaLng / 2), 2);
        double c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));

        return EARTH_MEAN_RADIUS_METRES * c;
    }
}
