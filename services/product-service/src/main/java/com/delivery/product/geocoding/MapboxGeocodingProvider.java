package com.delivery.product.geocoding;

import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatusCode;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;

import com.delivery.product.domain.GeoPoint;
import com.fasterxml.jackson.databind.JsonNode;

/**
 * The commercial seam: Mapbox Geocoding.
 *
 * <p><strong>This has never made a successful request, and cannot until somebody provisions an
 * access token.</strong> That is a statement of fact rather than a caveat. It is written and wired
 * so that moving off the dev geocoder is a configuration change — the same justification the SMS
 * connector gives for shipping {@code TwilioSmsClient} before the vendor decision was made — but no
 * response shape below has been checked against the live API, and the first person to switch this
 * on should expect to correct something.
 *
 * <p>It fails closed. With no token it refuses every call rather than calling Mapbox
 * unauthenticated, for the reason {@code TwilioSmsClient} gives: an unconfigured vendor that fails
 * loudly is far better than one that half-works, and a geocoder that half-works puts shops at the
 * wrong coordinates.
 *
 * <p>Mapbox is one of two obvious choices; Google Places is the other. Mapbox is written here
 * because its terms permit storing a geocoded coordinate against a record, which is exactly what
 * pinning a store does, and Google's do not without a Places contract. That is a licensing
 * distinction the owner should confirm for their jurisdiction before committing either way — see
 * the geocoding section of this service's notes.
 */
@Component
public class MapboxGeocodingProvider implements GeocodingProvider {

    public static final String NAME = "MAPBOX";

    private static final Logger log = LoggerFactory.getLogger(MapboxGeocodingProvider.class);

    /** Mapbox's own cap on results per forward request. */
    private static final int MAX_LIMIT = 10;

    private final RestClient client;
    private final String accessToken;
    private final String country;

    public MapboxGeocodingProvider(
            RestClient.Builder builder,
            @Value("${delivery.geocoding.mapbox.base-url:https://api.mapbox.com}") String baseUrl,
            // No default and no fallback. Comes from Vault through the Config Server, like every
            // other vendor credential on this platform, and is never read from a settings table
            // and never logged.
            @Value("${delivery.geocoding.mapbox.access-token:}") String accessToken,
            // Biases results to one country. Optional: a marketplace operating in one market gets
            // markedly better matches for a bare street name with it set.
            @Value("${delivery.geocoding.mapbox.country:}") String country,
            @Value("${delivery.geocoding.mapbox.timeout:5s}") Duration timeout) {

        org.springframework.http.client.SimpleClientHttpRequestFactory factory =
                new org.springframework.http.client.SimpleClientHttpRequestFactory();
        factory.setConnectTimeout(timeout);
        factory.setReadTimeout(timeout);

        this.client = builder.baseUrl(baseUrl).requestFactory(factory).build();
        this.accessToken = accessToken == null ? "" : accessToken.trim();
        this.country = country == null ? "" : country.trim();
    }

    @Override
    public String name() {
        return NAME;
    }

    /**
     * No rate limiter here, and that is not an oversight.
     *
     * <p>Mapbox's limits are a term of a paid plan rather than a fixed one-per-second courtesy, and
     * a hard-coded gate would either throttle a plan that has paid for more or fail to protect one
     * that has bought less. Whoever provisions the token should set the plan's limit, and this is
     * where a limiter would go.
     */
    @Override
    public List<PlaceCandidate> search(String query, int limit) {
        requireToken();

        JsonNode response = get(uri -> uri
                .path("/geocoding/v5/mapbox.places/{query}.json")
                .queryParam("access_token", accessToken)
                .queryParam("limit", Math.min(Math.max(limit, 1), MAX_LIMIT))
                .queryParamIfPresent("country",
                        country.isEmpty() ? Optional.empty() : Optional.of(country))
                .build(query));

        return featuresOf(response);
    }

    @Override
    public Optional<ResolvedAddress> reverse(GeoPoint point) {
        requireToken();

        // Mapbox puts the point in the PATH as "lon,lat" — longitude first, which is the opposite
        // order to Nominatim's query parameters and the single easiest thing to get wrong when
        // switching providers. It is spelled out here so the next reader does not have to check.
        String coordinates = point.longitude().toPlainString() + "," + point.latitude().toPlainString();

        JsonNode response = get(uri -> uri
                .path("/geocoding/v5/mapbox.places/{coordinates}.json")
                .queryParam("access_token", accessToken)
                .queryParam("limit", 1)
                .build(coordinates));

        return featuresOf(response).stream()
                .findFirst()
                .map(candidate -> new ResolvedAddress(
                        candidate.label(),
                        candidate.point(),
                        // Mapbox nests locality and country inside each feature's `context` array
                        // rather than in a flat address object. Left unread rather than guessed at:
                        // returning null says "we do not know", which is true, where a wrong guess
                        // parsed from an unverified shape would say something false.
                        null,
                        null));
    }

    // ---------------------------------------------------------------- internals

    private void requireToken() {
        if (accessToken.isEmpty()) {
            throw new GeocodingException(
                    "Mapbox is selected as the geocoding provider but no access token is "
                            + "provisioned. Set delivery.geocoding.mapbox.access-token from Vault, "
                            + "or set delivery.geocoding.provider back to NOMINATIM.");
        }
    }

    private JsonNode get(java.util.function.Function<org.springframework.web.util.UriBuilder,
            java.net.URI> uri) {
        try {
            return client.get()
                    .uri(uri)
                    .retrieve()
                    .onStatus(HttpStatusCode::isError, (request, response) ->
                            // The status only. A Mapbox error body can echo the query back, and for
                            // a reverse lookup the query is a person's coordinates.
                            {
                                throw new GeocodingException(
                                        "Mapbox refused the request with HTTP "
                                                + response.getStatusCode().value());
                            })
                    .body(JsonNode.class);

        } catch (GeocodingException e) {
            throw e;
        } catch (RestClientException e) {
            // The message is withheld for the same reason as in the Nominatim client: it can carry
            // the request URI, and this one has the access token in it.
            log.warn("Mapbox was unreachable ({})", e.getClass().getSimpleName());
            throw new GeocodingException("The geocoding provider could not be reached", e);
        }
    }

    /**
     * Maps Mapbox's GeoJSON {@code features} array.
     *
     * <p>Each feature carries {@code center} as {@code [longitude, latitude]}. GeoJSON's axis order
     * is the reverse of the one every human writes, and getting it backwards puts every shop in the
     * wrong hemisphere without erroring anywhere — so the two are named rather than indexed inline.
     */
    private static List<PlaceCandidate> featuresOf(JsonNode response) {
        if (response == null) {
            return List.of();
        }
        JsonNode features = response.path("features");
        if (!features.isArray()) {
            return List.of();
        }

        List<PlaceCandidate> candidates = new ArrayList<>(features.size());
        for (JsonNode feature : features) {
            JsonNode center = feature.path("center");
            if (!center.isArray() || center.size() < 2) {
                continue;
            }
            double longitude = center.get(0).asDouble();
            double latitude = center.get(1).asDouble();

            GeoPoint point;
            try {
                point = GeoPoint.of(latitude, longitude);
            } catch (GeoPoint.InvalidCoordinateException e) {
                // One bad feature does not fail the search, for the same reason as in the Nominatim
                // client: a geocoder is an external system and a customer's address picker must not
                // 500 because of one malformed row.
                log.debug("Discarding a Mapbox feature with an unusable coordinate");
                continue;
            }

            candidates.add(new PlaceCandidate(
                    PlaceLabels.clean(feature.path("place_name").asText(null)),
                    point,
                    PlaceLabels.clean(feature.path("place_type").path(0).asText(null)),
                    // Mapbox's relevance is documented as 0..1 with 1 an exact match. Same
                    // conservative threshold as the Nominatim client, so a client styling a
                    // "confident" result does not have to know which provider answered.
                    feature.path("relevance").asDouble(0d) >= 0.9d));
        }
        return candidates;
    }
}
