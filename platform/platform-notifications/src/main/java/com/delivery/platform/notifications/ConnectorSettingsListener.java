package com.delivery.platform.notifications;

import java.util.LinkedHashMap;
import java.util.Map;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.amqp.rabbit.annotation.RabbitListener;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * Applies {@code connector.settings_changed} to a connector's {@link ActiveProviderRegistry}.
 *
 * <p>Shared rather than copied into each connector because all three need identical behaviour, and
 * the failure mode of getting it subtly different — one connector that quietly ignores a provider
 * switch — stays invisible until someone asks why messages still went through the old vendor.
 *
 * <p>Each connector gets its OWN queue bound to this routing key. They must not share one: a topic
 * exchange fans out, and competing consumers on a single queue would mean only one connector ever
 * heard about any given change.
 */
public class ConnectorSettingsListener {

    private static final Logger log = LoggerFactory.getLogger(ConnectorSettingsListener.class);

    private final String connectorType;
    private final ActiveProviderRegistry registry;
    private final ObjectMapper objectMapper;

    public ConnectorSettingsListener(String connectorType, ActiveProviderRegistry registry,
                                     ObjectMapper objectMapper) {
        this.connectorType = connectorType;
        this.registry = registry;
        this.objectMapper = objectMapper;
    }

    @RabbitListener(queues = "${delivery.connector.settings-queue}")
    public void onSettingsChanged(String payload) {
        try {
            JsonNode node = objectMapper.readTree(payload);
            String type = node.path("connectorType").asText(null);

            // Every connector's changes land on this queue, because they all bind the same routing
            // key. Filtering here is cheaper than a routing key per connector type and means
            // adding a connector needs no broker change.
            if (!connectorType.equals(type)) {
                return;
            }

            Map<String, String> config = new LinkedHashMap<>();
            node.path("config").fields().forEachRemaining(
                    entry -> config.put(entry.getKey(), entry.getValue().asText()));

            registry.apply(node.path("provider").asText(registry.activeProvider()), config);

        } catch (Exception e) {
            // Never rethrow: a malformed settings event must not become a poison pill that stops
            // the connector consuming. The registry's TTL refresh is the backstop.
            log.error("Ignoring unreadable settings event: {}", payload, e);
        }
    }
}
