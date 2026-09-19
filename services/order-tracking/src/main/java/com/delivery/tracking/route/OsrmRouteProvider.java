package com.delivery.tracking.route;

import java.time.Duration;
import java.util.List;
import java.util.Locale;
import java.util.Optional;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatusCode;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

import com.fasterxml.jackson.databind.JsonNode;

/**
 * OSRM, the open-source routing engine.
 *
 * <p>The cheapest way to make routing real, because it can be self-hosted from an OpenStreetMap
 * extract with no vendor account at all — which is why it is the first real provider rather than a
 * commercial one. It needs a base URL and nothing else; the owner has not supplied one, so this
 * provider is unconfigured and refuses to answer. See the service report.
 *
 * <p>The public demo server at {@code router.project-osrm.org} is deliberately not a default. It
 * carries no availability guarantee, rate-limits without warning, and pointing a customer-facing
 * ETA at it would make the tracking screen depend on a volunteer's box. A default that half-works
 * is worse than none.
 *
 * <p>Note what turning this on means: every estimate sends a rider's position and a customer's
 * doorstep to whatever host is configured. Self-hosted that is fine. Against someone else's server
 * it is a disclosure of customer location data and needs to be a decision, not a config typo — one
 * more reason there is no default here.
 */
@Component
public class OsrmRouteProvider implements RouteProvider {

    public static final String NAME = "OSRM";

    private static final Logger log = LoggerFactory.getLogger(OsrmRouteProvider.class);

    private final RestClient client;
    private final String baseUrl;
    private final String profile;

    public OsrmRouteProvider(RestClient.Builder builder,
                             @Value("${delivery.tracking.routing.osrm.base-url:}") String baseUrl,
                             // "driving" suits scooters and cars; "cycling" and "foot" exist for a
                             // fleet that is not motorised. Configurable because which one is right
                             // is a property of the fleet, not of the code.
                             @Value("${delivery.tracking.routing.osrm.profile:driving}") String profile) {
        this.baseUrl = baseUrl;
        this.profile = profile;
        this.client = baseUrl.isBlank() ? null : builder.baseUrl(baseUrl).build();
    }

    @Override
    public String name() {
        return NAME;
    }

    @Override
    public boolean isConfigured() {
        return !baseUrl.isBlank();
    }

    @Override
    public Optional<RouteEstimate> estimate(GeoPoint from, GeoPoint to) {
        if (!isConfigured()) {
            // Empty, not an exception and certainly not a straight-line fallback: an ETA that
            // silently downgraded to arithmetic would look identical to a routed one on the wire
            // apart from the provider name, and the whole point of that name is that it is true.
            log.debug("OSRM asked for an estimate with no base URL configured");
            return Optional.empty();
        }

        // OSRM takes lng,lat — the opposite order to almost everything else here, and the reason
        // GeoPoint exists rather than a pair of doubles.
        String coordinates = String.format(Locale.ROOT, "%f,%f;%f,%f",
                from.lng(), from.lat(), to.lng(), to.lat());

        try {
            JsonNode response = client.get()
                    .uri(uri -> uri.path("/route/v1/{profile}/{coordinates}")
                            // overview=false: we want the distance and duration, not the geometry.
                            // The polyline is kilobytes per request on a path called several times
                            // a second per delivery, and nothing here draws it.
                            .queryParam("overview", "false")
                            .build(profile, coordinates))
                    .retrieve()
                    .onStatus(HttpStatusCode::isError, (request, res) -> {
                        // Swallowed so a bad status becomes an empty estimate below rather than an
                        // exception on a customer's tracking screen.
                    })
                    .body(JsonNode.class);

            if (response == null || !"Ok".equals(response.path("code").asText())) {
                log.warn("OSRM returned no usable route (code {})",
                        response == null ? "none" : response.path("code").asText());
                return Optional.empty();
            }

            JsonNode route = response.path("routes").path(0);
            if (route.isMissingNode()) {
                return Optional.empty();
            }

            double metres = route.path("distance").asDouble();
            long seconds = Math.round(route.path("duration").asDouble());
            return Optional.of(new RouteEstimate(metres, Duration.ofSeconds(seconds), NAME));

        } catch (Exception e) {
            // The routing host being unreachable must degrade the ETA, never the tracking screen:
            // "where is my rider" still works without "when will they arrive".
            log.warn("OSRM route lookup failed; reporting no estimate", e);
            return Optional.empty();
        }
    }

    /**
     * The routed path through the stops, with the road geometry to draw.
     *
     * <p>{@code overview=simplified}: a phone's map needs the shape of the route, not every vertex
     * OSRM knows, and the simplified line keeps a checkout map's refresh to a few hundred bytes.
     * {@code geometries=polyline6} is the 1e6-precision encoding, which is what the app decodes.
     *
     * <p>A route that comes back without geometry is treated as no route at all. Falling back to
     * straight lines here would put a line the provider never returned on a map labelled as roads.
     */
    @Override
    public Optional<RoutePath> path(List<GeoPoint> stops) {
        if (!isConfigured() || stops.size() < 2) {
            // Unconfigured is the registry's problem to announce; this just declines, as estimate
            // does.
            return Optional.empty();
        }

        // lng,lat per stop and ';' between them. The values are numbers formatted here, so they go
        // into the path as they are rather than as an expanded variable, which would
        // percent-encode the separators OSRM splits on.
        String coordinates = LngLat.list(stops);

        try {
            JsonNode response = client.get()
                    .uri(uri -> uri.path("/route/v1/{profile}/" + coordinates)
                            .queryParam("overview", "simplified")
                            .queryParam("geometries", "polyline6")
                            .build(profile))
                    .retrieve()
                    .onStatus(HttpStatusCode::isError, (request, res) -> {
                        // Classified below: a bad status is an empty path, not an exception.
                    })
                    .body(JsonNode.class);

            if (response == null || !"Ok".equals(response.path("code").asText())) {
                log.warn("OSRM returned no usable path (code {})",
                        response == null ? "none" : response.path("code").asText());
                return Optional.empty();
            }

            JsonNode route = response.path("routes").path(0);
            JsonNode geometry = route.path("geometry");
            if (route.isMissingNode() || !geometry.isTextual() || geometry.asText().isEmpty()) {
                return Optional.empty();
            }

            double metres = route.path("distance").asDouble();
            long seconds = Math.round(route.path("duration").asDouble());
            return Optional.of(new RoutePath(metres, Duration.ofSeconds(seconds), NAME,
                    geometry.asText()));

        } catch (Exception e) {
            log.warn("OSRM path lookup failed; drawing no path", e);
            return Optional.empty();
        }
    }

    /** Roads, as OSRM returned them. */
    @Override
    public PathGeometry pathGeometry() {
        return PathGeometry.ROAD;
    }

    /**
     * Yes: OSRM here is the platform's own server over open data, so a path may be kept and served
     * again, which is what keeps a checkout map's refreshes from re-routing the same streets.
     */
    @Override
    public boolean mayCachePaths() {
        return true;
    }
}
