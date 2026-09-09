package com.delivery.platform.notifications;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.atomic.AtomicInteger;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

/**
 * The breaker in front of every provider call.
 *
 * <p>It could never open. resilience4j counts a call as failed only when the decorated function
 * throws, and every function this class is given is written never to throw — the connector clients
 * catch {@code Exception} and return a {@link DeliveryOutcome} instead. So the breaker recorded an
 * unbroken run of successes while a provider failed message after message: it read {@code CLOSED}
 * after seventy permanent failures in a day, and every one of those messages spent the full
 * timeout on a call that was never going to succeed. The retry layer worked throughout, on these
 * same outcomes, which is exactly why nobody noticed.
 *
 * <p>The tests below fix both halves of the rule: a failing provider must trip the breaker, and a
 * stream of messages the provider is right to reject must not.
 */
@DisplayName("the provider circuit breaker")
class ResilientDispatcherTest {

    /** A command with a stable idempotency key; nothing here cares about its contents. */
    private record Message(String idempotencyKey) implements IdempotentCommand {
    }

    private final List<String> deadLettered = new ArrayList<>();

    private void deadLetter(Message command, String reason) {
        deadLettered.add(command.idempotencyKey() + ": " + reason);
    }

    /**
     * A dispatcher that opens on the first failure it sees, once it has seen enough calls to judge.
     *
     * <p>One attempt per dispatch, so each call to {@link ResilientDispatcher#dispatch} records
     * exactly one result and the arithmetic below is legible.
     */
    private ResilientDispatcher dispatcher() {
        return new ResilientDispatcher("test-provider", 1, Duration.ofMillis(1),
                50f, Duration.ofMinutes(1));
    }

    private static DeliveryOutcome sendFailing(Message ignored) {
        return DeliveryOutcome.transientFailure("provider is down");
    }

    @Nested
    @DisplayName("when the provider is failing")
    class ProviderDown {

        @Test
        void opens_once_the_failure_rate_is_clear() {
            ResilientDispatcher dispatcher = dispatcher();

            assertThat(dispatcher.circuitState()).isEqualTo("CLOSED");
            for (int i = 0; i < 10; i++) {
                dispatcher.dispatch(new Message("msg-" + i),
                        ResilientDispatcherTest::sendFailing,
                        ResilientDispatcherTest.this::deadLetter);
            }

            // The whole point of the breaker: stop calling a provider that is not answering.
            assertThat(dispatcher.circuitState()).isEqualTo("OPEN");
        }

        @Test
        void then_stops_calling_it_at_all() {
            ResilientDispatcher dispatcher = dispatcher();
            AtomicInteger calls = new AtomicInteger();

            for (int i = 0; i < 20; i++) {
                dispatcher.dispatch(new Message("msg-" + i), command -> {
                    calls.incrementAndGet();
                    return DeliveryOutcome.transientFailure("provider is down");
                }, ResilientDispatcherTest.this::deadLetter);
            }

            // Fewer calls than messages: the ones after the breaker opened were never attempted,
            // which is the timeout-per-message this exists to stop spending.
            assertThat(calls.get()).isLessThan(20);
            // And none of them was silently dropped.
            assertThat(deadLettered).hasSize(20);
            assertThat(deadLettered).anyMatch(entry -> entry.endsWith("provider circuit open"));
        }
    }

    @Nested
    @DisplayName("when the provider is healthy")
    class ProviderHealthy {

        @Test
        void stays_closed() {
            ResilientDispatcher dispatcher = dispatcher();

            for (int i = 0; i < 20; i++) {
                dispatcher.dispatch(new Message("msg-" + i),
                        command -> DeliveryOutcome.sent("test-provider", "ref-" + command.idempotencyKey()),
                        ResilientDispatcherTest.this::deadLetter);
            }

            assertThat(dispatcher.circuitState()).isEqualTo("CLOSED");
            assertThat(deadLettered).isEmpty();
        }

        /**
         * A rejected recipient says something about the message, not about the provider.
         *
         * <p>Counting these would let a batch of bad phone numbers take a perfectly healthy
         * provider out of service for everybody else — and the messages behind them would be
         * dead-lettered as "circuit open" when nothing was ever wrong with the connection.
         */
        @Test
        void a_run_of_permanently_bad_messages_does_not_trip_it() {
            ResilientDispatcher dispatcher = dispatcher();

            for (int i = 0; i < 20; i++) {
                dispatcher.dispatch(new Message("msg-" + i),
                        command -> DeliveryOutcome.permanentFailure("not a valid number"),
                        ResilientDispatcherTest.this::deadLetter);
            }

            assertThat(dispatcher.circuitState()).isEqualTo("CLOSED");
            // Still every one of them parked for an operator, which is the other half of the rule.
            assertThat(deadLettered).hasSize(20);
        }
    }
}
