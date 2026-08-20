package com.delivery.platform.notifications;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

/**
 * The one endpoint every connector exposes, and the only place a provider gets called.
 *
 * <p>Shared across the three connectors because the sequence is identical — resolve the active
 * provider, run the call inside the breaker and retry, dead-letter what is left. Only the provider
 * clients differ, and those are contributed by the connector.
 *
 * <p><strong>Not routed by the API Gateway.</strong> This path exists only on the internal network
 * between a worker and its connector; it is not in the Gateway's route table, so it is unreachable
 * from outside the cluster. In dev the compose network is the trust boundary. Staging and
 * production put mTLS between services (Section 10) — until then, do not add a Gateway route for
 * it, because that would expose "send an arbitrary SMS" to anyone with any valid token.
 */
@RestController
public class ConnectorSendController {

    private static final Logger log = LoggerFactory.getLogger(ConnectorSendController.class);

    private final Map<String, ProviderClient> clients = new LinkedHashMap<>();
    private final ActiveProviderRegistry registry;
    private final ResilientDispatcher dispatcher;
    private final DeadLetterPublisher deadLetters;
    private final String connectorType;

    public ConnectorSendController(List<ProviderClient> providerClients,
                                   ActiveProviderRegistry registry,
                                   ResilientDispatcher dispatcher,
                                   DeadLetterPublisher deadLetters,
                                   ConnectorProperties properties) {
        providerClients.forEach(client -> this.clients.put(client.name(), client));
        this.registry = registry;
        this.dispatcher = dispatcher;
        this.deadLetters = deadLetters;
        this.connectorType = properties.getType();
    }

    @PostMapping(NotificationCommand.CONNECTOR_SEND_PATH)
    public DeliveryOutcome send(@RequestBody NotificationCommand command) {
        // Routed on the idempotency key, so a retry always reaches the vendor that saw the original
        // attempt. See CanaryRouter — getting this wrong sends the customer two texts.
        String provider = CanaryRouter.route(
                registry.activeProvider(), registry.config(), command.idempotencyKey());
        ProviderClient client = clients.get(provider);

        if (client == null) {
            // Configuration says to use a provider this build does not have. Permanent, because
            // retrying cannot conjure the implementation — and loud, because it means Connector
            // Settings and the deployed connector disagree about what exists.
            log.error("{} connector has no client for active provider {} (have {})",
                    connectorType, provider, clients.keySet());
            deadLetters.park(command, "no client for provider " + provider);
            return DeliveryOutcome.permanentFailure(provider, "no client for provider " + provider);
        }

        return dispatcher.dispatch(command, client::send, deadLetters::park);
    }

    /**
     * What this connector is currently doing. Useful from a shell inside the network when a
     * provider switch is not behaving, and cheap enough to leave in.
     */
    @GetMapping("/api/connector/status")
    public Map<String, Object> status() {
        Map<String, String> config = registry.config();
        Map<String, Object> status = new LinkedHashMap<>();
        status.put("connectorType", connectorType);
        status.put("activeProvider", registry.activeProvider());
        status.put("availableProviders", clients.keySet());
        status.put("settingsStale", registry.isStale());
        status.put("circuitState", dispatcher.circuitState());
        // Surfaced because "which provider did that go through" has two answers during a ramp, and
        // an operator staring at a delivery-rate dip needs to know a canary is running.
        status.put("canaryProvider", config.getOrDefault(CanaryRouter.CANARY_PROVIDER, ""));
        status.put("canaryPercentage", config.getOrDefault(CanaryRouter.CANARY_PERCENTAGE, "0"));
        return status;
    }

    /**
     * Which provider a given message would go to, without sending it.
     *
     * <p>Exists so a ramp can be confirmed before it carries real traffic, and so the split can be
     * verified as deterministic rather than assumed. Takes an id, sends nothing, and is on the same
     * internal-only path as the rest of this controller.
     */
    @GetMapping("/api/connector/route/{idempotencyKey}")
    public Map<String, Object> route(@PathVariable String idempotencyKey) {
        return Map.of(
                "idempotencyKey", idempotencyKey,
                "bucket", CanaryRouter.bucketOf(idempotencyKey),
                "provider", CanaryRouter.route(
                        registry.activeProvider(), registry.config(), idempotencyKey));
    }
}
