package com.delivery.transfer.domain;

/**
 * The transfer's life. Deliberately small: this service records intent and outcome, it is not a
 * card processor with a dozen intermediate states.
 */
public enum TransferStatus {
    /** Recorded, nothing moved yet. */
    PENDING,
    /** A connector accepted it — a wallet hold placed, or cash notified to the rider flow. */
    INITIATED,
    /** The money arrived (rider collected; wallet settled). */
    COMPLETED,
    /** It will not happen — order cancelled, or the connector refused. */
    CANCELLED
}
