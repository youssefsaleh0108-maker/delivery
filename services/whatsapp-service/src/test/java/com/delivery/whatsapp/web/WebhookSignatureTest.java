package com.delivery.whatsapp.web;

import static org.assertj.core.api.Assertions.assertThat;

import java.nio.charset.StandardCharsets;

import org.junit.jupiter.api.Test;

import com.delivery.whatsapp.config.WhatsAppProperties;

/**
 * The gate on the one public path. Every test here is a way in that must stay shut.
 */
class WebhookSignatureTest {

    private static final String SECRET = "an-app-secret";
    private static final byte[] BODY = "{\"entry\":[]}".getBytes(StandardCharsets.UTF_8);

    private WebhookSignature signatureWith(String secret) {
        WhatsAppProperties properties = new WhatsAppProperties();
        properties.setAppSecret(secret);
        return new WebhookSignature(properties);
    }

    @Test
    void acceptsABodySignedWithTheConfiguredSecret() {
        WebhookSignature signature = signatureWith(SECRET);

        assertThat(signature.verify(signature.sign(SECRET, BODY), BODY)).isTrue();
    }

    @Test
    void rejectsASignatureFromADifferentSecret() {
        WebhookSignature signature = signatureWith(SECRET);
        String forged = signatureWith("not-the-secret").sign("not-the-secret", BODY);

        assertThat(signature.verify(forged, BODY)).isFalse();
    }

    @Test
    void rejectsAValidSignatureOverDifferentBytes() {
        WebhookSignature signature = signatureWith(SECRET);
        String forOtherBody = signature.sign(SECRET, "{\"entry\":[1]}".getBytes(StandardCharsets.UTF_8));

        // The point of signing the body rather than a header: swapping the payload must invalidate
        // an otherwise genuine signature.
        assertThat(signature.verify(forOtherBody, BODY)).isFalse();
    }

    @Test
    void rejectsEverythingWhenNoSecretIsConfigured() {
        WebhookSignature unconfigured = signatureWith("");

        // Fails closed. A deployment where nobody finished the setup must receive nothing, not
        // accept anything — including a request carrying a perfectly well-formed signature.
        assertThat(unconfigured.verify(signatureWith(SECRET).sign(SECRET, BODY), BODY)).isFalse();
        assertThat(unconfigured.verify(null, BODY)).isFalse();
    }

    @Test
    void rejectsAMissingOrEmptySignatureHeader() {
        WebhookSignature signature = signatureWith(SECRET);

        assertThat(signature.verify(null, BODY)).isFalse();
        assertThat(signature.verify("", BODY)).isFalse();
        assertThat(signature.verify("   ", BODY)).isFalse();
    }

    @Test
    void rejectsTheDigestWithoutItsAlgorithmPrefix() {
        WebhookSignature signature = signatureWith(SECRET);
        String withPrefix = signature.sign(SECRET, BODY);
        String bare = withPrefix.substring("sha256=".length());

        // Not pedantry: accepting a bare hex digest would mean accepting an HMAC computed with a
        // weaker algorithm the day the provider offers one.
        assertThat(signature.verify(bare, BODY)).isFalse();
    }

    @Test
    void signsAsLowercaseHexWithTheAlgorithmPrefix() {
        String produced = signatureWith(SECRET).sign(SECRET, BODY);

        assertThat(produced).matches("sha256=[0-9a-f]{64}");
    }
}
