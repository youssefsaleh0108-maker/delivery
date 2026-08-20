package com.delivery.platform.notifications;

import java.util.Map;

/**
 * The {@code connector.settings_changed} payload Connector Settings publishes (Section 8).
 *
 * <p>Declared here rather than in the settings service so a connector can deserialise it without
 * depending on that service's jar — the two must stay independently deployable, and a shared
 * contract record is the cheapest way to keep them honest about the payload shape.
 *
 * <p>The config map carries non-secret values only. Secrets stay in Vault and reach a connector
 * through the Config Server, never over the bus, where they would end up in queue backlogs and
 * broker traces.
 */
public record SettingsChangedEvent(
        String connectorType,
        String provider,
        Map<String, String> config) {

    /** Routing key. Every connector binds its own queue to this. */
    public static final String ROUTING_KEY = "connector.settings_changed";
}
