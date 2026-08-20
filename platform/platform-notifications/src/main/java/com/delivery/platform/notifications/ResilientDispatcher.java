package com.delivery.platform.notifications;

import java.time.Duration;
import java.util.function.Function;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import io.github.resilience4j.circuitbreaker.CallNotPermittedException;
import io.github.resilience4j.circuitbreaker.CircuitBreaker;
import io.github.resilience4j.circuitbreaker.CircuitBreakerConfig;
import io.github.resilience4j.retry.Retry;
import io.github.resilience4j.retry.RetryConfig;

/**
 * The resilience wrapper every connector puts around its outbound provider call (Section 7 and 10).
 *
 * <p>Three behaviours, all required by the brief:
 *
 * <ul>
 *   <li><strong>Circuit breaker</strong> — once a provider is failing, stop calling it. Without
 *       this, a dead provider means every message spends the full timeout before failing, and the
 *       connector's threads fill with calls that were never going to succeed.</li>
 *   <li><strong>Retry with backoff</strong> — but only for outcomes classified retryable. Retrying
 *       an invalid phone number wastes the budget and, with a paid vendor, money.</li>
 *   <li><strong>Dead letter</strong> — anything that exhausts retries is handed to the caller's
 *       dead-letter handler rather than dropped, so an operator can find it.</li>
 * </ul>
 *
 * <p>Deliberately a plain object rather than annotations: a connector creates one per provider, so
 * a Twilio outage opens Twilio's breaker without affecting the dev-passthrough path.
 */
public class ResilientDispatcher {

    private static final Logger log = LoggerFactory.getLogger(ResilientDispatcher.class);

    private final CircuitBreaker circuitBreaker;
    private final Retry retry;
    private final String name;

    public ResilientDispatcher(String name, int maxAttempts, Duration initialBackoff,
                               float failureRateThreshold, Duration openStateDuration) {
        this.name = name;

        this.circuitBreaker = CircuitBreaker.of(name, CircuitBreakerConfig.custom()
                .failureRateThreshold(failureRateThreshold)
                .waitDurationInOpenState(openStateDuration)
                // Enough calls to judge a failure rate on, but small enough to react quickly.
                .slidingWindowSize(20)
                .minimumNumberOfCalls(5)
                .permittedNumberOfCallsInHalfOpenState(3)
                .build());

        this.retry = Retry.of(name, RetryConfig.<DeliveryOutcome>custom()
                .maxAttempts(maxAttempts)
                .intervalFunction(io.github.resilience4j.core.IntervalFunction
                        .ofExponentialBackoff(initialBackoff, 2.0))
                // Retry on the OUTCOME, not just on thrown exceptions: a provider returning
                // "rate limited" as a 429 body is a retryable failure that never throws.
                .retryOnResult(outcome -> outcome != null && !outcome.success() && outcome.retryable())
                .build());

        circuitBreaker.getEventPublisher().onStateTransition(event ->
                log.warn("Circuit breaker {} {} -> {}", name,
                        event.getStateTransition().getFromState(),
                        event.getStateTransition().getToState()));
    }

    /**
     * Runs the provider call with retry and the breaker in front of it.
     *
     * @param command      what to send; its notificationId is the idempotency key
     * @param send         the provider call
     * @param onDeadLetter invoked when the message is permanently undeliverable or the breaker is
     *                     open — must not throw
     */
    public <T extends IdempotentCommand> DeliveryOutcome dispatch(
            T command,
            Function<T, DeliveryOutcome> send,
            java.util.function.BiConsumer<T, String> onDeadLetter) {
        try {
            DeliveryOutcome outcome = Retry.decorateFunction(retry,
                    CircuitBreaker.decorateFunction(circuitBreaker, send)).apply(command);

            if (!outcome.success()) {
                // Reached only when retries are exhausted or the failure was permanent.
                log.warn("{} could not deliver {}: {}", name, command.idempotencyKey(),
                        outcome.failureReason());
                onDeadLetter.accept(command, outcome.failureReason());
            }
            return outcome;

        } catch (CallNotPermittedException e) {
            // Breaker open: the provider is known-bad, so this was not even attempted. Dead-letter
            // it rather than pretending it failed on its own merits.
            log.warn("{} circuit open, {} not attempted", name, command.idempotencyKey());
            onDeadLetter.accept(command, "provider circuit open");
            return DeliveryOutcome.transientFailure("provider circuit open");

        } catch (Exception e) {
            log.error("{} threw dispatching {}", name, command.idempotencyKey(), e);
            onDeadLetter.accept(command, e.getMessage());
            return DeliveryOutcome.transientFailure(e.getMessage());
        }
    }

    public String circuitState() {
        return circuitBreaker.getState().name();
    }
}
