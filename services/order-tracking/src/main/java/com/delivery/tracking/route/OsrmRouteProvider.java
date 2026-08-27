package com.delivery.tracking.route;

import java.time.Duration;
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
}
