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
 * Mapbox Directions — the commercial option, with live traffic.
 *
 * <p>Built alongside OSRM for the same reason the SMS connector ships MontyMobile and Twilio
 * together: which routing engine the platform ends up on is a commercial decision nobody has made,
 * and having both means the cutover is a config change rather than a release.
 *
 * <p>The access token comes from Vault through the Config Server, never from a properties file in
 * the repository and never from a log line — see {@link #estimate}, which is careful not to include
 * the request URI in any message it writes, because for this vendor the URI contains the token.
 * The owner has supplied no Mapbox account, so this provider is unconfigured and answers nothing.
 *
 * <p>Two things to know before switching to it. Every estimate discloses a rider's position and a
 * customer's address to Mapbox, which is a data-processing decision as much as a technical one. And
 * Directions is billed per request: this service would call it on every ETA poll of every live
 * delivery, so a cache or a poll-rate limit needs to exist before it is turned on. Neither is built
 * here, because building a cache for a vendor nobody has bought is guesswork.
 */
@Component
public class MapboxRouteProvider implements RouteProvider {

    public static final String NAME = "MAPBOX";

    private static final Logger log = LoggerFactory.getLogger(MapboxRouteProvider.class);

    private final RestClient client;
    private final String accessToken;
    private final String profile;

    public MapboxRouteProvider(
            RestClient.Builder builder,
            @Value("${delivery.tracking.routing.mapbox.base-url:https://api.mapbox.com}") String baseUrl,
            @Value("${delivery.tracking.routing.mapbox.access-token:}") String accessToken,
            @Value("${delivery.tracking.routing.mapbox.profile:mapbox/driving-traffic}") String profile) {
        this.client = builder.baseUrl(baseUrl).build();
        this.accessToken = accessToken;
        this.profile = profile;
    }

    @Override
    public String name() {
        return NAME;
    }

    @Override
    public boolean isConfigured() {
        return !accessToken.isBlank();
    }

    @Override
    public Optional<RouteEstimate> estimate(GeoPoint from, GeoPoint to) {
        if (!isConfigured()) {
            log.debug("Mapbox asked for an estimate with no access token provisioned");
            return Optional.empty();
        }

        // lng,lat, as Mapbox and OSRM both want it.
        String coordinates = String.format(Locale.ROOT, "%f,%f;%f,%f",
                from.lng(), from.lat(), to.lng(), to.lat());

        try {
            JsonNode response = client.get()
                    .uri(uri -> uri.path("/directions/v5/{profile}/{coordinates}")
                            .queryParam("overview", "false")
                            // Mapbox authenticates by query parameter; it offers no header form.
                            // That is the vendor's design, not a choice made here, and it is why
                            // nothing below ever logs a URI.
                            .queryParam("access_token", accessToken)
                            .build(profile, coordinates))
                    .retrieve()
                    .onStatus(HttpStatusCode::isError, (request, res) -> {
                        // Classified below rather than thrown.
                    })
                    .body(JsonNode.class);

            if (response == null) {
                return Optional.empty();
            }

            String code = response.path("code").asText();
            if (!"Ok".equals(code)) {
                // The code only, never the response body or the URI: an error body from a
                // misconfigured request can echo the query string back, token included.
                log.warn("Mapbox Directions returned code {}", code);
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
            // Deliberately not e's full message into a warn with the URI attached, for the reason
            // above. The stack trace is enough to identify a connectivity failure.
            log.warn("Mapbox route lookup failed; reporting no estimate. Cause: {}",
                    e.getClass().getSimpleName());
            return Optional.empty();
        }
    }
}
