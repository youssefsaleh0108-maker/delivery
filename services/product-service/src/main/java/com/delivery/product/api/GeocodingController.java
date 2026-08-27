package com.delivery.product.api;

import java.math.BigDecimal;
import java.util.List;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.delivery.product.api.dto.GeoDtos.PlaceResponse;
import com.delivery.product.api.dto.GeoDtos.PlaceSearchResponse;
import com.delivery.product.api.dto.GeoDtos.ReverseGeocodeResponse;
import com.delivery.product.domain.GeoPoint;
import com.delivery.product.geocoding.GeocodingProvider.PlaceCandidate;
import com.delivery.product.service.GeocodingService;

/**
 * The address picker's back end.
 *
 * <p><strong>Authorisation: any authenticated caller, no role.</strong> A customer saving a delivery
 * address and a merchant placing their shop both need this, and neither has a role in common. What
 * it must not be is public — an open geocoding endpoint is a free proxy onto whichever provider is
 * configured, and it would spend this deployment's Nominatim budget, or its Mapbox bill, on behalf
 * of anybody who found the URL. The rate limiter caps the damage; the login is what stops it being
 * aimed here in the first place.
 *
 * <p>Nothing here logs the query, the point, or anything derived from them. A search term in an
 * address picker is somebody's home address.
 */
@RestController
@RequestMapping("/api/geocoding")
public class GeocodingController {

    /**
     * The longest search term accepted.
     *
     * <p>An address is well under this. A longer one is either a paste accident or somebody probing,
     * and both cost a slot from a one-per-second budget and a row in the cache keyed on text nobody
     * will ever search again.
     */
    private static final int MAX_QUERY_LENGTH = 200;

    /** More candidates than any picker shows. Bounded so one request cannot ask for a thousand. */
    private static final int MAX_RESULTS = 10;

    private final GeocodingService geocoding;

    public GeocodingController(GeocodingService geocoding) {
        this.geocoding = geocoding;
    }

    /**
     * Text in, places out.
     *
     * <p>A blank or too-short query returns an empty list without calling the provider at all. Two
     * characters match half a country, so the answer would be useless — and the address picker fires
     * on every keystroke, so answering locally is what keeps the first two keystrokes of every
     * search off somebody else's server.
     */
    @GetMapping("/search")
    public PlaceSearchResponse search(@RequestParam("q") String query,
                                      @RequestParam(defaultValue = "5") int limit) {

        String trimmed = query == null ? "" : query.trim();
        if (trimmed.length() < 3) {
            return new PlaceSearchResponse(geocoding.activeProviderName(), List.of());
        }
        if (trimmed.length() > MAX_QUERY_LENGTH) {
            trimmed = trimmed.substring(0, MAX_QUERY_LENGTH);
        }

        List<PlaceCandidate> candidates =
                geocoding.search(trimmed, Math.min(Math.max(limit, 1), MAX_RESULTS));

        return new PlaceSearchResponse(
                geocoding.activeProviderName(),
                candidates.stream().map(GeocodingController::toPlace).toList());
    }

    /**
     * A point in, the address at it out.
     *
     * <p>204 rather than 404 when the provider knows of no address there. "You have dropped a pin in
     * the sea" is a successful answer to a question, not a missing resource, and a 404 would make
     * every client treat it as an error worth retrying.
     */
    @GetMapping("/reverse")
    public ResponseEntity<ReverseGeocodeResponse> reverse(@RequestParam BigDecimal latitude,
                                                          @RequestParam BigDecimal longitude) {
        // Validated by construction: an out-of-range or (0, 0) point is refused here rather than
        // sent to a provider that would charge for the privilege of saying no.
        GeoPoint point = new GeoPoint(latitude, longitude);

        return geocoding.reverse(point)
                .map(address -> ResponseEntity.ok(new ReverseGeocodeResponse(
                        geocoding.activeProviderName(),
                        address.label(),
                        address.point().latitude(),
                        address.point().longitude(),
                        address.locality(),
                        address.countryCode())))
                .orElseGet(() -> ResponseEntity.noContent().build());
    }

    private static PlaceResponse toPlace(PlaceCandidate candidate) {
        return new PlaceResponse(
                candidate.label(),
                candidate.point().latitude(),
                candidate.point().longitude(),
                candidate.kind(),
                candidate.confident());
    }
}
