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
 * The dev geocoder: OpenStreetMap's Nominatim.
 *
 * <p>The counterpart of {@code sms-connector}'s dev-passthrough client, and it exists for the same
 * reason: the platform must be able to launch, and the whole address-picker chain must be
 * exercisable, before anyone has bought a map contract. Nominatim needs no key and no account, so
 * this is a <em>real</em> geocoder returning real answers — not a stub that makes an unbuilt feature
 * look finished.
 *
 * <p><strong>It is still a dev provider, and the reason is the usage policy rather than the data
 * quality.</strong> <a href="https://operations.osmfoundation.org/policies/nominatim/">Nominatim's
 * policy</a> for the public endpoint is explicit, and two of its terms are implemented here because
 * ignoring them gets an application blocked outright:
 *
 * <ul>
 *   <li><strong>A real User-Agent identifying the application.</strong> Not a library default, not a
 *       browser string. It is configurable rather than hard-coded because the policy wants a
 *       contact behind it, and the contact belongs to whoever is running this deployment, not to
 *       the code. If it is not set this provider refuses every call — see {@link #requireUserAgent}.
 *       A default value would have been a lie told to somebody else's server on the operator's
 *       behalf.
 *   <li><strong>At most one request per second, absolute.</strong> Enforced by
 *       {@link MinIntervalRateLimiter} in front of every call, including the ones that end up
 *       failing, because a failed request costs the endpoint just as much as a successful one.
 * </ul>
 *
 * <p>The policy also requires that results be cached rather than re-requested; that is done a layer
 * up, in {@code GeocodingService}, so the cache protects any provider rather than just this one.
 *
 * <p>The remaining term is one code cannot satisfy: the public endpoint is not for "systematic"
 * production use by an application of any size. That is the honest reason this is the dev provider
 * and a commercial one is the seam beside it — not a technical limitation, an entitlement one.
 */
@Component
public class NominatimGeocodingProvider implements GeocodingProvider {

    public static final String NAME = "NOMINATIM";

    private static final Logger log = LoggerFactory.getLogger(NominatimGeocodingProvider.class);

    /**
     * Nominatim's own hard cap on candidates. Asking for more is silently ignored by the server, so
     * clamping here keeps the request honest about what it expects back.
     */
    private static final int MAX_LIMIT = 40;

    private final RestClient client;
    private final String userAgent;
    private final String acceptLanguage;
    private final MinIntervalRateLimiter rateLimiter;

    public NominatimGeocodingProvider(
            RestClient.Builder builder,
            @Value("${delivery.geocoding.nominatim.base-url:https://nominatim.openstreetmap.org}")
            String baseUrl,
            /*
             * No default, on purpose. An unset User-Agent must fail loudly rather than fall back to
             * something plausible: the policy asks for a real identity so the OSM operators can
             * reach whoever is generating the traffic, and inventing one here would put this
             * project's name on an operator's requests without their knowledge.
             */
            @Value("${delivery.geocoding.nominatim.user-agent:}") String userAgent,
            @Value("${delivery.geocoding.nominatim.accept-language:}") String acceptLanguage,
            @Value("${delivery.geocoding.nominatim.min-interval:1s}") Duration minInterval,
            @Value("${delivery.geocoding.nominatim.timeout:5s}") Duration timeout) {

        this.client = builder
                .baseUrl(baseUrl)
                .requestFactory(timeoutsOf(timeout))
                .build();
        this.userAgent = userAgent == null ? "" : userAgent.trim();
        this.acceptLanguage = acceptLanguage == null ? "" : acceptLanguage.trim();

        // One limiter per provider instance, and the instance is a singleton, so every caller in
        // this JVM queues behind the same gate. A limiter created per request would enforce nothing.
        this.rateLimiter = new MinIntervalRateLimiter(minInterval);
    }

    /**
     * Bounds how long a geocode may hold a request thread.
     *
     * <p>The default {@code RestClient} factory has no timeout at all, and the address picker is on
     * an interactive path: a Nominatim outage with no read timeout does not degrade the picker, it
     * parks a servlet thread per attempt until the pool is gone and the rest of the catalog stops
     * answering too.
     */
    private static org.springframework.http.client.ClientHttpRequestFactory timeoutsOf(Duration timeout) {
        org.springframework.http.client.SimpleClientHttpRequestFactory factory =
                new org.springframework.http.client.SimpleClientHttpRequestFactory();
        factory.setConnectTimeout(timeout);
        factory.setReadTimeout(timeout);
        return factory;
    }

    @Override
    public String name() {
        return NAME;
    }

    @Override
    public List<PlaceCandidate> search(String query, int limit) {
        requireUserAgent();

        // Before the call, not after: the limit is on requests made, and a request that turns out
        // to fail has still been made.
        rateLimiter.acquire();

        JsonNode response = get(uri -> uri.path("/search")
                .queryParam("q", query)
                .queryParam("format", "jsonv2")
                .queryParam("addressdetails", 1)
                .queryParam("limit", Math.min(Math.max(limit, 1), MAX_LIMIT))
                .build());

        if (response == null || !response.isArray()) {
            return List.of();
        }

        List<PlaceCandidate> candidates = new ArrayList<>(response.size());
        for (JsonNode node : response) {
            toCandidate(node).ifPresent(candidates::add);
        }
        return candidates;
    }

    @Override
    public Optional<ResolvedAddress> reverse(GeoPoint point) {
        requireUserAgent();
        rateLimiter.acquire();

        JsonNode response = get(uri -> uri.path("/reverse")
                .queryParam("lat", point.latitude().toPlainString())
                .queryParam("lon", point.longitude().toPlainString())
                .queryParam("format", "jsonv2")
                .queryParam("addressdetails", 1)
                .build());

        // Nominatim answers "nowhere" with a 200 and an {"error": ...} body rather than a 404, so
        // the absence has to be detected here rather than from the status.
        if (response == null || response.has("error") || !response.hasNonNull("lat")) {
            return Optional.empty();
        }

        GeoPoint snapped = pointOf(response);
        if (snapped == null) {
            return Optional.empty();
        }

        JsonNode address = response.path("address");
        return Optional.of(new ResolvedAddress(
                PlaceLabels.clean(response.path("display_name").asText(null)),
                snapped,
                localityOf(address),
                countryCodeOf(address)));
    }

    // ---------------------------------------------------------------- internals

    /**
     * Refuses to call at all when nobody has said who we are.
     *
     * <p>Fails closed, exactly as {@code TwilioSmsClient} does with an unprovisioned account SID.
     * Calling anyway with whatever the HTTP library sends by default is the specific behaviour the
     * policy singles out, and it would get this deployment blocked — while looking, from the
     * inside, like an intermittent geocoder fault.
     */
    private void requireUserAgent() {
        if (userAgent.isEmpty()) {
            throw new GeocodingException(
                    "Nominatim will not be called without delivery.geocoding.nominatim.user-agent, "
                            + "which must identify this deployment and give a contact. "
                            + "Its usage policy requires one and blocks applications that omit it.");
        }
    }

    private JsonNode get(java.util.function.Function<org.springframework.web.util.UriBuilder,
            java.net.URI> uri) {
        try {
            return client.get()
                    .uri(uri)
                    .header("User-Agent", userAgent)
                    .headers(headers -> {
                        if (!acceptLanguage.isEmpty()) {
                            headers.set("Accept-Language", acceptLanguage);
                        }
                    })
                    .retrieve()
                    .onStatus(HttpStatusCode::isError, (request, response) -> {
                        // Swallowed so the status can be turned into a message that names the
                        // provider rather than a generic client exception. 429 is the one that
                        // matters: it means the limiter above is not the whole story, most likely
                        // because more than one replica is sharing this endpoint.
                        throw new GeocodingException(
                                "Nominatim refused the request with HTTP "
                                        + response.getStatusCode().value()
                                        + (response.getStatusCode().value() == 429
                                        ? " (rate limited — the public endpoint allows one request "
                                        + "per second per application, and this deployment is "
                                        + "exceeding that across its replicas)"
                                        : ""));
                    })
                    .body(JsonNode.class);

        } catch (GeocodingException e) {
            throw e;
        } catch (RestClientException e) {
            // Deliberately does not include the exception message in what the caller sees: it can
            // carry the request URI, and for a reverse lookup that URI is a person's coordinates.
            log.warn("Nominatim was unreachable ({})", e.getClass().getSimpleName());
            throw new GeocodingException("The geocoding provider could not be reached", e);
        }
    }

    /**
     * Maps one Nominatim row, dropping anything without a usable point.
     *
     * <p>Skipped rather than returned with a null point: a candidate the picker cannot drop a pin
     * for is a row that does nothing but occupy a slot in a list of five.
     */
    private static Optional<PlaceCandidate> toCandidate(JsonNode node) {
        GeoPoint point = pointOf(node);
        if (point == null) {
            return Optional.empty();
        }
        return Optional.of(new PlaceCandidate(
                PlaceLabels.clean(node.path("display_name").asText(null)),
                point,
                PlaceLabels.clean(node.path("type").asText(null)),
                // Nominatim's importance is a relevance score in [0, 1] rather than a confidence,
                // but it is the only signal it gives. The threshold is a display decision — above
                // it the picker may present a result as a match, below it as a suggestion — and it
                // is deliberately conservative, because labelling a guess as certain is the failure
                // that matters here.
                node.path("importance").asDouble(0d) >= 0.5d));
    }

    /**
     * Reads a lat/lon pair, or null when it is missing, unparseable or out of range.
     *
     * <p>Null rather than an exception. A geocoder is an external system and one malformed row in
     * forty must not fail the whole search — but nor may it be passed through, because
     * {@link GeoPoint} would reject it anyway and the rejection would surface as a 500 on a
     * customer's address picker.
     */
    private static GeoPoint pointOf(JsonNode node) {
        String lat = node.path("lat").asText(null);
        String lon = node.path("lon").asText(null);
        if (lat == null || lon == null) {
            return null;
        }
        try {
            return new GeoPoint(new java.math.BigDecimal(lat), new java.math.BigDecimal(lon));
        } catch (NumberFormatException | GeoPoint.InvalidCoordinateException e) {
            log.debug("Discarding a geocoder result with an unusable coordinate");
            return null;
        }
    }

    /**
     * The most specific "place a person would name" in the address.
     *
     * <p>Tried in order because Nominatim populates whichever of these the local data has, and a
     * village genuinely has no city. Taking only {@code city} would leave the field empty across
     * most of the country.
     */
    private static String localityOf(JsonNode address) {
        for (String field : new String[]{"city", "town", "village", "municipality", "suburb", "state"}) {
            String value = PlaceLabels.clean(address.path(field).asText(null));
            if (value != null) {
                return value;
            }
        }
        return null;
    }

    private static String countryCodeOf(JsonNode address) {
        String code = address.path("country_code").asText(null);
        // Nominatim reports it lower-case; ISO 3166-1 alpha-2 is upper-case, and clients matching
        // it against a country list should not have to know which convention this provider chose.
        return code == null || code.isBlank()
                ? null
                : code.trim().toUpperCase(java.util.Locale.ROOT);
    }
}
