package com.delivery.transfer.connector;

import java.util.List;
import java.util.Optional;

import org.springframework.stereotype.Component;

import com.delivery.transfer.domain.TransferMethod;

/**
 * Which connector answers for which method.
 *
 * <p>Spring injects every {@link MoneyTransferConnector} bean in {@code @Order} order; the first
 * READY one that supports the method carries it. That ordering is the upgrade path: a real Whish
 * connector at order 50 silently takes over from the order-100 simulator the day it appears, with
 * no other code changing.
 */
@Component
public class ConnectorRegistry {

    private final List<MoneyTransferConnector> connectors;

    public ConnectorRegistry(List<MoneyTransferConnector> connectors) {
        this.connectors = connectors;
    }

    public Optional<MoneyTransferConnector> forMethod(TransferMethod method) {
        return connectors.stream()
                .filter(c -> c.supports(method) && c.ready())
                .findFirst();
    }

    /** The methods a client may offer right now: those some ready connector will carry. */
    public List<TransferMethod> availableMethods() {
        return List.of(TransferMethod.values()).stream()
                .filter(m -> forMethod(m).isPresent())
                .toList();
    }
}
