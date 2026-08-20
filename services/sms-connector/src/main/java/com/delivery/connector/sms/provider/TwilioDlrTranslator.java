package com.delivery.connector.sms.provider;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Base64;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import com.delivery.platform.notifications.DeliveryReceiptTranslator;
import com.delivery.platform.notifications.ProviderDeliveryReceipt;

/**
 * Twilio's status callbacks — the carrier's verdict on a message we already sent.
 *
 * <p>Twilio POSTs form-encoded and signs with {@code X-Twilio-Signature}: HMAC-SHA1, keyed on the
 * account's auth token, over the full callback URL with every POST parameter appended after it as
 * name-then-value pairs in lexicographic order by name. The URL is part of the signed material, so
 * anything that rewrites it in front of this service will fail verification — see
 * {@code DlrWebhookController.requestUrl} for how the forwarded headers are honoured.
 *
 * <p>Confidence here is high: unlike the MontyMobile side, this scheme is stable and precisely
 * documented. It still has not been exercised against a live Twilio account, because there isn't
 * one — open decision #6.
 */
@Component
public class TwilioDlrTranslator implements DeliveryReceiptTranslator {

    private static final Logger log = LoggerFactory.getLogger(TwilioDlrTranslator.class);

    private static final String SIGNATURE_HEADER = "x-twilio-signature";

    private final String authToken;

    public TwilioDlrTranslator(@Value("${delivery.sms.twilio.auth-token:}") String authToken) {
        this.authToken = authToken;
    }

    @Override
    public String name() {
        return TwilioSmsClient.NAME;
    }

    @Override
    public boolean verify(String requestUrl, Map<String, String> headers, Map<String, String> form,
                          String rawBody) {
        if (authToken.isBlank()) {
            // Fails CLOSED. The tempting alternative — "no token configured, so skip the check" —
            // would mean the endpoint silently accepts anything on exactly the deployments where
            // nobody has finished the setup, which is when it is least likely to be noticed.
            log.warn("Twilio DLR rejected: no auth token provisioned, so nothing can be verified");
            return false;
        }
        String presented = headers.get(SIGNATURE_HEADER);
        if (presented == null || presented.isBlank()) {
            return false;
        }

        String expected = sign(requestUrl, form);
        if (expected == null) {
            return false;
        }
        // Constant-time: a byte-by-byte comparison that returns early leaks how much of a forged
        // signature was correct, and a webhook is an endpoint an attacker can call repeatedly.
        return MessageDigest.isEqual(
                expected.getBytes(StandardCharsets.UTF_8),
                presented.getBytes(StandardCharsets.UTF_8));
    }

    /** Twilio's documented scheme: URL, then sorted name+value pairs, HMAC-SHA1, base64. */
    String sign(String requestUrl, Map<String, String> form) {
        StringBuilder material = new StringBuilder(requestUrl);
        new TreeMap<>(form).forEach((key, value) -> material.append(key).append(value));
        try {
            Mac mac = Mac.getInstance("HmacSHA1");
            mac.init(new SecretKeySpec(authToken.getBytes(StandardCharsets.UTF_8), "HmacSHA1"));
            return Base64.getEncoder().encodeToString(
                    mac.doFinal(material.toString().getBytes(StandardCharsets.UTF_8)));
        } catch (Exception e) {
            log.error("Could not compute a Twilio signature", e);
            return null;
        }
    }

    @Override
    public List<ProviderDeliveryReceipt> translate(Map<String, String> form, String rawBody) {
        String messageSid = form.get("MessageSid");
        String status = form.get("MessageStatus");
        if (messageSid == null || status == null) {
            return List.of();
        }

        // Twilio emits queued/sending/sent/delivered/undelivered/failed. Only the last three are
        // answers; the rest are the message still being in flight, and publishing one as an outcome
        // would resolve its fate before the carrier has decided it.
        Boolean delivered = switch (status.toLowerCase()) {
            case "delivered" -> Boolean.TRUE;
            case "undelivered", "failed" -> Boolean.FALSE;
            default -> null;
        };
        if (delivered == null) {
            return List.of();
        }

        // ErrorCode is present only on the failure path and is the single most useful field for
        // telling "wrong number" apart from "carrier rejected us", so it is kept verbatim.
        String detail = form.containsKey("ErrorCode")
                ? status + " (" + form.get("ErrorCode") + ")"
                : status;

        List<ProviderDeliveryReceipt> receipts = new ArrayList<>(1);
        receipts.add(new ProviderDeliveryReceipt(
                TwilioSmsClient.NAME, messageSid, "SMS", delivered, detail, Instant.now()));
        return receipts;
    }
}
