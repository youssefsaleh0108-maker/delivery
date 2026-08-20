package com.delivery.connector.sms.provider;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.Instant;
import java.util.HexFormat;
import java.util.List;
import java.util.Map;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import com.delivery.platform.notifications.DeliveryReceiptTranslator;
import com.delivery.platform.notifications.ProviderDeliveryReceipt;

/**
 * A carrier receipt for the dev passthrough provider, so the DLR path can be exercised end to end
 * without a vendor account.
 *
 * <p><strong>This does not invent delivery outcomes.</strong> Nothing here decides that a message
 * arrived — the test inbox has no carrier behind it and no way to know. It only accepts an outcome
 * that a test, a smoke script or an operator explicitly asserts, so the plumbing either side of it
 * (signature check, bus hop, matching on provider_message_id, the rate query) can be proven to work.
 * Fabricating delivery results would corrupt the one number this whole feature exists to make
 * trustworthy, which is why the real vendors' translators have no equivalent shortcut.
 *
 * <p>Still signed, with the same fail-closed rule as the real providers. An unauthenticated way to
 * write delivery outcomes would be a hole regardless of which provider name it wrote them under, and
 * "it's only the dev provider" is how that kind of hole reaches production.
 */
@Component
public class DevPassthroughDlrTranslator implements DeliveryReceiptTranslator {

    private static final Logger log = LoggerFactory.getLogger(DevPassthroughDlrTranslator.class);

    private static final String SIGNATURE_HEADER = "x-delivery-signature";

    private final String secret;

    public DevPassthroughDlrTranslator(
            @Value("${delivery.sms.dev-passthrough.dlr-secret:}") String secret) {
        this.secret = secret;
    }

    @Override
    public String name() {
        return DevPassthroughSmsClient.NAME;
    }

    @Override
    public boolean verify(String requestUrl, Map<String, String> headers, Map<String, String> form,
                          String rawBody) {
        if (secret.isBlank()) {
            log.warn("Dev-passthrough DLR rejected: no callback secret configured");
            return false;
        }
        String presented = headers.get(SIGNATURE_HEADER);
        if (presented == null || presented.isBlank()) {
            return false;
        }
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
            return HexFormat.of().formatHex(mac.doFinal(material.getBytes(StandardCharsets.UTF_8)));
        } catch (Exception e) {
            log.error("Could not compute a dev-passthrough signature", e);
            return null;
        }
    }

    @Override
    public List<ProviderDeliveryReceipt> translate(Map<String, String> form, String rawBody) {
        String messageId = form.get("messageId");
        String status = form.get("status");
        if (messageId == null || status == null) {
            return List.of();
        }
        Boolean delivered = switch (status.trim().toLowerCase()) {
            case "delivered" -> Boolean.TRUE;
            case "undelivered", "failed" -> Boolean.FALSE;
            default -> null;
        };
        if (delivered == null) {
            return List.of();
        }
        return List.of(new ProviderDeliveryReceipt(
                DevPassthroughSmsClient.NAME, messageId, "SMS", delivered, status, Instant.now()));
    }
}
