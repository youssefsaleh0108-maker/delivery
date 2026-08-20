package com.delivery.whatsapp.client;

import java.util.Map;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

import com.delivery.whatsapp.config.WhatsAppProperties;
import com.fasterxml.jackson.databind.JsonNode;

/**
 * Sends a message back to the customer.
 *
 * <p>Shaped as Meta's Cloud API send call, because that is what it will be talking to in a
 * deployment. Locally it points at this service's own simulator, so the same code path runs in
 * development as in production — a separate "dev sender" would mean the real one is first exercised
 * on the day it matters.
 */
@Component
public class OutboundSender {

    private static final Logger log = LoggerFactory.getLogger(OutboundSender.class);

    private final RestClient restClient;
    private final WhatsAppProperties properties;

    public OutboundSender(RestClient.Builder builder, WhatsAppProperties properties) {
        this.restClient = builder.build();
        this.properties = properties;
    }

    /**
     * What happened to a send.
     *
     * @param accepted          whether the provider took it
     * @param providerMessageId the provider's id, when there is one
     * @param detail            why not, when there isn't
     */
    public record SendResult(boolean accepted, String providerMessageId, String detail) {

        static SendResult ok(String providerMessageId) {
            return new SendResult(true, providerMessageId, null);
        }

        static SendResult failed(String detail) {
            return new SendResult(false, null, detail);
        }
    }

    /**
     * Never throws.
     *
     * <p>Every caller here is doing something else that already succeeded — an order was placed, a
     * merchant wrote a reply — and a provider outage must not undo it. The result says what happened
     * so the caller can tell the merchant the message did not go out, which is a different and much
     * smaller problem than the order silently not existing.
     */
    public SendResult send(String phoneNumberId, String toWaId, String body) {
        String url = properties.getOutboundUrl();
        if (url == null || url.isBlank()) {
            log.warn("No outbound URL configured; nothing was sent to {}", toWaId);
            return SendResult.failed("outbound messaging is not configured");
        }

        try {
            RestClient.RequestBodySpec request = restClient.post()
                    .uri(url)
                    .contentType(MediaType.APPLICATION_JSON);
            String accessToken = properties.getAccessToken();
            if (accessToken != null && !accessToken.isBlank()) {
                request = request.header("Authorization", "Bearer " + accessToken);
            }

            // Meta's own shape. Kept even against the simulator so the request that is exercised in
            // development is the request that will be sent in production.
            JsonNode response = request
                    .body(Map.of(
                            "messaging_product", "whatsapp",
                            "recipient_type", "individual",
                            "to", toWaId,
                            "type", "text",
                            "text", Map.of("preview_url", false, "body", body),
                            // Not part of Meta's payload — the number id is in the URL there. The
                            // simulator needs it to know which shop is talking.
                            "from", phoneNumberId == null ? "" : phoneNumberId))
                    .retrieve()
                    .body(JsonNode.class);

            String id = response == null ? null
                    : response.path("messages").path(0).path("id").asText(null);
            if (id == null || id.isBlank()) {
                // Accepted, but with nothing to identify it by. Treated as sent: the customer has
                // the message either way, and failing here would tempt a caller into resending.
                log.warn("Outbound message to {} was accepted with no id", toWaId);
                return SendResult.ok(null);
            }
            return SendResult.ok(id);
        } catch (Exception e) {
            log.error("Could not send a WhatsApp message to {}", toWaId, e);
            return SendResult.failed("the message could not be sent");
        }
    }
}
