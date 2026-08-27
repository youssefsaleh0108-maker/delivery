package com.delivery.product.service;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.product.domain.GeocodeCacheEntry;
import com.delivery.product.domain.GeocodeCacheRepository;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * The persistent memory in front of whichever geocoder is selected.
 *
 * <p>A bean of its own rather than private methods on {@link GeocodingService}, for a reason that is
 * easy to get wrong: {@code REQUIRES_NEW} on a method called from inside the same class does
 * nothing at all. Spring's transaction advice lives on the proxy, and a self-invocation never
 * touches it — so the isolation the write path depends on would have been silently absent, and the
 * comment claiming it would have been a lie. Crossing a bean boundary is what makes it real.
 *
 * <p>It also keeps the transactions short. {@link GeocodingService} sleeps for up to a second in the
 * rate limiter and then makes a network call; a transaction spanning that would pin a Hikari
 * connection for the whole round trip, and ten concurrent address lookups would exhaust a pool of
 * ten while doing nothing but waiting on somebody else's server.
 */
@Component
public class GeocodeCache {

    private static final Logger log = LoggerFactory.getLogger(GeocodeCache.class);

    private final GeocodeCacheRepository entries;
    private final ObjectMapper objectMapper;
    private final Clock clock;
    private final Duration ttl;
    private final Duration evictAfter;

    public GeocodeCache(GeocodeCacheRepository entries, ObjectMapper objectMapper, Clock clock,
                        /*
                         * Thirty days. A street does not move, and the underlying OSM data changes
                         * on a scale of months, so a short TTL would spend the rate budget
                         * re-confirming answers that were never going to differ. Long enough to be
                         * worth having, short enough that a genuine correction upstream reaches
                         * customers inside a month.
                         */
                        @Value("${delivery.geocoding.cache.ttl:30d}") Duration ttl,
                        @Value("${delivery.geocoding.cache.evict-after:180d}") Duration evictAfter) {
        this.entries = entries;
        this.objectMapper = objectMapper;
        this.clock = clock;
        this.ttl = ttl;
        this.evictAfter = evictAfter;
    }

    /**
     * A cached answer wrapped in a {@link Hit}, or null when there is no usable one.
     *
     * <p>The wrapper is not ceremony. A reverse lookup's honest answer is sometimes "there is no
     * address at that point", which is stored as a literal null — and a bare {@code T} return could
     * not tell that remembered null apart from a miss, so the one case caching exists to prevent
     * (repeatedly re-asking about a patch of sea, at one request per second) would go on happening
     * forever. {@code Optional} cannot carry it either, since it cannot hold a null.
     *
     * <p>A stale entry is left in place rather than deleted. {@link #store} refreshes the row, so
     * deleting on a stale read would open a window in which a second request finds nothing and calls
     * the provider too — an extra call against a one-per-second budget, caused by the cache.
     */
    @Transactional
    public <T> Hit<T> lookup(String provider, GeocodeCacheEntry.Lookup lookup, String key,
                             TypeReference<T> shape) {
        Instant now = clock.instant();

        GeocodeCacheEntry entry = entries.findByProviderAndLookupAndCacheKey(provider, lookup, key)
                .filter(fresh -> fresh.isFreshAt(now, ttl))
                .orElse(null);
        if (entry == null) {
            return null;
        }

        Hit<T> hit = deserialize(entry, shape);
        if (hit == null) {
            // Unreadable, so it was not a hit and must not be counted as one.
            return null;
        }
        entry.recordHit();
        return hit;
    }

    /**
     * A cached value, which may legitimately be null.
     *
     * @param value the remembered answer; null means the provider's answer was "nothing here"
     */
    public record Hit<T>(T value) {
    }

    /**
     * Remembers an answer, upserting on {@code (provider, lookup, key)}.
     *
     * <p>{@code REQUIRES_NEW} because a failure to cache must never fail the request that produced
     * the answer. Two requests for the same new address race to insert and the loser hits the unique
     * constraint; that is a cache miss, not an error. Catching it inside the caller's transaction
     * would not help — the transaction would already be marked rollback-only and would fail at
     * commit regardless — so the write needs a transaction it is allowed to lose.
     */
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void store(String provider, GeocodeCacheEntry.Lookup lookup, String key, Object payload) {
        try {
            String json = objectMapper.writeValueAsString(payload);
            Instant now = clock.instant();

            entries.findByProviderAndLookupAndCacheKey(provider, lookup, key)
                    .ifPresentOrElse(
                            entry -> entry.refresh(json, now),
                            () -> entries.save(new GeocodeCacheEntry(provider, lookup, key, json, now)));

        } catch (DataIntegrityViolationException raced) {
            log.debug("Another request cached the same lookup first");

        } catch (Exception e) {
            // Never fatal, and deliberately not rethrown. A geocode that worked and failed to cache
            // is still a geocode that worked; the customer gets their address either way.
            // The exception TYPE only: its message can carry the payload, and a reverse lookup's
            // payload is somebody's street.
            log.warn("Could not cache a geocoding result ({})", e.getClass().getSimpleName());
        }
    }

    /**
     * Deletes entries nobody has asked about in a long time.
     *
     * <p>Not {@code @Scheduled}. This service runs multiple replicas with no scheduler lock, so an
     * annotation here would mean one sweep per replica; it is a method for an operator or a future
     * single-runner job to call. The table holds one row per distinct address ever searched, so
     * leaving it unswept is a slow leak rather than a problem.
     */
    @Transactional
    public int evictStale() {
        int removed = entries.deleteFetchedBefore(clock.instant().minus(evictAfter));
        if (removed > 0) {
            log.info("Evicted {} geocode cache entries older than {}", removed, evictAfter);
        }
        return removed;
    }

    /**
     * Turns a stored payload back into objects, treating anything unreadable as a miss.
     *
     * <p>A payload written by an older shape of the candidate record would otherwise poison that one
     * address forever. Falling back to a miss means a deploy that changes the record simply
     * re-fetches, which is the behaviour a cache is supposed to have.
     */
    private <T> Hit<T> deserialize(GeocodeCacheEntry entry, TypeReference<T> shape) {
        try {
            // A payload of the four characters "null" deserialises to a null value, which is a
            // remembered "nothing here" rather than a failure — hence the wrapper.
            return new Hit<>(objectMapper.readValue(entry.getPayload(), shape));
        } catch (Exception e) {
            log.warn("Discarding an unreadable geocode cache entry (id {})", entry.getId());
            return null;
        }
    }
}
