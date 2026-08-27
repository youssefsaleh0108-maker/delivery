package com.delivery.product.domain;

import java.time.Duration;
import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * One remembered geocoder answer.
 *
 * <p>Caching is not an optimisation here, it is a condition of use. OpenStreetMap's Nominatim usage
 * policy requires that results be cached and caps the public endpoint at one request per second; a
 * service that re-asks for the same street every time a merchant re-opens the address picker would
 * burn its entire budget on questions it has already had answered.
 *
 * <p>Persisted rather than held in memory so it survives a restart and is shared across replicas —
 * an in-process map would replay the whole rate budget over the wire after every deploy, which is
 * precisely the behaviour the policy exists to stop.
 */
@Entity
@Table(name = "geocode_cache")
public class GeocodeCacheEntry {

    /** Which direction was asked. Separate from the key — see {@link #keyFor}. */
    public enum Lookup {
        /** Text in, candidate places out. */
        FORWARD,
        /** Point in, address out. */
        REVERSE
    }

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    /**
     * The provider whose answer this is.
     *
     * <p>Part of the key because a switch of provider must not serve the previous vendor's results
     * under the new one's name. They disagree — about spelling, about which of several matches comes
     * first, and about which side of a street a point falls on.
     */
    @Column(name = "provider", nullable = false, length = 32, updatable = false)
    private String provider;

    @Enumerated(EnumType.STRING)
    @Column(name = "lookup", nullable = false, length = 16, updatable = false)
    private Lookup lookup;

    @Column(name = "cache_key", nullable = false, length = 512, updatable = false)
    private String cacheKey;

    /** The provider's answer, already translated into this service's own shape. */
    @Column(name = "payload", nullable = false, columnDefinition = "text")
    private String payload;

    @Column(name = "fetched_at", nullable = false)
    private Instant fetchedAt;

    @Column(name = "hit_count", nullable = false)
    private int hitCount;

    protected GeocodeCacheEntry() {
        // for JPA
    }

    public GeocodeCacheEntry(String provider, Lookup lookup, String cacheKey, String payload,
                             Instant fetchedAt) {
        this.id = UUID.randomUUID();
        this.provider = provider;
        this.lookup = lookup;
        this.cacheKey = cacheKey;
        this.payload = payload;
        this.fetchedAt = fetchedAt;
        this.hitCount = 0;
    }

    /**
     * Normalises a forward-search term into a cache key.
     *
     * <p>Case and whitespace are folded because "Hamra Street" and "hamra  street" are the same
     * question, and a cache that treats them as two is a cache that mostly misses. Nothing else is
     * touched: stripping punctuation or diacritics would fold together queries the geocoder itself
     * distinguishes, and a wrong cache hit is worse than a miss.
     *
     * <p>The result is truncated to the column width. A query long enough to hit that limit is
     * already rejected at the API, so this is a belt-and-braces guard against a non-HTTP caller
     * rather than something that happens in normal use.
     */
    public static String keyFor(String query) {
        String normalised = query.trim().toLowerCase(java.util.Locale.ROOT).replaceAll("\\s+", " ");
        return normalised.length() > 512 ? normalised.substring(0, 512) : normalised;
    }

    /**
     * Normalises a point into a cache key.
     *
     * <p>Rounded to five decimals — about a metre — which is what makes a reverse cache worth having
     * at all. A phone's GPS never reports exactly the same coordinate twice, so an unrounded key
     * would miss on every single request while filling the table with near-duplicates. One metre is
     * far below the accuracy of the fix that produced the point, so the rounding cannot change which
     * address comes back.
     */
    public static String keyFor(GeoPoint point) {
        return point.latitude().setScale(5, java.math.RoundingMode.HALF_UP).toPlainString()
                + "," + point.longitude().setScale(5, java.math.RoundingMode.HALF_UP).toPlainString();
    }

    public boolean isFreshAt(Instant now, Duration ttl) {
        return fetchedAt.plus(ttl).isAfter(now);
    }

    /** Records a use. Cheap enough to be worth knowing before anyone signs a per-request contract. */
    public void recordHit() {
        this.hitCount++;
    }

    /** Replaces a stale answer in place, so a re-fetch reuses the row rather than racing on the key. */
    public void refresh(String payload, Instant fetchedAt) {
        this.payload = payload;
        this.fetchedAt = fetchedAt;
        this.hitCount = 0;
    }

    public UUID getId() {
        return id;
    }

    public String getProvider() {
        return provider;
    }

    public Lookup getLookup() {
        return lookup;
    }

    public String getCacheKey() {
        return cacheKey;
    }

    public String getPayload() {
        return payload;
    }

    public Instant getFetchedAt() {
        return fetchedAt;
    }

    public int getHitCount() {
        return hitCount;
    }
}
