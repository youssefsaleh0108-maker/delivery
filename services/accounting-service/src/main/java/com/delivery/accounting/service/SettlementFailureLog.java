package com.delivery.accounting.service;

import java.util.UUID;

/**
 * Where a settlement nobody will retry is written down (RECON-04).
 *
 * <p>An interface so the event listener can be built without one — every test that is not about
 * this passes {@link #NONE} — and so that what the listener does with a message it cannot settle is
 * one line at the point of failure rather than a repository call in the middle of the parsing.
 */
public interface SettlementFailureLog {

    /**
     * Records that an order will not settle from this message.
     *
     * @param orderId       the order, or null when the message did not name one that could be read
     * @param reason        what stopped it, in the words an operator will read
     * @param payload       the message as it arrived, for whoever has to work out what happened
     */
    void record(UUID orderId, String eventType, String reason, String payload,
                String correlationId);

    /** Writes nothing. */
    SettlementFailureLog NONE = (orderId, eventType, reason, payload, correlationId) -> {
    };
}
