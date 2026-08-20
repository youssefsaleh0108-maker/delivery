package com.delivery.connector.sms.provider;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.Instant;
import java.util.ArrayList;
import java.util.HexFormat;
import java.util.List;
import java.util.Map;
import java.util.Set;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import com.delivery.platform.notifications.DeliveryReceiptTranslator;
import com.delivery.platform.notifications.ProviderDeliveryReceipt;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * MontyMobile's delivery-report callback.
 *
 * <p><strong>Contract confidence is LOW</strong>, exactly as it is for {@link MontyMobileSmsClient},
 * and for the same reason: this follows the published v1 shape, but the account's own documentation
 * is the authority and there is no account yet. Every field name is therefore configurable rather
 * than compiled in, so confirming the real contract is a config change. The runbook's instruction to
 * validate against real responses before ramping past 5% applies to this file more than any other.
 *
 * <p>Verification is a shared-secret HMAC-SHA256 over the raw body, hex-encoded — the common shape
 * where a vendor does not document something more specific. If MontyMobile turns out to sign
 * differently, this is the method to change, and it must keep failing closed while it is unknown.
 */
@Component
public class MontyMobileDlrTranslator implements DeliveryReceiptTranslator {

    private static final Logger log = LoggerFactory.getLogger(MontyMobileDlrTranslator.class);

    /** Vendor vocabularies vary; these are the v1 terminal values, lower-cased. */
    private static final Set<String> DELIVERED = Set.of("delivered", "delivrd", "2");
    private static final Set<String> UNDELIVERED =
            Set.of("undelivered", "undeliv", "expired", "rejected", "rejectd", "failed", "3", "5");

    private final ObjectMapper objectMapper;
    private final String secret;
    private final String signatureHeader;
    private final String messageIdField;
    private final String statusField;

    public MontyMobileDlrTranslator(
            ObjectMapper objectMapper,
            @Value("${delivery.sms.montymobile.dlr-secret:}") String secret,
            @Value("${delivery.sms.montymobile.dlr-signature-header:x-monty-signature}")
            String signatureHeader,
            @Value("${delivery.sms.montymobile.dlr-message-id-field:messageId}") String messageIdField,
            @Value("${delivery.sms.montymobile.dlr-status-field:status}") String statusField) {
        this.objectMapper = objectMapper;
        this.secret = secret;
        this.signatureHeader = signatureHeader.toLowerCase();
        this.messageIdField = messageIdField;
        this.statusField = statusField;
    }

    @Override
    public String name() {
        return MontyMobileSmsClient.NAME;
    }

    @Override
    public boolean verify(String requestUrl, Map<String, String> headers, Map<String, String> form,
                          String rawBody) {
        if (secret.isBlank()) {
            log.warn("MontyMobile DLR rejected: no callback secret provisioned");
            return false;
        }
        String presented = headers.get(signatureHeader);
        if (presented == null || presented.isBlank()) {
            return false;
        }
        // Form-encoded callbacks leave no raw body to sign (the container consumed the stream), so
        // fall back to the canonical sorted-field encoding rather than signing an empty string —
        // which would otherwise verify identically for every payload.
        String material = rawBody.isEmpty() ? canonicalise(form) : rawBody;

        String expected = hmacHex(material);
        return expected != null && MessageDigest.isEqual(
                expected.getBytes(StandardCharsets.UTF_8),
                presented.trim().toLowerCase().getBytes(StandardCharsets.UTF_8));
    }

    private String canonicalise(Map<String, String> form) {
        StringBuilder sb = new StringBuilder();
        new java.util.TreeMap<>(form).forEach((k, v) -> {
            if (sb.length() > 0) {
                sb.append('&');
            }
            sb.append(k).append('=').append(v);
        });
        return sb.toString();
    }

    private String hmacHex(String material) {
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(secret.getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
            return HexFormat.of().formatHex(
                    mac.doFinal(material.getBytes(StandardCharsets.UTF_8)));
        } catch (Exception e) {
            log.error("Could not compute a MontyMobile signature", e);
            return null;
        }
    }

    @Override
    public List<ProviderDeliveryReceipt> translate(Map<String, String> form, String rawBody) {
        List<ProviderDeliveryReceipt> receipts = new ArrayList<>();
        // v1 posts JSON, but the vendor's own docs show a form-encoded variant too, so both are
        // accepted rather than betting on one.
        if (!rawBody.isBlank()) {
            try {
                JsonNode root = objectMapper.readTree(rawBody);
                // A single object or a batch — vendors that batch tend to start doing so without
                // warning once volume rises.
                if (root.isArray()) {
                    root.forEach(node -> add(receipts, node.path(messageIdField).asText(null),
                            node.path(statusField).asText(null)));
                } else {
                    add(receipts, root.path(messageIdField).asText(null),
                            root.path(statusField).asText(null));
                }
            } catch (Exception e) {
                log.warn("Could not parse a MontyMobile DLR body", e);
            }
        } else {
            add(receipts, form.get(messageIdField), form.get(statusField));
        }
        return receipts;
    }

    private void add(List<ProviderDeliveryReceipt> receipts, String messageId, String status) {
        if (messageId == null || messageId.isBlank() || status == null || status.isBlank()) {
            return;
        }
        String normalised = status.trim().toLowerCase();
        Boolean delivered = DELIVERED.contains(normalised) ? Boolean.TRUE
                : UNDELIVERED.contains(normalised) ? Boolean.FALSE
                : null;
        if (delivered == null) {
            // An intermediate state, or one this integration has never seen. Both mean "no answer
            // yet"; guessing would be worse than waiting, and the unknown value is logged so an
            // unrecognised vocabulary surfaces during the 5% pilot rather than after the ramp.
            log.info("MontyMobile DLR status '{}' is not a terminal outcome; ignored", status);
            return;
        }
        receipts.add(new ProviderDeliveryReceipt(
                MontyMobileSmsClient.NAME, messageId, "SMS", delivered, status, Instant.now()));
    }
}
