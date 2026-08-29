package com.delivery.accounting.service;

import java.time.Instant;
import java.util.Map;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.util.MultiValueMap;
import org.springframework.web.client.RestClient;

import com.fasterxml.jackson.databind.JsonNode;

/**
 * Sends one message to one address through Notifications Manager.
 *
 * <p>The same path Onboarding uses for a one-time code — {@code POST /api/notifications/direct} with
 * a channel, a recipient, a subject, a body and a purpose, authenticated as this service. Deliberately
 * NOT an SMTP client of this service's own: that service owns the templates, the provider
 * credentials, the retries and the delivery log, and a second sending path would create a class of
 * message nobody can answer "did it arrive" about.
 *
 * <p><strong>Failures are thrown, never swallowed.</strong> The caller records a dispatch row on
 * success and that row is a claim that a statement reached somebody. Logging a failure and returning
 * normally would write that claim about a message that never left, and the counterparties listing
 * would then show the shop as told — which is worse than showing nothing, because the operator stops
 * chasing it.
 *
 * <p>The direct endpoint is BACKOFFICE-gated, so this service's Keycloak client needs that realm
 * role and its client id has to be on {@code delivery.security.allowed-client-ids} in Notifications
 * Manager. Same requirement Onboarding's {@code PlatformClient} carries, and for the same reason.
 */
@Component
public class NotificationsClient {

    private static final Logger log = LoggerFactory.getLogger(NotificationsClient.class);

    private final RestClient notifications;
    private final RestClient keycloak;
    private final String realm;
    private final String clientId;
    private final String clientSecret;

    private volatile Cached token = new Cached(null, Instant.EPOCH);

    public NotificationsClient(
            RestClient.Builder builder,
            @Value("${delivery.services.notifications-manager:http://localhost:8104}")
            String notificationsUrl,
            @Value("${delivery.accounting.keycloak.base-url:http://localhost:8180}") String baseUrl,
            @Value("${delivery.accounting.keycloak.realm:delivery-platform}") String realm,
            @Value("${delivery.accounting.keycloak.client-id:accounting-service}") String clientId,
            @Value("${delivery.accounting.keycloak.client-secret:}") String clientSecret) {
        this.notifications = builder.clone().baseUrl(notificationsUrl).build();
        this.keycloak = builder.clone().baseUrl(baseUrl).build();
        this.realm = realm;
        this.clientId = clientId;
        this.clientSecret = clientSecret;
    }

    /**
     * @return Notifications Manager's own id for the message, which its delivery log is keyed on,
     *         or null when it accepted the message without naming one
     */
    public String sendDirect(String channel, String recipient, String subject, String body,
                             String purpose) {
        JsonNode accepted = notifications.post()
                .uri("/api/notifications/direct")
                .header("Authorization", "Bearer " + serviceToken())
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of(
                        "channel", channel,
                        "recipient", recipient,
                        "subject", subject == null ? "" : subject,
                        "body", body,
                        "purpose", purpose))
                .retrieve()
                .body(JsonNode.class);

        String id = accepted == null ? null : accepted.path("notificationId").asText(null);
        log.info("Sent a {} statement to {} ({})", channel, redact(recipient), id);
        return id;
    }

    /**
     * The address, with the local part cut short.
     *
     * <p>Logs are read by more people than statements are. Enough survives to match a line against a
     * support ticket; not enough to harvest a shop's contact address out of a log aggregator.
     */
    private static String redact(String recipient) {
        int at = recipient.indexOf('@');
        if (at <= 1) {
            return "***";
        }
        return recipient.charAt(0) + "***" + recipient.substring(at);
    }

    private String serviceToken() {
        Cached current = token;
        if (current.usable()) {
            return current.value();
        }

        MultiValueMap<String, String> form = new LinkedMultiValueMap<>();
        form.add("grant_type", "client_credentials");
        form.add("client_id", clientId);
        form.add("client_secret", clientSecret);

        JsonNode response = keycloak.post()
                .uri("/realms/{realm}/protocol/openid-connect/token", realm)
                .contentType(MediaType.APPLICATION_FORM_URLENCODED)
                .body(form)
                .retrieve()
                .body(JsonNode.class);

        if (response == null || !response.hasNonNull("access_token")) {
            throw new IllegalStateException("Keycloak did not return a service-account token");
        }

        long expiresIn = response.path("expires_in").asLong(60);
        // Refreshed early, as everywhere else: a token that expires mid-request produces a 401 for
        // a send that had nothing wrong with it, and the operator sees a failure they cannot act on.
        Cached fresh = new Cached(response.get("access_token").asText(),
                Instant.now().plusSeconds(Math.max(expiresIn - 30, 5)));
        token = fresh;
        return fresh.value();
    }

    private record Cached(String value, Instant expiresAt) {
        boolean usable() {
            return value != null && Instant.now().isBefore(expiresAt);
        }
    }
}
