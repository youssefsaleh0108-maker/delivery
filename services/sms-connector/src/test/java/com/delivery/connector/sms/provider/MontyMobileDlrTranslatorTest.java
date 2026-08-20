package com.delivery.connector.sms.provider;

import static org.assertj.core.api.Assertions.assertThat;

import java.nio.charset.StandardCharsets;
import java.util.HexFormat;
import java.util.List;
import java.util.Map;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

import org.junit.jupiter.api.Test;

import com.delivery.platform.notifications.ProviderDeliveryReceipt;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * MontyMobile's contract confidence is LOW, so these tests pin down the parts that are OUR decision
 * — fail-closed verification, terminal-vs-intermediate classification, batch handling — rather than
 * asserting a vendor payload shape nobody has confirmed yet.
 */
class MontyMobileDlrTranslatorTest {

    private static final String SECRET = "callback-secret";

    private final ObjectMapper objectMapper = new ObjectMapper();
    private final MontyMobileDlrTranslator translator = new MontyMobileDlrTranslator(
            objectMapper, SECRET, "x-monty-signature", "messageId", "status");

    private static String hmac(String material) {
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(SECRET.getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
            return HexFormat.of().formatHex(mac.doFinal(material.getBytes(StandardCharsets.UTF_8)));
        } catch (Exception e) {
            throw new IllegalStateException(e);
        }
    }

    @Test
    void acceptsABodySignedWithTheSharedSecret() {
        String body = "{\"messageId\":\"MM1\",\"status\":\"delivered\"}";

        assertThat(translator.verify("https://x/webhooks/dlr/MONTYMOBILE",
                Map.of("x-monty-signature", hmac(body)), Map.of(), body)).isTrue();
    }

    @Test
    void rejectsATamperedBody() {
        String signed = "{\"messageId\":\"MM1\",\"status\":\"delivered\"}";
        String tampered = "{\"messageId\":\"MM1\",\"status\":\"undelivered\"}";

        assertThat(translator.verify("https://x/webhooks/dlr/MONTYMOBILE",
                Map.of("x-monty-signature", hmac(signed)), Map.of(), tampered)).isFalse();
    }

    @Test
    void failsClosedWhenNoSecretIsProvisioned() {
        MontyMobileDlrTranslator unconfigured = new MontyMobileDlrTranslator(
                objectMapper, "", "x-monty-signature", "messageId", "status");
        String body = "{\"messageId\":\"MM1\",\"status\":\"delivered\"}";

        assertThat(unconfigured.verify("https://x", Map.of("x-monty-signature", hmac(body)),
                Map.of(), body)).isFalse();
    }

    @Test
    void signsFormFieldsWhenThereIsNoRawBody() {
        // A form-encoded callback leaves no body to sign — the container already consumed it. If
        // that fell back to signing an empty string, every payload would verify identically, which
        // is a hole rather than a fallback.
        Map<String, String> form = Map.of("messageId", "MM1", "status", "delivered");
        String canonical = "messageId=MM1&status=delivered";

        assertThat(translator.verify("https://x", Map.of("x-monty-signature", hmac(canonical)),
                form, "")).isTrue();

        Map<String, String> tampered = Map.of("messageId", "MM1", "status", "undelivered");
        assertThat(translator.verify("https://x", Map.of("x-monty-signature", hmac(canonical)),
                tampered, "")).isFalse();
    }

    @Test
    void translatesABatchedCallback() {
        // Vendors that batch tend to start doing so without warning once volume rises, so one
        // receipt per POST is not a safe assumption.
        String body = """
                [{"messageId":"MM1","status":"delivered"},
                 {"messageId":"MM2","status":"expired"}]
                """;

        List<ProviderDeliveryReceipt> receipts = translator.translate(Map.of(), body);

        assertThat(receipts).hasSize(2);
        assertThat(receipts.get(0).delivered()).isTrue();
        assertThat(receipts.get(1).delivered()).isFalse();
    }

    @Test
    void ignoresAStatusItDoesNotRecognise() {
        // The vocabulary is unconfirmed. Guessing that an unknown string means delivered would put
        // an invented number in front of the person choosing a vendor.
        assertThat(translator.translate(Map.of(),
                "{\"messageId\":\"MM1\",\"status\":\"enroute\"}")).isEmpty();
    }
}
