package com.delivery.product.shoppage;

import java.time.Duration;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * The memo behind the page, the QR code and the sitemap.
 *
 * <p>Its own test because the thing it promises cannot be seen from outside: two identical pages
 * look the same whether they were rendered twice or once, and the case this exists for — a link
 * that lands in a group chat and is opened by forty people in the same second — is exactly the one
 * a request-at-a-time test never reproduces.
 */
@DisplayName("what the page remembers")
class ShopPageCacheTest {

    /** A hand-wound clock, so an expiry is stepped over rather than slept through. */
    private final AtomicLong nanos = new AtomicLong(1_000_000_000L);

    private <V> ShopPageCache<V> cache(Duration ttl, int maxEntries) {
        return new ShopPageCache<>(ttl, maxEntries, nanos::get);
    }

    @Test
    @DisplayName("it builds once and answers the rest from what it built")
    void buildsOncePerKey() {
        AtomicInteger builds = new AtomicInteger();
        ShopPageCache<String> cache = cache(Duration.ofMinutes(5), 16);

        for (int i = 0; i < 50; i++) {
            assertThat(cache.get("dekkane", () -> "page " + builds.incrementAndGet()))
                    .isEqualTo("page 1");
        }
        assertThat(builds).hasValue(1);
        // A different shop is a different answer, not the first one's.
        assertThat(cache.get("bakery", () -> "page " + builds.incrementAndGet()))
                .isEqualTo("page 2");
    }

    @Test
    @DisplayName("it builds again once the window the response advertised has passed")
    void rebuildsAfterTheWindow() {
        AtomicInteger builds = new AtomicInteger();
        ShopPageCache<String> cache = cache(Duration.ofMinutes(5), 16);

        cache.get("dekkane", () -> "page " + builds.incrementAndGet());
        nanos.addAndGet(Duration.ofMinutes(5).toNanos() - 1);
        cache.get("dekkane", () -> "page " + builds.incrementAndGet());
        assertThat(builds).as("still inside the five minutes the page promised").hasValue(1);

        nanos.addAndGet(2);
        assertThat(cache.get("dekkane", () -> "page " + builds.incrementAndGet()))
                .isEqualTo("page 2");
    }

    @Test
    @DisplayName("forty readers arriving at a cold key build it once, not forty times")
    void afloodBuildsOnce() throws Exception {
        AtomicInteger builds = new AtomicInteger();
        ShopPageCache<String> cache = cache(Duration.ofMinutes(5), 16);
        int readers = 40;
        CountDownLatch together = new CountDownLatch(1);
        CountDownLatch done = new CountDownLatch(readers);
        ExecutorService pool = Executors.newFixedThreadPool(16);

        try {
            for (int i = 0; i < readers; i++) {
                pool.execute(() -> {
                    try {
                        together.await();
                        cache.get("dekkane", () -> {
                            builds.incrementAndGet();
                            // Long enough that every other reader is certainly waiting on this one.
                            sleep(50);
                            return "the page";
                        });
                    } catch (InterruptedException interrupted) {
                        Thread.currentThread().interrupt();
                    } finally {
                        done.countDown();
                    }
                });
            }
            together.countDown();
            assertThat(done.await(30, TimeUnit.SECONDS)).isTrue();
        } finally {
            pool.shutdownNow();
        }

        assertThat(builds).hasValue(1);
    }

    @Test
    @DisplayName("it stops growing: a flood of slugs nobody has cannot fill the pod")
    void staysBounded() {
        ShopPageCache<String> cache = cache(Duration.ofMinutes(5), 8);

        for (int i = 0; i < 500; i++) {
            cache.get("shop-" + i, () -> "page");
        }

        assertThat(cache.size()).isLessThanOrEqualTo(8);
    }

    @Test
    @DisplayName("a refusal is not remembered: a shop that goes live is live at once")
    void doesNotRememberAFailedBuild() {
        AtomicInteger builds = new AtomicInteger();
        ShopPageCache<String> cache = cache(Duration.ofMinutes(5), 16);

        assertThatThrownBy(() -> cache.get("dekkane", () -> {
            builds.incrementAndGet();
            throw new PublicShopPageService.ShopPageNotFoundException();
        })).isInstanceOf(PublicShopPageService.ShopPageNotFoundException.class);

        assertThat(cache.size()).isZero();
        assertThat(cache.get("dekkane", () -> "now it is live")).isEqualTo("now it is live");
        assertThat(builds).hasValue(1);
    }

    private static void sleep(long millis) {
        try {
            Thread.sleep(millis);
        } catch (InterruptedException interrupted) {
            Thread.currentThread().interrupt();
        }
    }
}
