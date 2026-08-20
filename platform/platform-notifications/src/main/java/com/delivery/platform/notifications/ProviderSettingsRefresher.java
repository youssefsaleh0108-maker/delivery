package com.delivery.platform.notifications;

import java.util.LinkedHashMap;
import java.util.Map;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.web.client.RestClient;

import com.fasterxml.jackson.databind.JsonNode;

/**
 * Pulls the active provider from Connector Settings when the cached value has aged out.
 *
 * <p>The bus event is the fast path — a provider switch takes effect within a second. This is the
 * slow safety net for the case the event never arrived: the connector was restarting, or the broker
 * dropped it. Without it a missed event would leave a connector on a vendor the business believes
 * it has turned off, which for SMS means real messages and real spend through the wrong account.
 *
 * <p>A failed refresh is deliberately non-fatal. The registry keeps its last known-good value, so a
 * Connector Settings outage degrades the freshness of a setting rather than taking a connector
 * down (Section 8).
 */
public class ProviderSettingsRefresher {

    private static final Logger log = LoggerFactory.getLogger(ProviderSettingsRefresher.class);

    private final RestClient client;
    private final String connectorType;
    private final ActiveProviderRegistry registry;

    public ProviderSettingsRefresher(RestClient client, String connectorType,
                                     ActiveProviderRegistry registry) {
        this.client = client;
        this.connectorType = connectorType;
        this.registry = registry;
    }

    /** Called on a timer. Cheap when the cache is warm — no call is made at all. */
    public void refreshIfStale() {
        if (registry.isStale()) {
            refresh();
        }
    }

    public void refresh() {
        try {
            JsonNode body = client.get()
                    .uri("/internal/connectors/{type}", connectorType)
                    .retrieve()
                    .body(JsonNode.class);

            if (body == null || body.path("provider").isMissingNode()) {
                log.warn("Connector Settings returned no provider for {}, keeping {}",
                        connectorType, registry.activeProvider());
                return;
            }

            Map<String, String> config = new LinkedHashMap<>();
            body.path("config").fields().forEachRemaining(
                    entry -> config.put(entry.getKey(), entry.getValue().asText()));

            registry.apply(body.path("provider").asText(), config);

        } catch (Exception e) {
            // Degraded, not broken: the last known-good provider stays in force.
            log.warn("Could not refresh {} settings, still using {}: {}",
                    connectorType, registry.activeProvider(), e.getMessage());
        }
    }
}
