package com.delivery.notifications.domain;

/**
 * One row of the delivery-rate report: how one provider performed on one channel.
 *
 * <p>A projection interface rather than an entity — Spring Data maps the aggregate query onto it
 * directly, so there is no table behind this and nothing to keep in step with notification_log.
 */
public interface DeliveryRateProjection {

    String getChannel();

    /** Null for rows that never reached a provider, which is itself worth seeing. */
    String getProvider();

    long getTotal();

    long getSent();

    long getFailed();

    long getPending();

    /** Seconds from the log row being written to the provider accepting it. Null if none sent. */
    Double getAvgSecondsToSend();

    /** Carrier confirmed arrival. */
    long getDelivered();

    /** Carrier confirmed it never arrived — the number acceptance rates cannot see. */
    long getUndelivered();

    /**
     * Accepted by the provider, with no carrier receipt yet.
     *
     * <p>Reported rather than buried so a delivery rate can be read honestly: a provider with 1000
     * accepted, 12 delivered and 988 awaiting is not a 1.2% delivery rate, it is a provider whose
     * receipts are not arriving — possibly because none were ever configured.
     */
    long getAwaitingReceipt();

    /** Seconds from provider acceptance to carrier confirmation. Null until something is delivered. */
    Double getAvgSecondsToDeliver();
}
