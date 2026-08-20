package com.delivery.connector.sms.provider;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;

import org.junit.jupiter.api.Test;

import com.delivery.platform.notifications.ProviderDeliveryReceipt;

/**
 * The security-critical half of DLR ingestion.
 *
 * <p>These assertions are about what the endpoint REFUSES. The delivery numbers it writes are what a
 * vendor decision rests on, and the endpoint is reachable by anyone on the internet, so "accepts a
 * valid signature" is the least interesting thing to prove here.
 */
class TwilioDlrTranslatorTest {

    private static final String TOKEN = "test-auth-token";
    private static final String URL = "https://delivery.example.com/webhooks/dlr/TWILIO";

    private final TwilioDlrTranslator translator = new TwilioDlrTranslator(TOKEN);

    private Map<String, String> signed(String url, Map<String, String> form) {
        return Map.of("x-twilio-signature", translator.sign(url, form));
    }

    @Test
    void acceptsACallbackSignedWithTheAccountToken() {
        Map<String, String> form = Map.of("MessageSid", "SM123", "MessageStatus", "delivered");

        assertThat(translator.verify(URL, signed(URL, form), form, "")).isTrue();
    }

    @Test
    void rejectsAForgedSignature() {
        Map<String, String> form = Map.of("MessageSid", "SM123", "MessageStatus", "delivered");

        assertThat(translator.verify(URL, Map.of("x-twilio-signature", "not-it"), form, ""))
                .isFalse();
    }

    @Test
    void rejectsACallbackWithNoSignatureAtAll() {
        Map<String, String> form = Map.of("MessageSid", "SM123", "MessageStatus", "delivered");

        assertThat(translator.verify(URL, Map.of(), form, "")).isFalse();
    }

    @Test
    void rejectsAValidSignatureReplayedAgainstDifferentContent() {
        // The signature covers the parameters, so swapping "delivered" for "undelivered" after
        // signing must not still verify — otherwise anyone who observed one genuine callback could
        // rewrite every subsequent outcome.
        Map<String, String> original = Map.of("MessageSid", "SM123", "MessageStatus", "delivered");
        Map<String, String> tampered = Map.of("MessageSid", "SM123", "MessageStatus", "undelivered");

        assertThat(translator.verify(URL, signed(URL, original), tampered, "")).isFalse();
    }

    @Test
    void rejectsASignatureMadeForADifferentUrl() {
        // Twilio signs the URL too, so a callback captured on one deployment cannot be replayed
        // against another.
        Map<String, String> form = Map.of("MessageSid", "SM123", "MessageStatus", "delivered");

        assertThat(translator.verify(URL, signed("https://elsewhere.example.com/webhooks/dlr/TWILIO", form),
                form, "")).isFalse();
    }

    @Test
    void failsClosedWhenNoAuthTokenIsProvisioned() {
        // The important one. An unconfigured deployment must reject receipts, not accept them
        // unverified — otherwise the hole opens exactly where nobody is looking.
        TwilioDlrTranslator unconfigured = new TwilioDlrTranslator("");
        Map<String, String> form = Map.of("MessageSid", "SM123", "MessageStatus", "delivered");

        assertThat(unconfigured.verify(URL, Map.of("x-twilio-signature", "anything"), form, ""))
                .isFalse();
    }

    @Test
    void translatesDeliveredAndUndelivered() {
        List<ProviderDeliveryReceipt> delivered = translator.translate(
                Map.of("MessageSid", "SM1", "MessageStatus", "delivered"), "");
        assertThat(delivered).singleElement()
                .satisfies(r -> {
                    assertThat(r.providerMessageId()).isEqualTo("SM1");
                    assertThat(r.delivered()).isTrue();
                });

        List<ProviderDeliveryReceipt> failed = translator.translate(
                Map.of("MessageSid", "SM2", "MessageStatus", "failed", "ErrorCode", "30003"), "");
        assertThat(failed).singleElement()
                .satisfies(r -> {
                    assertThat(r.delivered()).isFalse();
                    // The error code is the difference between "wrong number" and "carrier problem".
                    assertThat(r.detail()).contains("30003");
                });
    }

    @Test
    void ignoresIntermediateStatuses() {
        // "sent" means Twilio handed it to the carrier — the question this feature exists to answer
        // is still open at that point, and publishing it as an outcome would close it wrongly.
        assertThat(translator.translate(Map.of("MessageSid", "SM1", "MessageStatus", "sent"), ""))
                .isEmpty();
        assertThat(translator.translate(Map.of("MessageSid", "SM1", "MessageStatus", "queued"), ""))
                .isEmpty();
    }
}
