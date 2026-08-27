package com.delivery.product.geocoding;

import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicLong;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * The gate that keeps this service inside OpenStreetMap's one-request-per-second limit.
 *
 * <p>Worth testing properly rather than trusting, because the failure mode is invisible from here:
 * a limiter that quietly permits two calls a second does not break anything locally, it gets the
 * whole deployment blocked by somebody else's server, days later, with no error that points at
 * this class.
 *
 * <p>The clock and the sleep are injected so these assertions are exact and instant. A test that
 * proved the limiter worked by taking three real seconds would be too slow to keep and too coarse
 * to catch an interval that was merely nearly right.
 */
@DisplayName("the geocoder's rate limiter")
class MinIntervalRateLimiterTest {

    private static final Duration ONE_SECOND = Duration.ofSeconds(1);

    /** A clock that only moves when a test says so. */
    private final AtomicLong now = new AtomicLong(1_000_000_000L);

    /** Records what it was asked to wait for instead of actually waiting. */
    private final List<Long> slept = new ArrayList<>();

    private MinIntervalRateLimiter limiter(Duration interval) {
        return new MinIntervalRateLimiter(interval, now::get, slept::add);
    }

    private void advance(Duration by) {
        now.addAndGet(by.toNanos());
    }

    @Nested
    @DisplayName("with calls arriving faster than the limit")
    class TooFast {

        @Test
        void lets_the_first_call_straight_through() {
            // A limiter that made a freshly started service pause before its first request would
            // add a second to every cold start for nothing.
            assertThat(limiter(ONE_SECOND).acquire()).isZero();
            assertThat(slept).isEmpty();
        }

        @Test
        void makes_the_second_call_wait_the_rest_of_the_interval() {
            MinIntervalRateLimiter limiter = limiter(ONE_SECOND);

            limiter.acquire();
            advance(Duration.ofMillis(200));

            assertThat(limiter.acquire()).isEqualTo(Duration.ofMillis(800));
            assertThat(slept).containsExactly(Duration.ofMillis(800).toNanos());
        }

        /**
         * The property that actually matters. Three callers arriving at once must be spaced one
         * interval apart from <em>each other</em>, not all released one interval from now — which
         * is what a naive implementation does, and which sends three requests in the same
         * millisecond a second later.
         */
        @Test
        void spaces_a_burst_out_one_interval_at_a_time() {
            MinIntervalRateLimiter limiter = limiter(ONE_SECOND);

            limiter.acquire();
            Duration second = limiter.acquire();
            Duration third = limiter.acquire();
            Duration fourth = limiter.acquire();

            assertThat(second).isEqualTo(Duration.ofSeconds(1));
            assertThat(third).isEqualTo(Duration.ofSeconds(2));
            assertThat(fourth).isEqualTo(Duration.ofSeconds(3));
        }

        /**
         * Restated as the rule the policy is written in: over any run of calls, the outbound rate
         * never exceeds one per interval.
         */
        @Test
        void never_permits_more_than_one_call_per_interval() {
            MinIntervalRateLimiter limiter = limiter(ONE_SECOND);

            Duration lastWait = Duration.ZERO;
            for (int call = 0; call < 10; call++) {
                lastWait = limiter.acquire();
            }

            // The clock never moves here, so all ten calls arrive at the same instant. The tenth is
            // held back a full nine intervals — which is precisely what "no more than one call per
            // interval" means when they all arrive together.
            assertThat(lastWait).isEqualTo(Duration.ofSeconds(9));
        }
    }

    @Nested
    @DisplayName("with calls arriving slower than the limit")
    class SlowEnough {

        @Test
        void does_not_make_anybody_wait() {
            MinIntervalRateLimiter limiter = limiter(ONE_SECOND);

            limiter.acquire();
            advance(Duration.ofSeconds(3));

            assertThat(limiter.acquire()).isZero();
            assertThat(slept).isEmpty();
        }

        /**
         * No credit accrues over an idle period, and that is deliberate. A token bucket would have
         * banked three seconds' worth of permits here and released a burst the moment somebody
         * opened the address picker — which is exactly the shape an abuse detector looks for.
         */
        @Test
        void banks_no_credit_while_idle() {
            MinIntervalRateLimiter limiter = limiter(ONE_SECOND);

            limiter.acquire();
            advance(Duration.ofSeconds(30));

            assertThat(limiter.acquire()).isZero();
            assertThat(limiter.acquire()).isEqualTo(ONE_SECOND);
            assertThat(limiter.acquire()).isEqualTo(Duration.ofSeconds(2));
        }
    }

    @Nested
    @DisplayName("under concurrent callers")
    class Concurrency {

        /**
         * The limiter is a singleton shared by every request thread, so the reservation has to be
         * atomic. Without that, two threads read the same "next permit" and both go through — the
         * exact doubling the limit forbids.
         */
        @Test
        void hands_out_a_distinct_slot_to_every_thread() throws Exception {
            MinIntervalRateLimiter limiter = limiter(ONE_SECOND);
            int threads = 8;

            ExecutorService pool = Executors.newFixedThreadPool(threads);
            CountDownLatch start = new CountDownLatch(1);
            List<java.util.concurrent.Future<Duration>> waits = new ArrayList<>();

            try {
                for (int i = 0; i < threads; i++) {
                    waits.add(pool.submit(() -> {
                        start.await();
                        return limiter.acquire();
                    }));
                }
                start.countDown();

                List<Duration> granted = new ArrayList<>();
                for (java.util.concurrent.Future<Duration> wait : waits) {
                    granted.add(wait.get(5, TimeUnit.SECONDS));
                }

                // Every thread got a different wait, one interval apart: 0s, 1s, 2s ... 7s. Any
                // duplicate would be two requests permitted for the same slot.
                assertThat(granted).doesNotHaveDuplicates().hasSize(threads);
                assertThat(granted).allSatisfy(
                        wait -> assertThat(wait.toNanos() % ONE_SECOND.toNanos()).isZero());

            } finally {
                pool.shutdownNow();
            }
        }
    }

    @Nested
    @DisplayName("when interrupted while waiting")
    class Interrupted {

        /**
         * Giving up is the right answer. Swallowing the interrupt and proceeding would send the
         * request anyway, which is the one thing a rate limiter must never do.
         */
        @Test
        void gives_up_rather_than_sending_the_request_anyway() {
            MinIntervalRateLimiter limiter = new MinIntervalRateLimiter(
                    ONE_SECOND,
                    now::get,
                    nanos -> {
                        throw new InterruptedException("shutting down");
                    });

            limiter.acquire();

            try {
                org.assertj.core.api.Assertions.assertThatThrownBy(limiter::acquire)
                        .isInstanceOf(GeocodingException.class);
                assertThat(Thread.currentThread().isInterrupted()).isTrue();
            } finally {
                // Clear it so the flag does not leak into whatever runs next on this thread.
                Thread.interrupted();
            }
        }
    }
}
