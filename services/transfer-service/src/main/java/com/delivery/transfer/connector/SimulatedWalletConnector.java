package com.delivery.transfer.connector;

import java.util.UUID;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;

import com.delivery.transfer.domain.MoneyTransfer;
import com.delivery.transfer.domain.TransferMethod;
import com.delivery.transfer.domain.TransferStatus;

/**
 * The dev stand-in for the wallet providers (Whish, OMT).
 *
 * <p>Accepts every transfer and mints a reference, so the whole flow — quote, split, initiate,
 * status — is exercisable end to end before either commercial integration exists. Real
 * connectors replace this one bean each, keyed off the same {@link TransferMethod}; enabled by a
 * flag so a production deployment that forgets to configure the real thing gets NO wallet methods
 * rather than a simulator quietly accepting real customers' money.
 */
@Component
@Order(100)
public class SimulatedWalletConnector implements MoneyTransferConnector {

    private final boolean enabled;

    public SimulatedWalletConnector(
            @Value("${delivery.transfer.simulate-wallets:true}") boolean enabled) {
        this.enabled = enabled;
    }

    @Override
    public String name() {
        return "sim-wallet";
    }

    @Override
    public boolean supports(TransferMethod method) {
        return method == TransferMethod.WHISH || method == TransferMethod.OMT
                || method == TransferMethod.BOB;
    }

    @Override
    public boolean ready() {
        return enabled;
    }

    @Override
    public void initiate(MoneyTransfer transfer) {
        transfer.carriedBy(name(),
                "SIM-" + UUID.randomUUID().toString().substring(0, 8).toUpperCase(),
                TransferStatus.INITIATED);
    }
}
