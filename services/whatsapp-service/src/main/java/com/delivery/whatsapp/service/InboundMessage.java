package com.delivery.whatsapp.service;

import java.time.Instant;

import com.delivery.whatsapp.domain.WhatsAppMessage;

/**
 * One message, already lifted out of the provider's envelope.
 *
 * <p>The point of this type is that nothing downstream has to know what Meta's JSON looks like. If
 * a second provider is ever added — Twilio's WhatsApp API, or a local aggregator — it produces these
 * and the rest of the service is untouched, which is exactly how the SMS connectors are arranged.
 *
 * @param phoneNumberId     the shop's number the customer wrote to; how we find the merchant
 * @param customerWaId      the customer's WhatsApp id, their number in practice
 * @param customerName      the display name the provider reports, often absent
 * @param providerMessageId the provider's own id; the dedup key for redelivered webhooks
 * @param body              the text, or null for a kind that carries none
 * @param kind              what sort of message it was, even when there is no body to show
 * @param sentAt            when the customer sent it, not when we received it
 */
public record InboundMessage(
        String phoneNumberId,
        String customerWaId,
        String customerName,
        String providerMessageId,
        String body,
        WhatsAppMessage.Kind kind,
        Instant sentAt) {
}
