package com.delivery.platform.notifications;

/**
 * One external provider a connector can send through.
 *
 * <p>This is the abstraction Section 8 is built on: which implementation is live is a runtime
 * setting a Backoffice user changes, not a code change or a redeploy. The SMS connector ships three
 * of these from Phase 3 — dev-passthrough, MontyMobile and Twilio — precisely so going live with a
 * vendor is a dropdown, not a project.
 *
 * <p>Implementations must classify their failures honestly via {@link DeliveryOutcome}. Marking
 * everything retryable turns one bad recipient into a retry storm; marking everything permanent
 * throws away messages that a rate limit would have let through a second later.
 */
public interface ProviderClient {

    /** Must match a provider name in the connector's {@code ConnectorType} list. */
    String name();

    /**
     * Hands the message to the provider.
     *
     * <p>{@code command.notificationId()} is the idempotency key and must be passed to the provider
     * wherever the API supports one, so a retry cannot become a second message.
     */
    DeliveryOutcome send(NotificationCommand command);
}
