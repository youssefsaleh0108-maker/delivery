package com.delivery.platform.notifications;

/**
 * Anything a connector sends outward exactly once, however many times it is asked to.
 *
 * <p>Exists so {@link ResilientDispatcher} and {@link DeadLetterPublisher} can serve more than one
 * kind of payload. A notification command and a bank posting need identical treatment — breaker,
 * retry on retryable outcomes only, dead-letter what is left — and the only thing that machinery
 * needs from the payload is a stable key to log and correlate on.
 *
 * <p>The key must be stable across retries and redeliveries. That is the whole guarantee: it is
 * what makes a retried SMS one SMS, and a retried debit one debit.
 */
public interface IdempotentCommand {

    /** Stable across every retry and redelivery of this same logical operation. */
    String idempotencyKey();

    /** For log correlation across services; may be null outside a request-triggered flow. */
    default String correlationId() {
        return null;
    }
}
