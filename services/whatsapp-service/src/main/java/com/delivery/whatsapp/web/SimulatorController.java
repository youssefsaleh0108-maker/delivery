package com.delivery.whatsapp.web;

import java.time.Instant;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Deque;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

/**
 * A stand-in for WhatsApp, so the whole feature can be exercised without a WhatsApp account.
 *
 * <p>Getting a real number is weeks of business verification, and until then the alternative is a
 * feature nobody can try. This is the same choice already made for Core Banking (Phase 4): a
 * simulator that speaks the vendor's shapes, and a toggle that swaps in the real thing.
 *
 * <p><strong>It is not a way around the signature check.</strong> {@code /simulator/inbound} builds
 * a Cloud API envelope and signs it with the configured app secret, then posts it through the real
 * webhook. If the secret is wrong, the simulated message is rejected exactly as a forged one would
 * be — which means this endpoint cannot become the hole in the one public path.
 *
 * <p>Dev only, on two counts: {@code delivery.whatsapp.simulator.enabled} must be true, and the
 * Gateway deliberately does not route {@code /simulator/**}. The same reasoning that keeps the Core
 * Banking simulator's fault-injection endpoint off the public gateway.
 */
@RestController
@RequestMapping(SimulatorController.PATH)
@ConditionalOnProperty(prefix = "delivery.whatsapp.simulator", name = "enabled",
        havingValue = "true", matchIfMissing = true)
public class SimulatorController {

    public static final String PATH = "/simulator";

    private static final Logger log = LoggerFactory.getLogger(SimulatorController.class);

    /** How many sent messages to remember. Enough for a test run, bounded so it cannot grow. */
    private static final int KEEP = 200;

    private final Deque<SentMessage> sent = new ArrayDeque<>();
    private final WebhookSignature signature;
    private final InboundWebhookController webhook;
    private final ObjectMapper objectMapper;

    public SimulatorController(WebhookSignature signature,
                               InboundWebhookController webhook,
                               ObjectMapper objectMapper) {
        this.signature = signature;
        this.webhook = webhook;
        this.objectMapper = objectMapper;
        log.warn("The WhatsApp simulator is enabled. This must not be true in production.");
    }

    public record SentMessage(String id, String from, String to, String body, Instant at) {
    }

    // ---------------------------------------------------------------- standing in for the send API

    /**
     * Meta's send endpoint, as far as {@code OutboundSender} is concerned.
     *
     * <p>Answers in Meta's shape so the production sender is the code being exercised here, rather
     * than a development-only branch that first runs for real on the day it matters.
     */
    @PostMapping("/outbound")
    public Map<String, Object> outbound(@RequestBody JsonNode request) {
        String to = request.path("to").asText("");
        String body = request.path("text").path("body").asText("");
        String from = request.path("from").asText("");

        SentMessage message = new SentMessage(
                "wamid.sim." + UUID.randomUUID(), from, to, body, Instant.now());
        synchronized (sent) {
            sent.addFirst(message);
            while (sent.size() > KEEP) {
                sent.removeLast();
            }
        }
        log.info("Simulator accepted a message to {}: {}", to, body);

        return Map.of(
                "messaging_product", "whatsapp",
                "contacts", List.of(Map.of("wa_id", to)),
                "messages", List.of(Map.of("id", message.id())));
    }

    /** What the shop has sent. The assertion surface for a test, and a window for a developer. */
    @GetMapping("/sent")
    public List<SentMessage> sent() {
        synchronized (sent) {
            return new ArrayList<>(sent);
        }
    }

    @DeleteMapping("/sent")
    public ResponseEntity<Void> clear() {
        synchronized (sent) {
            sent.clear();
        }
        return ResponseEntity.noContent().build();
    }

    // ---------------------------------------------------------------- standing in for a customer

    public record InboundRequest(
            @NotBlank @Size(max = 64) String phoneNumberId,
            @NotBlank @Size(max = 32) String from,
            @Size(max = 160) String name,
            @NotBlank @Size(max = 4000) String body) {
    }

    /**
     * Pretends a customer wrote something.
     *
     * <p>Goes the long way round on purpose: it builds the provider's envelope, signs it with the
     * real app secret, and hands it to the real webhook. Nothing here is a shortcut past the
     * verification — a misconfigured secret makes the simulator stop working, which is exactly the
     * signal a developer wants before they discover it in production.
     */
    @PostMapping("/inbound")
    public ResponseEntity<Void> inbound(@Valid @RequestBody InboundRequest request) throws Exception {
        // Built a level at a time rather than as one nested literal: this is the provider's own
        // envelope shape, and it has to be readable next to their documentation.
        Map<String, Object> message = Map.of(
                "from", request.from(),
                "id", "wamid.sim." + UUID.randomUUID(),
                "timestamp", String.valueOf(Instant.now().getEpochSecond()),
                "type", "text",
                "text", Map.of("body", request.body()));

        Map<String, Object> contact = Map.of(
                "wa_id", request.from(),
                "profile", Map.of("name", request.name() == null ? "" : request.name()));

        Map<String, Object> value = Map.of(
                "messaging_product", "whatsapp",
                "metadata", Map.of("phone_number_id", request.phoneNumberId()),
                "contacts", List.of(contact),
                "messages", List.of(message));

        Map<String, Object> change = Map.of("field", "messages", "value", value);
        Map<String, Object> entry = Map.of("id", "SIMULATED", "changes", List.of(change));
        Map<String, Object> envelope = Map.of(
                "object", "whatsapp_business_account",
                "entry", List.of(entry));

        byte[] raw = objectMapper.writeValueAsBytes(envelope);
        return webhook.receive(signature.sign(signatureSecret(), raw), raw);
    }

    /**
     * The configured secret, read through the verifier so there is exactly one place that knows it.
     *
     * <p>Blank when nothing is provisioned, which produces an unverifiable signature and a 401 —
     * the same answer a real unconfigured deployment gives.
     */
    private String signatureSecret() {
        return signature.configuredSecret();
    }
}
