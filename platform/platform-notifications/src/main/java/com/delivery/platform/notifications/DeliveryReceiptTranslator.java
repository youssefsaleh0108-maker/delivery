package com.delivery.platform.notifications;

import java.util.List;
import java.util.Map;

/**
 * Turns one vendor's delivery-receipt callback into the platform's own shape — and, first, decides
 * whether to believe it at all.
 *
 * <p>One implementation per provider, contributed by the connector, mirroring {@link ProviderClient}
 * on the outbound side. Every vendor differs in all three of the things that matter here: how the
 * callback is signed, what the fields are called, and which of its dozen status strings count as a
 * final answer. None of that is worth abstracting away — it is the integration.
 *
 * <p><strong>Verification is not optional.</strong> This endpoint has to be reachable by the public
 * internet for a vendor to call it, and the numbers it writes are the ones a cutover decision rests
 * on. An unauthenticated version would let anyone move those numbers by POSTing invented receipts —
 * cheaply, and in whichever direction they preferred. Implementations must fail closed: no secret
 * configured means reject, never "skip the check".
 */
public interface DeliveryReceiptTranslator {

    /** Provider name, matching the {@link ProviderClient} it belongs to. */
    String name();

    /**
     * Whether this callback genuinely came from the vendor.
     *
     * @param requestUrl the full URL as the vendor called it — part of the signed material for
     *                   several vendors, so a proxy that rewrites it will break verification
     * @param headers    lower-cased header names
     * @param form       decoded form parameters
     * @param rawBody    the body exactly as received, for vendors that sign bytes rather than fields
     */
    boolean verify(String requestUrl, Map<String, String> headers, Map<String, String> form,
                   String rawBody);

    /**
     * Extracts the terminal outcomes from a verified callback.
     *
     * <p>Returns a list because some vendors batch several receipts into one POST, and empty when
     * the callback reports only an intermediate state — "sending" is not an outcome, and publishing
     * it as one would resolve a message's fate before the carrier has decided it.
     */
    List<ProviderDeliveryReceipt> translate(Map<String, String> form, String rawBody);
}
