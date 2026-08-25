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
 *
 * <p>{@code addressInvalid} is a narrower claim than {@code !retryable}: not merely "this attempt
 * will never succeed" but "this ADDRESS will never work again, for any message". A provider outage
 * that exhausts its retries is permanent for the message and says nothing about the recipient; an
 * uninstalled app or a disconnected number condemns the address itself. Only the second is grounds
 * for the platform to stop using an address it was given, which is why it needs its own flag rather
 * than being inferred from the failure text.
 */
public record DeliveryOutcome(
        boolean success,
        boolean retryable,
        boolean addressInvalid,
        String provider,
        String providerMessageId,
        String failureReason) {

    public static DeliveryOutcome sent(String provider, String providerMessageId) {
        return new DeliveryOutcome(true, false, false, provider, providerMessageId, null);
    }

    /** Transient: rate limit, timeout, provider 5xx. Worth retrying with backoff. */
    public static DeliveryOutcome transientFailure(String provider, String reason) {
        return new DeliveryOutcome(false, true, false, provider, null, reason);
    }

    /** Permanent: rejected content, provider refusal. Do not retry, but the address may be fine. */
    public static DeliveryOutcome permanentFailure(String provider, String reason) {
        return new DeliveryOutcome(false, false, false, provider, null, reason);
    }

    /**
     * The address itself is dead: app uninstalled, token rotated, number disconnected.
     *
     * <p>Permanent like {@link #permanentFailure}, and additionally a signal to stop addressing this
     * recipient here. Without acting on it, one uninstall produces a failed notification for every
     * message that user is ever sent again — each one indistinguishable, in the "what is stuck"
     * view, from a delivery problem somebody needs to look at.
     */
    public static DeliveryOutcome invalidAddress(String provider, String reason) {
        return new DeliveryOutcome(false, false, true, provider, null, reason);
    }

    /**
     * A failure that happened before any provider was reached — the connector was unreachable, or
     * the worker rejected the message itself. Treated as transient by default for the same reason
     * a dropped connection is: the call may have got through before the failure was observed, and
     * the idempotency key is what makes retrying that safe.
     */
    public static DeliveryOutcome transientFailure(String reason) {
        return new DeliveryOutcome(false, true, false, null, null, reason);
    }

    public static DeliveryOutcome permanentFailure(String reason) {
        return new DeliveryOutcome(false, false, false, null, null, reason);
    }
}
