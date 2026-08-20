package com.delivery.onboarding.client;

import java.time.Duration;
import java.time.Instant;
import java.util.Map;
import java.util.UUID;

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
 * Creating the domain record behind a newly approved partner.
 *
 * <p>This service calls the platform's own APIs rather than writing to their tables, because those
 * tables belong to other services and a cross-schema insert is exactly the coupling
 * schema-per-service exists to prevent. Registering a delivery company through Order Manager also
 * means the payout account is verified at the bank on the way in, which a direct insert would skip.
 *
 * <p><strong>It acts as the platform.</strong> Registering a fleet is a BACKOFFICE action, so the
 * service account carries that role and its client id has to be on
 * {@code delivery.security.allowed-client-ids} — which is a deliberate change: until now the
 * allow-list held only interactive clients, and the service accounts on it called Keycloak's admin
 * API rather than ours. This one calls ours, and it is the only one that does.
 */
@Component
public class PlatformClient {

    private static final Logger log = LoggerFactory.getLogger(PlatformClient.class);

    private final RestClient orderManager;
    private final RestClient notifications;
    private final RestClient keycloak;
    private final String realm;
    private final String clientId;
    private final String clientSecret;

    private volatile Cached token = new Cached(null, Instant.EPOCH);

    public PlatformClient(
            RestClient.Builder builder,
            @Value("${delivery.services.order-manager:http://localhost:8101}") String orderManagerUrl,
            @Value("${delivery.services.notifications-manager:http://localhost:8104}")
            String notificationsUrl,
            @Value("${delivery.keycloak.base-url:http://localhost:8180}") String baseUrl,
            @Value("${delivery.keycloak.realm:delivery-platform}") String realm,
            @Value("${delivery.keycloak.client-id:onboarding-service}") String clientId,
            @Value("${delivery.keycloak.client-secret:}") String clientSecret) {
        this.orderManager = builder.clone().baseUrl(orderManagerUrl).build();
        this.notifications = builder.clone().baseUrl(notificationsUrl).build();
        this.keycloak = builder.clone().baseUrl(baseUrl).build();
        this.realm = realm;
        this.clientId = clientId;
        this.clientSecret = clientSecret;
    }

    private record Cached(String value, Instant expiresAt) {
        boolean usable() {
            return value != null && Instant.now().isBefore(expiresAt);
        }
    }

    /**
     * Registers a delivery company and puts the new account in charge of it.
     *
     * @return the provider id, so the application can record what it created
     */
    public UUID registerCarrier(String name, String contactName, String contactPhone,
                                String staffUserRef) {
        String bearer = serviceToken();
        String slug = slugify(name);

        JsonNode created = orderManager.post()
                .uri("/api/delivery-providers")
                .header("Authorization", "Bearer " + bearer)
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of(
                        "slug", slug,
                        "name", name,
                        "contactName", contactName == null ? "" : contactName,
                        "contactPhone", contactPhone == null ? "" : contactPhone))
                .retrieve()
                .body(JsonNode.class);

        if (created == null || !created.hasNonNull("id")) {
            throw new KeycloakAdminClient.ProvisioningException(
                    "The delivery company could not be registered");
        }
        UUID providerId = UUID.fromString(created.path("id").asText());

        // Staff, not riders. Staff are the people who RUN the company and get the portal; riders
        // are who carries for it. Attaching the owner as a rider would give them a job board and no
        // way to manage their own fleet.
        orderManager.post()
                .uri("/api/delivery-providers/{id}/staff", providerId)
                .header("Authorization", "Bearer " + bearer)
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("riderRef", staffUserRef))
                .retrieve()
                .toBodilessEntity();

        log.info("Registered delivery company {} ({}) for {}", name, providerId, staffUserRef);
        return providerId;
    }

    /**
     * Puts a newly approved rider on a company's rider list.
     *
     * <p>{@code /riders}, not {@code /staff}, and the two are not interchangeable. Staff run the
     * company and see its portal; riders carry for it and see the job board. Only the rider list is
     * consulted when work is dispatched or a job is claimed — so attaching somebody to the wrong
     * one produces an account that looks attached, accepts the sign-in, and is never offered a
     * single delivery.
     */
    public void attachRider(UUID providerId, String riderRef) {
        orderManager.post()
                .uri("/api/delivery-providers/{id}/riders", providerId)
                .header("Authorization", "Bearer " + serviceToken())
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("riderRef", riderRef))
                .retrieve()
                .toBodilessEntity();
        log.info("Attached rider {} to company {}", riderRef, providerId);
    }

    /**
     * Whether this account actually runs that company.
     *
     * <p>The carrier portal sends the company id it believes is its own, and that belief is not
     * evidence: the id names both the queue of people applying and the fleet they would be hired
     * into, so a carrier who edited it could read a competitor's applicants and attach them to
     * their own company. Order Manager holds the record of who runs what, so it is asked.
     *
     * <p>Staff, not riders. Riders carry for a company; staff run it, and hiring is something you
     * do because you run the place.
     */
    public boolean isStaffOf(UUID providerId, String userRef) {
        try {
            JsonNode staff = orderManager.get()
                    .uri("/api/delivery-providers/{id}/staff", providerId)
                    .header("Authorization", "Bearer " + serviceToken())
                    .retrieve()
                    .body(JsonNode.class);
            if (staff == null || !staff.has("riders")) {
                return false;
            }
            for (JsonNode member : staff.path("riders")) {
                if (userRef.equals(member.asText())) {
                    return true;
                }
            }
            return false;
        } catch (Exception e) {
            // An unknown company, or Order Manager being unreachable. Either way this is not a
            // proven claim, and the safe answer to "may I decide this person's application" is no.
            log.warn("Could not confirm whether {} runs company {}", userRef, providerId, e);
            return false;
        }
    }

    /**
     * Sends one message to somebody who has no account.
     *
     * <p>A one-time code, or the decision that follows an application. Both go through Notifications
     * Manager rather than an SMTP client of this service's own: that service owns the templates, the
     * provider credentials, the retries and the delivery log, and a second sending path would mean a
     * class of message nobody can answer "did it arrive" about.
     *
     * <p>Failures are thrown, not swallowed. The caller has to know, because "we have sent you a
     * code" is a promise — a screen that says it while the send failed leaves somebody waiting for
     * a message that is not coming, and no amount of patience will fix it.
     */
    public void notifyDirect(String channel, String recipient, String subject, String body,
                             String purpose) {
        notifications.post()
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
                .toBodilessEntity();
    }

    /**
     * A handle for the company, derived from its name.
     *
     * <p>Suffixed with a short random tail because two businesses genuinely can share a name, and a
     * collision here would fail the whole provisioning step for a reason the applicant cannot fix.
     */
    private static String slugify(String name) {
        String base = name.toLowerCase(java.util.Locale.ROOT)
                .replaceAll("[^a-z0-9]+", "-")
                .replaceAll("(^-|-$)", "");
        if (base.isBlank()) {
            base = "carrier";
        }
        return base.substring(0, Math.min(40, base.length()))
                + "-" + UUID.randomUUID().toString().substring(0, 6);
    }

    private String serviceToken() {
        Cached current = token;
        if (current.usable()) {
            return current.value();
        }
        if (clientSecret == null || clientSecret.isBlank()) {
            throw new KeycloakAdminClient.ProvisioningException(
                    "No service-account secret is configured, so nothing can be registered");
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
            throw new KeycloakAdminClient.ProvisioningException(
                    "Keycloak refused a service-account token");
        }
        long seconds = response.path("expires_in").asLong(60);
        Cached fresh = new Cached(response.path("access_token").asText(),
                Instant.now().plus(Duration.ofSeconds(Math.max(10, seconds - 30))));
        token = fresh;
        return fresh.value();
    }
}
