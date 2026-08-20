package com.delivery.platform.notifications;

/**
 * What a provider did with a message.
 *
 * <p>The distinction that matters is {@link #retryable}: a rate limit or a 5xx is worth another
 * attempt, while an invalid phone number never will be. Retrying the latter burns the retry budget
 * and, for paid providers, money — so the connector must classify rather than treat every failure
 * the same.
 *
 * <p>{@code provider} travels with the outcome because the worker that reports the result back to
 * Notifications Manager does not otherwise know which vendor the connector actually used — the
 * active provider is a runtime setting the connector owns (Section 8). Without it, "which vendor
 * did this go through" is unanswerable from the notification log, which is the one place someone
 * looks after a switch.
 */
public record DeliveryOutcome(
        boolean success,
        boolean retryable,
        String provider,
        String providerMessageId,
        String failureReason) {

    public static DeliveryOutcome sent(String provider, String providerMessageId) {
        return new DeliveryOutcome(true, false, provider, providerMessageId, null);
    }

    /** Transient: rate limit, timeout, provider 5xx. Worth retrying with backoff. */
    public static DeliveryOutcome transientFailure(String provider, String reason) {
        return new DeliveryOutcome(false, true, provider, null, reason);
    }

    /** Permanent: malformed recipient, rejected content, unknown device token. Do not retry. */
    public static DeliveryOutcome permanentFailure(String provider, String reason) {
        return new DeliveryOutcome(false, false, provider, null, reason);
    }

    /**
     * A failure that happened before any provider was reached — the connector was unreachable, or
     * the worker rejected the message itself. Treated as transient by default for the same reason
     * a dropped connection is: the call may have got through before the failure was observed, and
     * the idempotency key is what makes retrying that safe.
     */
    public static DeliveryOutcome transientFailure(String reason) {
        return new DeliveryOutcome(false, true, null, null, reason);
    }

    public static DeliveryOutcome permanentFailure(String reason) {
        return new DeliveryOutcome(false, false, null, null, reason);
    }
}
