package com.delivery.platform.outbox;

import java.time.Duration;
import java.time.Instant;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * The retry schedule of a single outbox row.
 *
 * <p>The property under test is the one that separates "the broker is restarting" from "this
 * message is poison". Both look identical to the relay — a publish that threw — and the only thing
 * that tells them apart is how long the relay is willing to keep trying. Before the backoff existed
 * that window was {@code pollInterval * maxAttempts}, eleven seconds with the shipped defaults,
 * which is shorter than a broker restart: an ordinary restart dead-lettered every pending event in
 * every service and left the recovery to an operator.
 */
class OutboxEventTest {

    private static final Duration BASE = Duration.ofSeconds(10);
    private static final Duration CAP = Duration.ofMinutes(5);

    private static OutboxEvent event() {
        return new OutboxEvent("Order", "order-1", "order.placed", "{}", "corr-1");
    }

    @Nested
    @DisplayName("a freshly recorded event")
    class WhenRecorded {

        @Test
        void starts_pending_with_no_attempts() {
            OutboxEvent event = event();

            assertThat(event.getStatus()).isEqualTo(OutboxEvent.Status.PENDING);
            assertThat(event.getAttempts()).isZero();
            assertThat(event.getLastError()).isNull();
            assertThat(event.getPublishedAt()).isNull();
        }

        /**
         * The first publish must not be delayed. Backoff is a response to failure; a new event
         * waiting even one interval would add latency to every notification on the platform.
         */
        @Test
        void is_due_immediately() {
            OutboxEvent event = event();

            assertThat(event.getNextAttemptAt()).isEqualTo(event.getCreatedAt());
            assertThat(event.getNextAttemptAt()).isBeforeOrEqualTo(Instant.now());
        }

        @Test
        void carries_the_correlation_id_it_was_recorded_with() {
            assertThat(event().getCorrelationId()).isEqualTo("corr-1");
        }
    }

    @Nested
    @DisplayName("publishing")
    class Publishing {

        @Test
        void marks_published_and_stamps_the_time() {
            OutboxEvent event = event();

            event.markPublished();

            assertThat(event.getStatus()).isEqualTo(OutboxEvent.Status.PUBLISHED);
            assertThat(event.getPublishedAt()).isNotNull();
        }

        /** A row that failed and then succeeded should not keep the stale error on it. */
        @Test
        void clears_the_error_left_by_an_earlier_failure() {
            OutboxEvent event = event();
            event.markFailed("broker unreachable", 8, BASE, CAP);
            assertThat(event.getLastError()).isNotNull();

            event.markPublished();

            assertThat(event.getLastError()).isNull();
        }
    }

    @Nested
    @DisplayName("failing")
    class Failing {

        @Test
        void counts_the_attempt_and_keeps_the_error() {
            OutboxEvent event = event();

            event.markFailed("connection refused", 8, BASE, CAP);

            assertThat(event.getAttempts()).isEqualTo(1);
            assertThat(event.getLastError()).isEqualTo("connection refused");
            assertThat(event.getStatus()).isEqualTo(OutboxEvent.Status.PENDING);
        }

        /**
         * The whole point. A failed row must become ineligible for a while, otherwise the next tick
         * re-claims it and the attempt budget is spent in seconds.
         */
        @Test
        void pushes_the_next_attempt_into_the_future() {
            OutboxEvent event = event();

            event.markFailed("broker unreachable", 8, BASE, CAP);

            assertThat(event.getNextAttemptAt()).isAfter(Instant.now().plusSeconds(8));
        }

        @Test
        void dead_letters_once_the_attempts_are_exhausted() {
            OutboxEvent event = event();

            for (int i = 0; i < 3; i++) {
                event.markFailed("still failing", 3, BASE, CAP);
            }

            assertThat(event.getStatus()).isEqualTo(OutboxEvent.Status.DEAD_LETTERED);
            assertThat(event.getAttempts()).isEqualTo(3);
        }

        /** Dead-lettered is terminal and needs an operator — it must not be re-claimed by a tick. */
        @Test
        void a_dead_lettered_row_is_not_rescheduled() {
            OutboxEvent event = event();
            event.markFailed("fatal", 1, BASE, CAP);

            assertThat(event.getStatus()).isEqualTo(OutboxEvent.Status.DEAD_LETTERED);
            assertThat(event.getNextAttemptAt()).isEqualTo(event.getCreatedAt());
        }
    }

    @Nested
    @DisplayName("the backoff curve")
    class Backoff {

        @Test
        void doubles_on_each_attempt() {
            assertThat(OutboxEvent.backoffFor(1, BASE, CAP)).isEqualTo(Duration.ofSeconds(10));
            assertThat(OutboxEvent.backoffFor(2, BASE, CAP)).isEqualTo(Duration.ofSeconds(20));
            assertThat(OutboxEvent.backoffFor(3, BASE, CAP)).isEqualTo(Duration.ofSeconds(40));
            assertThat(OutboxEvent.backoffFor(4, BASE, CAP)).isEqualTo(Duration.ofSeconds(80));
        }

        @Test
        void is_capped_so_a_long_outage_still_retries_steadily() {
            assertThat(OutboxEvent.backoffFor(10, BASE, CAP)).isEqualTo(CAP);
            assertThat(OutboxEvent.backoffFor(31, BASE, CAP)).isEqualTo(CAP);
        }

        /**
         * {@code Duration.multipliedBy} overflows silently into a negative duration, which would
         * schedule the retry in the past and put the relay straight back to retrying every tick —
         * the exact behaviour the backoff exists to remove.
         */
        @Test
        void does_not_overflow_into_a_negative_delay_at_absurd_attempt_counts() {
            assertThat(OutboxEvent.backoffFor(32, BASE, CAP)).isEqualTo(CAP);
            assertThat(OutboxEvent.backoffFor(64, BASE, CAP)).isEqualTo(CAP);
            assertThat(OutboxEvent.backoffFor(Integer.MAX_VALUE, BASE, CAP)).isEqualTo(CAP);
        }

        /**
         * The number that matters operationally: the default schedule has to outlast a broker
         * restart. Eight attempts at 10s doubling to a 5min cap spans about twenty minutes.
         */
        @Test
        void the_shipped_defaults_tolerate_a_broker_restart() {
            OutboxProperties defaults = new OutboxProperties();

            Duration total = Duration.ZERO;
            for (int attempt = 1; attempt < defaults.getMaxAttempts(); attempt++) {
                total = total.plus(OutboxEvent.backoffFor(attempt,
                        defaults.getRetryBackoff(), defaults.getMaxRetryBackoff()));
            }

            assertThat(total).isGreaterThan(Duration.ofMinutes(15));
        }
    }
}
