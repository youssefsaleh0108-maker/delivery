package com.delivery.transfer.connector;

import com.delivery.transfer.domain.MoneyTransfer;
import com.delivery.transfer.domain.TransferMethod;

/**
 * One way money can actually move.
 *
 * <p>The ESB's connector pattern, inside this service: the transfer manager owns the ledger row
 * and the workflow, a connector owns the conversation with whatever carries the money — the rider
 * flow for cash, the Whish API, the OMT API. Adding a provider is adding a bean; nothing in the
 * API layer changes, exactly as the notification connectors sit behind the notifications manager.
 *
 * <p>A connector NEVER edits the row's amounts. It reports what happened (a reference and a
 * status) and the service records it; the money figures were fixed at quote time, rate lock and
 * all, and a provider that wants to renegotiate them is a provider reporting a failure.
 */
public interface MoneyTransferConnector {

    /** Stable name written into the transfer's audit column, e.g. {@code cash}, {@code sim-wallet}. */
    String name();

    /** Whether this connector carries the given method. First taker wins in registry order. */
    boolean supports(TransferMethod method);

    /**
     * Whether the provider behind it can currently accept work. A connector whose credentials or
     * endpoint are absent answers false and the method simply does not appear in the app — a
     * method that shows and then fails is worse than one that never showed.
     */
    boolean ready();

    /** Sets the transfer in motion. Implementations call {@code transfer.carriedBy(...)}. */
    void initiate(MoneyTransfer transfer);
}
