package com.delivery.whatsapp.web;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.List;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.delivery.whatsapp.config.WhatsAppProperties;
import com.delivery.whatsapp.service.CloudApiPayloadParser;
import com.delivery.whatsapp.service.ConversationService;
import com.delivery.whatsapp.service.InboundMessage;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * Where a customer's message arrives.
 *
 * <p>The one public path in this service, and public for a forced reason rather than a chosen one:
 * WhatsApp's servers originate outside our estate and hold no Keycloak token, so demanding one would
 * mean never receiving a message. Authentication is the provider's HMAC signature over the raw body,
 * checked by {@link WebhookSignature} before a single field is read, failing closed with no secret
 * configured. That is a real boundary — a different one, which is why it lives on its own path and
 * its own controller instead of being bolted onto the merchant API beside it.
 *
 * <p>This mirrors {@code DlrWebhookController} deliberately. That endpoint already established the
 * pattern and its constraints, and a second public path invented from scratch is a second place to
 * get it wrong.
 */
@RestController
@RequestMapping(InboundWebhookController.PATH)
public class InboundWebhookController {

    /** Public prefix; the Gateway routes exactly this and nothing else of this service's. */
    public static final String PATH = "/webhooks/whatsapp";

    private static final Logger log = LoggerFactory.getLogger(InboundWebhookController.class);

    private final WebhookSignature signature;
    private final CloudApiPayloadParser parser;
    private final ConversationService conversations;
    private final WhatsAppProperties properties;
    private final ObjectMapper objectMapper;

    public InboundWebhookController(WebhookSignature signature,
                                    CloudApiPayloadParser parser,
                                    ConversationService conversations,
                                    WhatsAppProperties properties,
                                    ObjectMapper objectMapper) {
        this.signature = signature;
        this.parser = parser;
        this.conversations = conversations;
        this.properties = properties;
        this.objectMapper = objectMapper;
    }

    /**
     * The registration handshake. Meta calls this once when the callback URL is saved and expects
     * the challenge echoed back verbatim, as text.
     *
     * <p>Compared in constant time for the same reason the signature is: this is a public endpoint
     * and an attacker can call it as often as they like. It authenticates nothing beyond the
     * handshake itself — only the signature does that — so a correct token here grants no ability to
     * deliver a message.
     */
    @GetMapping(produces = MediaType.TEXT_PLAIN_VALUE)
    public ResponseEntity<String> verify(@RequestParam(name = "hub.mode", required = false) String mode,
                                         @RequestParam(name = "hub.verify_token", required = false) String token,
                                         @RequestParam(name = "hub.challenge", required = false) String challenge) {
        String expected = properties.getVerifyToken();
        boolean ok = "subscribe".equals(mode)
                && expected != null && !expected.isBlank()
                && token != null
                && MessageDigest.isEqual(
                        expected.getBytes(StandardCharsets.UTF_8),
                        token.getBytes(StandardCharsets.UTF_8));

        if (!ok) {
            log.warn("Rejected a WhatsApp webhook verification attempt");
            return ResponseEntity.status(HttpStatus.FORBIDDEN).build();
        }
        return ResponseEntity.ok(challenge == null ? "" : challenge);
    }

    /**
     * A callback carrying customer messages.
     *
     * <p>Taken as raw bytes rather than a bound object because the signature covers the bytes.
     * Re-serialising the parsed JSON would change whitespace and key order and produce a different
     * digest for an identical message — the verification has to see exactly what was sent.
     */
    @PostMapping
    public ResponseEntity<Void> receive(
            @RequestHeader(name = WebhookSignature.HEADER, required = false) String presented,
            @RequestBody(required = false) byte[] body) {

        byte[] raw = body == null ? new byte[0] : body;
        if (!signature.verify(presented, raw)) {
            // Terse to the caller, loud in the log. A forged callback and a misconfigured secret are
            // indistinguishable from here, and the second silently discards real customer messages
            // until someone notices — so it must not be logged at debug.
            log.warn("Rejected an unverified WhatsApp callback");
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }

        JsonNode root;
        try {
            root = objectMapper.readTree(raw);
        } catch (Exception e) {
            // 400, not 500: the body is the caller's, and it is malformed. Retrying it would not
            // help, and telling the provider to retry forever is worse than dropping it.
            log.warn("Unparseable WhatsApp callback body", e);
            return ResponseEntity.badRequest().build();
        }

        List<InboundMessage> inbound = parser.parse(root);
        for (InboundMessage message : inbound) {
            try {
                conversations.record(message);
            } catch (Exception e) {
                // One bad message must not cost us the rest of a batched callback, and must not
                // provoke a redelivery of messages we have already filed correctly.
                log.error("Could not record WhatsApp message {}", message.providerMessageId(), e);
            }
        }

        // Always 2xx once verified. WhatsApp retries anything else, and a callback we understood but
        // found nothing actionable in — a status update, a message type we do not handle — is not a
        // failure the provider can fix by sending it again.
        return ResponseEntity.ok().build();
    }
}
