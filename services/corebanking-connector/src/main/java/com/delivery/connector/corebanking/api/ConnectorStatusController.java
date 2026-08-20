package com.delivery.connector.corebanking.api;

import java.util.List;
import java.util.Map;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import com.delivery.connector.corebanking.provider.BankClient;
import com.delivery.platform.notifications.ActiveProviderRegistry;
import com.delivery.platform.notifications.ResilientDispatcher;

/**
 * What this connector is currently doing.
 *
 * <p>Read-only and secret-free — the provider name and the breaker state, nothing about the
 * credential. It is the counterpart to the notification connectors' status endpoint, and the first
 * thing to check when "why did that settlement not post" comes up.
 *
 * <p>There is deliberately no send endpoint here. Postings arrive on a queue, and adding an HTTP
 * way in would be a way to make the bank call synchronous again.
 */
@RestController
public class ConnectorStatusController {

    private final ActiveProviderRegistry registry;
    private final ResilientDispatcher dispatcher;
    private final List<String> providers;

    public ConnectorStatusController(ActiveProviderRegistry registry,
                                     ResilientDispatcher bankDispatcher,
                                     List<BankClient> clients) {
        this.registry = registry;
        this.dispatcher = bankDispatcher;
        this.providers = clients.stream().map(BankClient::name).toList();
    }

    @GetMapping("/api/connector/status")
    public Map<String, Object> status() {
        return Map.of(
                "connectorType", "CORE_BANKING",
                "activeProvider", registry.activeProvider(),
                "availableProviders", providers,
                "settingsStale", registry.isStale(),
                "circuitState", dispatcher.circuitState());
    }
}
