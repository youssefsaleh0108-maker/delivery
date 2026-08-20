package com.delivery.whatsapp.web;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.HexFormat;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

import com.delivery.whatsapp.config.WhatsAppProperties;

/**
 * The authentication on the one public path in this service.
 *
 * <p>Meta signs the raw request body with HMAC-SHA256 keyed on the app secret and presents it as
 * {@code X-Hub-Signature-256: sha256=<hex>}. The signature covers the <em>bytes</em>, not the parsed
 * fields, so the body has to be read verbatim — re-serialising the JSON would change whitespace and
 * key order and produce a different digest for an identical message.
 */
@Component
public class WebhookSignature {

    static final String HEADER = "X-Hub-Signature-256";

    private static final String PREFIX = "sha256=";
    private static final String ALGORITHM = "HmacSHA256";

    private static final Logger log = LoggerFactory.getLogger(WebhookSignature.class);

    private final WhatsAppProperties properties;

    public WebhookSignature(WhatsAppProperties properties) {
        this.properties = properties;
    }

    /** Whether this body really came from the provider. */
    public boolean verify(String presented, byte[] body) {
        String secret = properties.getAppSecret();
        if (secret == null || secret.isBlank()) {
            // Fails CLOSED, and loudly. An unconfigured secret and a forged request look identical
            // from here; the difference is that one of them is our own fault, and a silent accept
            // would hide it until someone else found the open endpoint first.
            log.warn("WhatsApp webhook rejected: no app secret provisioned, "
                    + "so no request can be verified");
            return false;
        }
        if (presented == null || presented.isBlank()) {
            return false;
        }

        String expected = sign(secret, body);
        if (expected == null) {
            return false;
        }
        // Constant-time. A comparison that returns on the first differing byte leaks how much of a
        // forged signature was right, and this is an endpoint anyone can call as often as they like.
        return MessageDigest.isEqual(
                expected.getBytes(StandardCharsets.UTF_8),
                presented.trim().getBytes(StandardCharsets.UTF_8));
    }

    /**
     * The configured secret, for the simulator to sign with.
     *
     * <p>Exposed rather than read from the properties again so there is one place that knows where
     * the secret comes from. Blank when nothing is provisioned — which makes the simulator produce
     * a signature that fails verification, the same answer a real unconfigured deployment gives.
     */
    String configuredSecret() {
        return properties.getAppSecret() == null ? "" : properties.getAppSecret();
    }

    String sign(String secret, byte[] body) {
        try {
            Mac mac = Mac.getInstance(ALGORITHM);
            mac.init(new SecretKeySpec(secret.getBytes(StandardCharsets.UTF_8), ALGORITHM));
            return PREFIX + HexFormat.of().formatHex(mac.doFinal(body));
        } catch (Exception e) {
            log.error("Could not compute a WhatsApp webhook signature", e);
            return null;
        }
    }
}
