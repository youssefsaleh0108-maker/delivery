package com.delivery.product.geocoding;

import java.util.List;
import java.util.Optional;

import com.delivery.product.domain.GeoPoint;

/**
 * A source of coordinates for text, and of text for coordinates.
 *
 * <p>An interface for the same reason {@code sms-connector} puts its vendors behind
 * {@code ProviderClient}: the platform has to be able to launch on something free before anyone has
 * signed a contract, and swapping to a paid provider afterwards should be a configuration change,
 * not a development project. The implementations here are
 * {@link NominatimGeocodingProvider} — free, keyless, rate-limited, and what runs today — and
 * {@link MapboxGeocodingProvider}, which is written and will refuse every call until somebody
 * provisions an access token.
 *
 * <p>Implementations must treat everything they return as untrusted. A place label is text a
 * stranger typed into OpenStreetMap; it reaches a customer's screen, so it is length-capped and
 * stripped of control characters before it leaves this package — see {@link PlaceLabels}.
 *
 * <p>Implementations must also never log the query or the point. A search term here is somebody's
 * home address, and an address in a log file is an address in whatever aggregates that log file.
 */
public interface GeocodingProvider {

    /** The name this provider is selected by, e.g. {@code NOMINATIM}. Matches the config value. */
    String name();

    /**
     * Text in, candidate places out, best match first.
     *
     * <p>Returns an empty list when the provider had no matches, which is an answer and not a
     * failure — "no such street" is exactly what the address picker needs to be told. A provider
     * that could not be reached, or that refused, throws {@link GeocodingException} instead, so the
     * caller can tell "nothing there" from "we do not know".
     *
     * @param query a search term, already trimmed and length-capped by the caller
     * @param limit the most candidates to return; providers may return fewer
     */
    List<PlaceCandidate> search(String query, int limit);

    /**
     * A point in, the address at it out.
     *
     * <p>Empty when the provider knows of no address there — mid-ocean, or a stretch of desert. Same
     * distinction as {@link #search}: empty is an answer, an exception is a failure.
     */
    Optional<ResolvedAddress> reverse(GeoPoint point);

    /**
     * One candidate from a forward search.
     *
     * @param label     what to show in the picker. Untrusted text — see {@link PlaceLabels}.
     * @param point     where the pin drops
     * @param kind      the provider's own classification ("street", "restaurant", "suburb"), passed
     *                  through rather than normalised: the vocabularies genuinely differ between
     *                  providers, and a mapping to a shared enum would have to invent meanings.
     *                  Null when the provider did not say.
     * @param confident whether the provider considers this an exact match rather than a guess.
     *                  Carried so the client can style a fuzzy result differently instead of
     *                  presenting every candidate as equally certain.
     */
    record PlaceCandidate(String label, GeoPoint point, String kind, boolean confident) {
    }

    /**
     * The address at a point.
     *
     * @param label       the full one-line address. Untrusted text.
     * @param point       the point the provider snapped to, which is not always the one asked for
     * @param locality    town or city, when the provider named one. Null otherwise — an empty string
     *                    would claim the provider answered "" rather than that it did not answer.
     * @param countryCode ISO 3166-1 alpha-2, uppercased, or null
     */
    record ResolvedAddress(String label, GeoPoint point, String locality, String countryCode) {
    }
}
