package com.delivery.product.service;

import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.TimeUnit;
import java.util.function.LongSupplier;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

/**
 * How often one account may run the customer item search: a burst, then a steady rate.
 *
 * <p>Each search reads the trigram index and ranks what it finds, which costs the database tens of
 * milliseconds for a common word, and the service has ten connections for everything it does. The
 * gateway's limit is per address, 20 a second, which one script behind one address can spend on
 * searches alone. This limit is per signed-in account, which is who the search is for: the controller
 * asks it first, and a refused search reaches no query.
 *
 * <p>The budget is a person's: Home searches as the customer types, 350 ms after they pause, and the
 * results screen pages as they scroll, so {@code per-account-burst} (15) searches may come at once and
 * then {@code per-account-per-minute} (60), one a second. Past that the answer is 429 with
 * {@code SEARCH_RATE_LIMITED} and how many seconds until the next search is allowed.
 *
 * <p>The generic cell rate algorithm, which is a token bucket kept as one number per account: the
 * moment the account's bucket will be full again. A search is allowed while that moment is less than
 * a burst's worth of searches ahead of now, and moves it one interval on. One {@code long} per account
 * and one atomic update per search, where a bucket would need a count and a clock kept in step.
 *
 * <p><strong>Scope.</strong> One JVM, like {@link com.delivery.product.geocoding.MinIntervalRateLimiter}:
 * the service runs one replica (deploy/k3s/base/services.yaml), so this is the whole limit; with more,
 * each would allow its own share. In memory rather than in a table, because a row written per search
 * would cost the database more than the search it guards. Accounts whose bucket is full again are
 * forgotten, so the map holds only accounts that searched in the last few seconds.
 *
 * <p>The clock is injected, as in {@code MinIntervalRateLimiter}, so a test can assert the exact
 * answer for a sequence of searches without sleeping.
 */
@Component
public class ItemSearchThrottle {

    /** Refused because the account searched too often; 429. */
    public static final String SEARCH_RATE_LIMITED = "SEARCH_RATE_LIMITED";

    /** How many accounts are kept before the idle ones are swept. */
    static final int SWEEP_ABOVE = 10_000;

    /** The longest a sweep is put off once the map is past {@link #SWEEP_ABOVE}. */
    private static final long SWEEP_EVERY_NANOS = TimeUnit.SECONDS.toNanos(10);

    private final long intervalNanos;
    private final long toleranceNanos;
    private final LongSupplier nanoClock;

    /** Per account: the moment its bucket is full again, on the {@code nanoClock}'s timeline. */
    private final ConcurrentHashMap<String, Long> fullAt = new ConcurrentHashMap<>();

    private volatile long lastSweepNanos;

    @Autowired
    public ItemSearchThrottle(
            @Value("${delivery.catalog.item-search.per-account-burst:15}") int burst,
            @Value("${delivery.catalog.item-search.per-account-per-minute:60}") int perMinute) {
        this(burst, perMinute, System::nanoTime);
    }

    ItemSearchThrottle(int burst, int perMinute, LongSupplier nanoClock) {
        // Clamped rather than trusted: a zero in the configuration must not refuse every search, nor
        // divide by zero.
        int searches = Math.max(burst, 1);
        this.intervalNanos = TimeUnit.MINUTES.toNanos(1) / Math.max(perMinute, 1);
        this.toleranceNanos = (searches - 1) * intervalNanos;
        this.nanoClock = nanoClock;
        this.lastSweepNanos = nanoClock.getAsLong();
    }

    /**
     * Counts one search by {@code accountId}, or refuses it.
     *
     * @throws SearchThrottledException when the account has searched its burst and must wait
     */
    public void acquire(String accountId) {
        long now = nanoClock.getAsLong();
        sweepIfCrowded(now);
        long[] waitNanos = {0L};
        fullAt.compute(accountId, (id, full) -> {
            // Differences, not magnitudes: nanoTime has an arbitrary origin and can wrap.
            long start = full == null || full - now < 0 ? now : full;
            long ahead = start - now;
            if (ahead > toleranceNanos) {
                waitNanos[0] = ahead - toleranceNanos;
                return full;
            }
            return start + intervalNanos;
        });
        if (waitNanos[0] > 0) {
            long seconds = Math.max(1L, (waitNanos[0] + TimeUnit.SECONDS.toNanos(1) - 1)
                    / TimeUnit.SECONDS.toNanos(1));
            throw new SearchThrottledException(seconds);
        }
    }

    /** How many accounts are remembered; for tests. */
    int remembered() {
        return fullAt.size();
    }

    /** Forgets the accounts whose bucket is full again: a new search starts them afresh, just the same. */
    private void sweepIfCrowded(long now) {
        if (fullAt.size() <= SWEEP_ABOVE || now - lastSweepNanos < SWEEP_EVERY_NANOS) {
            return;
        }
        lastSweepNanos = now;
        fullAt.values().removeIf(full -> full - now <= 0);
    }

    /** Too many searches from one account; 429 with how long to wait. */
    public static class SearchThrottledException extends RuntimeException {

        private final long retryAfterSeconds;

        public SearchThrottledException(long retryAfterSeconds) {
            super("Too many searches just now. Wait a moment and search again.");
            this.retryAfterSeconds = retryAfterSeconds;
        }

        public long getRetryAfterSeconds() {
            return retryAfterSeconds;
        }

        public String getCode() {
            return SEARCH_RATE_LIMITED;
        }
    }
}
