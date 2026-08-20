package com.delivery.platform.notifications;

import java.time.Instant;

/**
 * What a carrier eventually said became of a message we had already handed over.
 *
 * <p>Distinct from {@link DeliveryReceipt}, and the distinction is the entire point of this class.
 * A {@code DeliveryReceipt} is our own worker reporting whether the PROVIDER accepted the message —
 * it is available within seconds and is what we bill against. This is the CARRIER reporting whether
 * the handset got it, which arrives seconds to hours later over a webhook and can flatly contradict
 * the first. Reporting acceptance as though it were delivery is the specific overstatement this
 * record exists to end.
 *
 * <p>Identified by {@code providerMessageId} rather than our notification id, because the callback
 * comes from a system that has never seen our ids. That makes the vendor's id the join key, and
 * makes it meaningless without the provider name beside it — two vendors will happily issue the same
 * id string.
 *
 * @param provider          which vendor sent this, and half of the lookup key
 * @param providerMessageId the vendor's id for the message, the other half
 * @param delivered         true for a terminal success, false for a terminal failure; intermediate
 *                          states are never published, having no answer to report
 * @param detail            the vendor's own wording, kept for forensics
 * @param occurredAt        when the carrier says it happened, not when we heard about it
 */
public record ProviderDeliveryReceipt(
        String provider,
        String providerMessageId,
        String channel,
        boolean delivered,
        String detail,
        Instant occurredAt) {

    /** Routing key connectors publish carrier receipts on; Notifications Manager binds exactly this. */
    public static final String ROUTING_KEY = "notification.dlr";
}
