package com.delivery.product.shoppage;

import java.util.concurrent.ConcurrentHashMap;
import java.util.function.LongSupplier;
import java.util.function.Supplier;

/**
 * What this page has already built, kept for as long as the response it came in said it was good
 * for.
 *
 * <p><strong>Why there is a cache here at all.</strong> Every other surface on this platform is
 * asked for by an app the platform wrote, behind a token, at a pace a person sets. This one is a
 * link pasted into a WhatsApp status: it is fetched by everyone in the group at once, re-fetched by
 * every chat app that draws a preview card, and walked by crawlers. The answer does not depend on
 * who is asking — that is the whole design — so the second reader inside the same window can have
 * the first reader's bytes, and the origin is asked once instead of once per reader.
 *
 * <p>The window is not a new promise: it is the {@code max-age} already on the response. A page
 * says five minutes, so a merchant who corrects a price still sees it within the five minutes they
 * were already told about, whether the copy that was served came from a CDN, a phone or from here.
 * Nothing is invalidated on a write for the same reason — a second mechanism could only disagree
 * with the header.
 *
 * <p>In this JVM and no further, like {@code ItemSearchThrottle} and for the same reason: the
 * service runs one replica (deploy/k3s/base/services.yaml), and a shared cache would be a second
 * thing to run, to secure and to explain, to save a query this one already saves.
 *
 * <p>Bounded, because the pod has 512 MiB and a cache that grows with the number of distinct slugs
 * anybody asks for is a memory leak with a nice name. Past {@link #maxEntries} the expired entries
 * go; if that is not enough the whole map does, which costs one rebuild per key and cannot be
 * turned into a way to make this service run out of memory.
 *
 * <p>The clock is a {@link LongSupplier} of nanoseconds so a test can step over an expiry instead
 * of sleeping through one, exactly as {@code ItemSearchThrottle} does.
 *
 * @param <V> what is memoised — rendered bytes, in every use here
 */
final class ShopPageCache<V> {

    private final long ttlNanos;
    private final int maxEntries;
    private final LongSupplier nanoClock;
    private final ConcurrentHashMap<String, Entry<V>> entries = new ConcurrentHashMap<>();

    ShopPageCache(java.time.Duration ttl, int maxEntries, LongSupplier nanoClock) {
        this.ttlNanos = ttl.toNanos();
        this.maxEntries = Math.max(maxEntries, 1);
        this.nanoClock = nanoClock;
    }

    /**
     * The memoised value for {@code key}, building it if this is the first ask or the last one has
     * expired.
     *
     * <p>The rebuild happens inside {@link ConcurrentHashMap#compute}, so a hundred readers arriving
     * at a cold key build it <em>once</em> and the other ninety-nine wait for that one — which is
     * the case this exists for. A flood is exactly when a per-request rebuild would hurt, and a
     * cache that let every reader in a burst through would help only the ones who came late.
     *
     * <p>A build that throws stores nothing and is retried by the next reader. On this page that is
     * {@code ShopPageNotFoundException}, and a refusal is not worth remembering: it costs one
     * indexed lookup and a shop that goes live this afternoon must not be missing until an entry
     * ages out.
     */
    V get(String key, Supplier<V> build) {
        long now = nanoClock.getAsLong();
        Entry<V> hit = entries.get(key);
        // Differences, not magnitudes: nanoTime has an arbitrary origin and can wrap.
        if (hit != null && now - hit.expiresAt() < 0) {
            return hit.value();
        }
        evictIfCrowded(now);
        return entries.compute(key, (ignored, existing) -> {
            long at = nanoClock.getAsLong();
            if (existing != null && at - existing.expiresAt() < 0) {
                // Somebody else rebuilt it while this thread waited for the entry.
                return existing;
            }
            return new Entry<>(build.get(), at + ttlNanos);
        }).value();
    }

    /** How many entries are held; for tests. */
    int size() {
        return entries.size();
    }

    private void evictIfCrowded(long now) {
        if (entries.size() < maxEntries) {
            return;
        }
        entries.values().removeIf(entry -> now - entry.expiresAt() >= 0);
        if (entries.size() >= maxEntries) {
            entries.clear();
        }
    }

    /** One memoised value and the moment it stops being current, on the {@code nanoClock}'s line. */
    private record Entry<V>(V value, long expiresAt) {
    }
}
