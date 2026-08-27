package com.delivery.product.service;

import java.util.List;
import java.util.Optional;

import org.springframework.stereotype.Service;

import com.delivery.product.domain.GeoPoint;
import com.delivery.product.domain.GeocodeCacheEntry;
import com.delivery.product.geocoding.GeocodingProvider;
import com.delivery.product.geocoding.GeocodingProvider.PlaceCandidate;
import com.delivery.product.geocoding.GeocodingProvider.ResolvedAddress;
import com.delivery.product.geocoding.GeocodingProviders;
import com.fasterxml.jackson.core.type.TypeReference;

/**
 * Address search and reverse lookup.
 *
 * <p>Cache first, provider second, with {@link GeocodeCache} owning both sides of the cache and its
 * transactions. This class is deliberately <strong>not</strong> {@code @Transactional}: it can block
 * for a second in the provider's rate limiter and then wait on a network call, and a transaction
 * held across that would pin a database connection for the entire round trip.
 *
 * <p><strong>Nothing here logs a query or a point.</strong> A term typed into an address picker is
 * somebody's home address and a reverse lookup is their exact location. Neither belongs in a log
 * file, and neither is needed to operate this: the counts and timings that are actually useful say
 * nothing about who was looking for what.
 */
@Service
public class GeocodingService {

    private static final TypeReference<List<PlaceCandidate>> CANDIDATE_LIST =
            new TypeReference<>() {
            };

    private static final TypeReference<ResolvedAddress> ADDRESS =
            new TypeReference<>() {
            };

    private final GeocodeCache cache;
    private final GeocodingProviders providers;

    public GeocodingService(GeocodeCache cache, GeocodingProviders providers) {
        this.cache = cache;
        this.providers = providers;
    }

    /**
     * Text in, candidate places out, best match first.
     *
     * <p>An empty list means the geocoder found nothing, which the picker should show as "no
     * matches". A provider that could not answer throws instead, so a customer is never told their
     * street does not exist because a server was down.
     *
     * @param query already trimmed and length-capped by the caller — see the API's validation
     * @param limit how many candidates the caller wants back
     */
    public List<PlaceCandidate> search(String query, int limit) {
        GeocodingProvider provider = providers.active();
        String key = GeocodeCacheEntry.keyFor(query);

        GeocodeCache.Hit<List<PlaceCandidate>> cached =
                cache.lookup(provider.name(), GeocodeCacheEntry.Lookup.FORWARD, key, CANDIDATE_LIST);
        if (cached != null && cached.value() != null) {
            // Trimmed on the way out rather than keyed on the limit. The same search for five
            // results and for ten is the same question asked of the provider; folding the limit
            // into the key would double the rows and halve the hit rate for nothing.
            List<PlaceCandidate> hit = cached.value();
            return hit.size() > limit ? List.copyOf(hit.subList(0, limit)) : hit;
        }

        List<PlaceCandidate> fresh = provider.search(query, limit);
        cache.store(provider.name(), GeocodeCacheEntry.Lookup.FORWARD, key, fresh);
        return fresh;
    }

    /** A point in, the address at it out. Empty means "no address there", not "we failed". */
    public Optional<ResolvedAddress> reverse(GeoPoint point) {
        GeocodingProvider provider = providers.active();
        String key = GeocodeCacheEntry.keyFor(point);

        GeocodeCache.Hit<ResolvedAddress> cached =
                cache.lookup(provider.name(), GeocodeCacheEntry.Lookup.REVERSE, key, ADDRESS);
        if (cached != null) {
            // A hit whose value is null is a remembered "no address there", and is returned as
            // such. That is the whole reason lookup wraps its result — see GeocodeCache.Hit.
            return Optional.ofNullable(cached.value());
        }

        Optional<ResolvedAddress> fresh = provider.reverse(point);
        // The empty answer is stored too, as a literal null payload. "There is no address at this
        // point" is a real and stable fact, and forgetting it means every tap on the same patch of
        // sea spends another slot from a one-per-second budget.
        cache.store(provider.name(), GeocodeCacheEntry.Lookup.REVERSE, key, fresh.orElse(null));
        return fresh;
    }

    /**
     * The name of the geocoder that would answer right now.
     *
     * <p>Returned to the client alongside results on purpose. A pin placed by the free dev geocoder
     * and one placed by a paid provider are not equally trustworthy, and the caller should be able
     * to tell which it is looking at rather than having to assume.
     */
    public String activeProviderName() {
        return providers.active().name();
    }
}
