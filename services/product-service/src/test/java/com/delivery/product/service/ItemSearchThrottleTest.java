package com.delivery.product.service;

import java.util.concurrent.TimeUnit;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import com.delivery.product.service.ItemSearchThrottle.SearchThrottledException;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.assertj.core.api.Assertions.assertThatCode;

/**
 * How often one account may search items ({@link ItemSearchThrottle}), on a clock the test moves, so
 * every answer is exact and nothing sleeps.
 */
@DisplayName("the item search's limit per account")
class ItemSearchThrottleTest {

    private static final long SECOND = TimeUnit.SECONDS.toNanos(1);

    /** A clock that stands still until the test moves it. */
    private long now = 7 * SECOND;

    private ItemSearchThrottle throttle(int burst, int perMinute) {
        return new ItemSearchThrottle(burst, perMinute, () -> now);
    }

    private static long refusedFor(ItemSearchThrottle throttle, String account) {
        try {
            throttle.acquire(account);
        } catch (SearchThrottledException e) {
            assertThat(e.getCode()).isEqualTo(ItemSearchThrottle.SEARCH_RATE_LIMITED);
            return e.getRetryAfterSeconds();
        }
        throw new AssertionError("expected " + account + " to be refused");
    }

    @Test
    @DisplayName("a burst goes through at once, the next waits one interval, then one more goes through")
    void a_burst_then_the_steady_rate() {
        ItemSearchThrottle throttle = throttle(15, 60);
        for (int i = 0; i < 15; i++) {
            throttle.acquire("customer");
        }

        assertThat(refusedFor(throttle, "customer")).isEqualTo(1);

        now += SECOND - 1;
        assertThat(refusedFor(throttle, "customer")).isEqualTo(1);
        now += 1;
        assertThatCode(() -> throttle.acquire("customer")).doesNotThrowAnyException();
        assertThat(refusedFor(throttle, "customer")).isEqualTo(1);
    }

    @Test
    @DisplayName("an account that stopped searching gets its whole burst back, and no more")
    void an_idle_account_refills_to_its_burst() {
        ItemSearchThrottle throttle = throttle(3, 60);
        for (int i = 0; i < 3; i++) {
            throttle.acquire("customer");
        }

        now += 60 * SECOND;
        for (int i = 0; i < 3; i++) {
            throttle.acquire("customer");
        }
        assertThat(refusedFor(throttle, "customer")).isEqualTo(1);
    }

    @Test
    @DisplayName("each account has its own budget")
    void accounts_are_counted_apart() {
        ItemSearchThrottle throttle = throttle(2, 60);
        throttle.acquire("one");
        throttle.acquire("one");
        refusedFor(throttle, "one");

        assertThatCode(() -> throttle.acquire("two")).doesNotThrowAnyException();
    }

    @Test
    @DisplayName("the wait is whole seconds, rounded up, at a slow rate too")
    void the_wait_is_rounded_up_to_whole_seconds() {
        ItemSearchThrottle throttle = throttle(1, 1);
        throttle.acquire("customer");

        assertThat(refusedFor(throttle, "customer")).isEqualTo(60);
        now += 59 * SECOND + 1;
        assertThat(refusedFor(throttle, "customer")).isEqualTo(1);
    }

    @Test
    @DisplayName("a refused search is not counted, so waiting as told is enough")
    void a_refused_search_costs_nothing() {
        ItemSearchThrottle throttle = throttle(1, 60);
        throttle.acquire("customer");
        for (int i = 0; i < 10; i++) {
            refusedFor(throttle, "customer");
        }

        now += SECOND;
        assertThatCode(() -> throttle.acquire("customer")).doesNotThrowAnyException();
    }

    @Test
    @DisplayName("a setting of zero allows one search at a time, one a minute, rather than none or a crash")
    void a_setting_of_zero_is_clamped() {
        ItemSearchThrottle throttle = throttle(0, 0);

        assertThatCode(() -> throttle.acquire("customer")).doesNotThrowAnyException();
        assertThat(refusedFor(throttle, "customer")).isEqualTo(60);
    }

    @Test
    @DisplayName("the clock's wrap past its largest value changes nothing")
    void the_clock_may_wrap() {
        now = Long.MAX_VALUE - SECOND / 2;
        ItemSearchThrottle throttle = throttle(2, 60);
        throttle.acquire("customer");
        throttle.acquire("customer");
        assertThat(refusedFor(throttle, "customer")).isEqualTo(1);

        now += SECOND;
        assertThatCode(() -> throttle.acquire("customer")).doesNotThrowAnyException();
    }

    @Test
    @DisplayName("accounts whose budget is whole again are forgotten once many are remembered")
    void idle_accounts_are_forgotten() {
        ItemSearchThrottle throttle = throttle(15, 60);
        for (int i = 0; i <= ItemSearchThrottle.SWEEP_ABOVE; i++) {
            throttle.acquire("customer-" + i);
        }
        assertThat(throttle.remembered()).isEqualTo(ItemSearchThrottle.SWEEP_ABOVE + 1);

        now += 11 * SECOND;
        throttle.acquire("still-searching");

        assertThat(throttle.remembered()).isEqualTo(1);
        // Forgetting gives nobody more than a burst: a forgotten account starts full, as it was.
        for (int i = 0; i < 14; i++) {
            throttle.acquire("customer-0");
        }
        throttle.acquire("customer-0");
        assertThatThrownBy(() -> throttle.acquire("customer-0")).isInstanceOf(SearchThrottledException.class);
    }
}
