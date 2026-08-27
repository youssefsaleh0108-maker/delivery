package com.delivery.product.geocoding;

import java.time.Duration;
import java.util.concurrent.TimeUnit;
import java.util.function.LongSupplier;

/**
 * Lets at most one call through per interval, making every other caller wait its turn.
 *
 * <p>Written for Nominatim, whose usage policy states an absolute maximum of one request per second
 * to the public endpoint and warns that exceeding it gets the application blocked. That is not a
 * performance guideline — it is the condition on which the service is free — so it is enforced
 * here rather than left to whoever calls the client.
 *
 * <p>A minimum-interval gate rather than a token bucket, deliberately. A bucket with a capacity of
 * one and a refill of one per second permits a burst after any idle period, which is exactly the
 * pattern that trips an abuse detector: a service that has been quiet for a minute would fire a
 * minute's worth of accumulated requests the instant a merchant opens the address picker. This
 * grants the next permit at {@code lastPermit + interval} and never accumulates credit, so the
 * outbound rate is bounded even after a long idle stretch.
 *
 * <p>Fair by construction rather than by a fairness flag: each caller reserves its slot under the
 * lock, releases the lock, and then sleeps. Holding the lock across the sleep would serialise the
 * waiting itself and turn N concurrent callers into N sequential sleeps of a full interval each.
 *
 * <p><strong>Scope.</strong> This bounds one JVM. Nominatim's limit is per application, so running
 * two replicas of this service against the public endpoint would exceed it — see the geocoding
 * notes in the service README and {@link NominatimGeocodingProvider}. The cache in front of it is
 * what keeps real traffic far below the limit; the limiter is the backstop.
 */
public class MinIntervalRateLimiter {

    private final long intervalNanos;
    private final LongSupplier nanoClock;
    private final Sleeper sleeper;

    /**
     * The moment the next call may proceed, on the {@code nanoClock}'s timeline.
     *
     * <p>Guarded by {@code this}. Uninitialised to {@code Long.MIN_VALUE} rather than to the clock's
     * value at construction so the very first call never waits — a limiter that made a freshly
     * started service pause before its first request would add a second to a cold start for nothing.
     */
    private long nextPermitAtNanos = Long.MIN_VALUE;

    /**
     * The seam that makes this testable.
     *
     * <p>A rate limiter whose only evidence of working is that the wall clock moved is a rate
     * limiter nobody can assert on without a slow, flaky test. With the clock and the sleep injected,
     * a test can prove the exact wait this grants for a given sequence of calls, in microseconds.
     */
    @FunctionalInterface
    public interface Sleeper {
        void sleepNanos(long nanos) throws InterruptedException;

        Sleeper REAL = nanos -> TimeUnit.NANOSECONDS.sleep(nanos);
    }

    public MinIntervalRateLimiter(Duration interval) {
        this(interval, System::nanoTime, Sleeper.REAL);
    }

    public MinIntervalRateLimiter(Duration interval, LongSupplier nanoClock, Sleeper sleeper) {
        if (interval.isNegative()) {
            throw new IllegalArgumentException("A rate-limit interval cannot be negative");
        }
        this.intervalNanos = interval.toNanos();
        this.nanoClock = nanoClock;
        this.sleeper = sleeper;
    }

    /**
     * Blocks until this caller may proceed, then reserves its slot.
     *
     * @return how long this call was made to wait; zero when it went straight through. Returned so
     *         the caller can record it, and so a test can assert on it without timing anything.
     */
    public Duration acquire() {
        long waitNanos = reserve();
        if (waitNanos > 0) {
            try {
                sleeper.sleepNanos(waitNanos);
            } catch (InterruptedException e) {
                // Restore the flag and give up rather than proceeding. Swallowing the interrupt
                // would send the request anyway, which is the one thing a rate limiter must not do.
                Thread.currentThread().interrupt();
                throw new GeocodingException("Interrupted while waiting for a geocoding rate-limit slot", e);
            }
        }
        return Duration.ofNanos(waitNanos);
    }

    /**
     * Claims the next slot and reports the wait it implies.
     *
     * <p>Separate from the sleeping, and synchronized where the sleeping is not, for the reason in
     * the class comment: the reservation must be atomic, the waiting must not be.
     *
     * <p>The comparison is a subtraction rather than {@code now < nextPermitAt} because
     * {@code System.nanoTime} is documented to be an arbitrary origin that can be negative and can
     * wrap; a difference is well defined across the wrap, a magnitude comparison is not.
     */
    private synchronized long reserve() {
        long now = nanoClock.getAsLong();

        if (nextPermitAtNanos == Long.MIN_VALUE || now - nextPermitAtNanos >= 0) {
            nextPermitAtNanos = now + intervalNanos;
            return 0L;
        }

        long waitNanos = nextPermitAtNanos - now;
        // Chained off the reserved slot, not off now(): three callers arriving together must be
        // spaced one interval apart from each other, not all released one interval from now.
        nextPermitAtNanos += intervalNanos;
        return waitNanos;
    }
}
