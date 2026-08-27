package com.delivery.product.domain;

import java.time.Instant;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface GeocodeCacheRepository extends JpaRepository<GeocodeCacheEntry, UUID> {

    Optional<GeocodeCacheEntry> findByProviderAndLookupAndCacheKey(
            String provider, GeocodeCacheEntry.Lookup lookup, String cacheKey);

    /**
     * Drops entries older than a cutoff.
     *
     * <p>By age rather than by the TTL the reader uses, and the two are deliberately different: the
     * reader re-fetches a stale entry in place, so a row only needs deleting once nobody is asking
     * for it any more. Sweeping at the read TTL would delete rows that are about to be refreshed and
     * turn every sweep into a burst of provider traffic — the opposite of what the cache is for.
     */
    @Modifying
    @Query("DELETE FROM GeocodeCacheEntry e WHERE e.fetchedAt < :cutoff")
    int deleteFetchedBefore(@Param("cutoff") Instant cutoff);
}
