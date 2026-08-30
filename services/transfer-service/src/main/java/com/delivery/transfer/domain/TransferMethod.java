package com.delivery.transfer.domain;

/**
 * How the money physically travels. Each maps to a connector; which connector answers for which
 * method is the ConnectorRegistry's business, not this enum's.
 */
public enum TransferMethod {
    /** Hand-to-rider at the door, USD, LBP or the split. The Lebanese default. */
    CASH_ON_DELIVERY,
    /** Whish Money wallet transfer. */
    WHISH,
    /** OMT online money transfer. */
    OMT,
    /** BOB Finance wallet transfer. */
    BOB
}
