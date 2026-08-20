package com.delivery.whatsapp.service;

import java.time.Instant;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

import com.delivery.whatsapp.domain.WhatsAppMessage;
import com.fasterxml.jackson.databind.JsonNode;

/**
 * Meta's Cloud API envelope, unwrapped.
 *
 * <p>The shape is deeply nested and batched — {@code entry[] → changes[] → value.messages[]} — and a
 * single callback can carry messages from several customers at once. Everything here is defensive
 * about missing nodes rather than mapped onto a DTO, because the provider adds fields at will and a
 * strict binding would start rejecting real messages the day they ship a new message type.
 *
 * <p>What it refuses to do is guess. A message with no id cannot be deduplicated, so it is dropped
 * rather than stored: a redelivery would otherwise appear twice in the merchant's thread, and a
 * duplicate is worse than a gap here because it invites sending the same order twice.
 */
@Component
public class CloudApiPayloadParser {

    private static final Logger log = LoggerFactory.getLogger(CloudApiPayloadParser.class);

    /** Provider type strings we understand, mapped to what a merchant will see in the thread. */
    private static final Map<String, WhatsAppMessage.Kind> KINDS = new HashMap<>();

    static {
        KINDS.put("text", WhatsAppMessage.Kind.TEXT);
        KINDS.put("image", WhatsAppMessage.Kind.IMAGE);
        KINDS.put("audio", WhatsAppMessage.Kind.AUDIO);
        // A voice note is an audio message with a flag set. Merchants do not make the distinction,
        // and neither does anything downstream.
        KINDS.put("voice", WhatsAppMessage.Kind.AUDIO);
        KINDS.put("document", WhatsAppMessage.Kind.DOCUMENT);
        KINDS.put("location", WhatsAppMessage.Kind.LOCATION);
    }

    public List<InboundMessage> parse(JsonNode root) {
        List<InboundMessage> parsed = new ArrayList<>();
        if (root == null) {
            return parsed;
        }

        for (JsonNode entry : root.path("entry")) {
            for (JsonNode change : entry.path("changes")) {
                JsonNode value = change.path("value");

                // Status callbacks — "delivered", "read" — arrive on the same webhook as messages.
                // They are about our own outbound messages, not the customer's, and there is nothing
                // in this feature that acts on them, so they are skipped rather than half-handled.
                if (!value.path("messages").isArray()) {
                    continue;
                }

                String phoneNumberId = value.path("metadata").path("phone_number_id").asText(null);
                Map<String, String> names = contactNames(value);

                for (JsonNode message : value.path("messages")) {
                    InboundMessage inbound = one(message, phoneNumberId, names);
                    if (inbound != null) {
                        parsed.add(inbound);
                    }
                }
            }
        }
        return parsed;
    }

    private InboundMessage one(JsonNode message, String phoneNumberId, Map<String, String> names) {
        String providerMessageId = message.path("id").asText(null);
        String from = message.path("from").asText(null);
        if (providerMessageId == null || providerMessageId.isBlank() || from == null || from.isBlank()) {
            log.warn("Dropping a WhatsApp message with no id or no sender; it cannot be deduplicated "
                    + "or attributed to a conversation");
            return null;
        }

        String type = message.path("type").asText("text");
        WhatsAppMessage.Kind kind = KINDS.getOrDefault(type, WhatsAppMessage.Kind.OTHER);

        return new InboundMessage(
                phoneNumberId,
                from,
                names.get(from),
                providerMessageId,
                bodyOf(message, kind),
                kind,
                timestampOf(message));
    }

    /**
     * What to show in the thread.
     *
     * <p>Only text has a body. A location is rendered from its coordinates because a customer
     * dropping a pin has said something specific and useful — where to deliver — and showing them
     * nothing would lose it. Media types get no body at all: the provider hands over a media id that
     * has to be fetched with a separate authenticated call, and a placeholder pretending to be
     * content would be worse than the honest blank the merchant sees beside the type.
     */
    private String bodyOf(JsonNode message, WhatsAppMessage.Kind kind) {
        if (kind == WhatsAppMessage.Kind.TEXT) {
            String text = message.path("text").path("body").asText(null);
            // Interactive replies (buttons, list picks) arrive as their own types but read as text
            // to a merchant, so their title is treated as the body.
            if (text == null) {
                text = message.path("button").path("text").asText(null);
            }
            return text;
        }
        if (kind == WhatsAppMessage.Kind.LOCATION) {
            JsonNode location = message.path("location");
            String name = location.path("name").asText(null);
            String coordinates = location.path("latitude").asText("?")
                    + "," + location.path("longitude").asText("?");
            return name == null || name.isBlank() ? coordinates : name + " (" + coordinates + ")";
        }
        // A caption is the one piece of text a media message can carry, and it is often the whole
        // order — "2 of these please" under a photo.
        String caption = message.path(message.path("type").asText("")).path("caption").asText(null);
        return caption == null || caption.isBlank() ? null : caption;
    }

    /**
     * When the customer sent it.
     *
     * <p>Unix seconds as a string, which is what the provider sends. Falls back to now: a message
     * with an unreadable timestamp still has to appear in the thread, and putting it at the bottom
     * is the least wrong place for it.
     */
    private Instant timestampOf(JsonNode message) {
        String raw = message.path("timestamp").asText(null);
        if (raw == null || raw.isBlank()) {
            return Instant.now();
        }
        try {
            return Instant.ofEpochSecond(Long.parseLong(raw.trim()));
        } catch (NumberFormatException e) {
            log.warn("Unreadable WhatsApp timestamp '{}'; treating the message as just-arrived", raw);
            return Instant.now();
        }
    }

    private Map<String, String> contactNames(JsonNode value) {
        Map<String, String> names = new HashMap<>();
        for (JsonNode contact : value.path("contacts")) {
            String waId = contact.path("wa_id").asText(null);
            String name = contact.path("profile").path("name").asText(null);
            if (waId != null && name != null && !name.isBlank()) {
                names.put(waId, name);
            }
        }
        return names;
    }
}
