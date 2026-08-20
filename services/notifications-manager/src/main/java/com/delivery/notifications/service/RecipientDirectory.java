package com.delivery.notifications.service;

import java.time.Duration;
import java.time.Instant;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Service;
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.util.MultiValueMap;
import org.springframework.web.client.RestClient;

import com.delivery.platform.notifications.NotificationCommand;
import com.fasterxml.jackson.databind.JsonNode;

/**
 * Turns a Keycloak user id into the addresses to reach them on.
 *
 * <p>Order events carry {@code customerId}, {@code merchantId} and {@code riderId} — Keycloak subs,
 * not contact details. Something has to resolve them, and Keycloak is where email and phone number
 * already live: copying them into a notification-owned table would create a second source of truth
 * that goes stale the moment a customer changes their number in their profile.
 *
 * <p>Read through a dedicated service-account client with {@code view-users} and nothing else. A
 * service that only needs to read a user's email should not be able to write one.
 *
 * <p>Results are cached briefly. Without it, a five-notification order would make five identical
 * admin-API calls, and Keycloak's admin API is not built for that rate — but the TTL is short
 * enough that a customer who corrects their phone number is not sent to the old one for long.
 */
@Service
public class RecipientDirectory {

    private static final Logger log = LoggerFactory.getLogger(RecipientDirectory.class);

    /**
     * The Keycloak user attribute holding the mobile number in E.164.
     *
     * <p>Not a standard OIDC claim — {@code phone_number} exists in the spec but Keycloak does not
     * populate or validate it by default, so the realm carries it as a user attribute.
     */
    private static final String PHONE_ATTRIBUTE = "phoneNumber";

    /** Where the mobile app stores its FCM registration token after sign-in. */
    private static final String DEVICE_TOKEN_ATTRIBUTE = "fcmToken";

    private final RestClient keycloak;
    private final String realm;
    private final String clientId;
    private final String clientSecret;
    private final Duration cacheTtl;

    private final Map<String, CachedContacts> cache = new ConcurrentHashMap<>();
    private volatile CachedToken token = new CachedToken(null, Instant.EPOCH);

    public RecipientDirectory(
            RestClient.Builder builder,
            @Value("${delivery.notifications.keycloak.base-url:http://localhost:8180}") String baseUrl,
            @Value("${delivery.notifications.keycloak.realm:delivery-platform}") String realm,
            @Value("${delivery.notifications.keycloak.client-id:notifications-manager}") String clientId,
            @Value("${delivery.notifications.keycloak.client-secret:}") String clientSecret,
            @Value("${delivery.notifications.recipient-cache-ttl:5m}") Duration cacheTtl) {
        this.keycloak = builder.baseUrl(baseUrl).build();
        this.realm = realm;
        this.clientId = clientId;
        this.clientSecret = clientSecret;
        this.cacheTtl = cacheTtl;
    }

    /**
     * Channel to address for one user, ready to hand to
     * {@link NotificationDispatchService#dispatch}.
     *
     * <p>A channel the user has no address for is simply absent from the map, and the dispatch
     * service skips it. That is the intended behaviour rather than a failure: not having a phone
     * number on file is normal, and it should mean "no SMS", not "this notification errored".
     */
    public Map<String, String> contactsFor(String userId) {
        if (userId == null || userId.isBlank()) {
            return Map.of();
        }

        CachedContacts cached = cache.get(userId);
        if (cached != null && Instant.now().isBefore(cached.expiresAt())) {
            return cached.contacts();
        }

        Map<String, String> contacts = load(userId);
        cache.put(userId, new CachedContacts(contacts, Instant.now().plus(cacheTtl)));
        return contacts;
    }

    private Map<String, String> load(String userId) {
        Map<String, String> contacts = new HashMap<>();
        // Always reachable in-app: the recipient is the user id itself, so this channel works even
        // when Keycloak is unreachable.
        contacts.put(NotificationCommand.CHANNEL_IN_APP, userId);

        try {
            JsonNode user = keycloak.get()
                    .uri("/admin/realms/{realm}/users/{id}", realm, userId)
                    .header("Authorization", "Bearer " + accessToken())
                    .retrieve()
                    .body(JsonNode.class);

            if (user == null) {
                return contacts;
            }

            String email = user.path("email").asText(null);
            if (email != null && !email.isBlank()) {
                contacts.put(NotificationCommand.CHANNEL_EMAIL, email);
            }

            JsonNode attributes = user.path("attributes");
            firstAttribute(attributes, PHONE_ATTRIBUTE)
                    .ifPresent(phone -> contacts.put(NotificationCommand.CHANNEL_SMS, phone));
            firstAttribute(attributes, DEVICE_TOKEN_ATTRIBUTE)
                    .ifPresent(fcm -> contacts.put(NotificationCommand.CHANNEL_PUSH, fcm));

        } catch (Exception e) {
            // Degraded, not failed. In-app still works, and the order event is not retried into a
            // loop over something a retry cannot fix quickly.
            log.warn("Could not read contacts for {} from Keycloak: {}", userId, e.getMessage());
        }

        return contacts;
    }

    /** Keycloak returns user attributes as arrays, even when single-valued. */
    private static java.util.Optional<String> firstAttribute(JsonNode attributes, String name) {
        JsonNode values = attributes.path(name);
        if (values.isArray() && !values.isEmpty()) {
            String value = values.get(0).asText(null);
            return value == null || value.isBlank()
                    ? java.util.Optional.empty()
                    : java.util.Optional.of(value);
        }
        return java.util.Optional.empty();
    }

    /**
     * A client-credentials token for the admin API, reused until shortly before it expires.
     *
     * <p>Refreshed early rather than on expiry: a token that expires mid-request produces a 401 for
     * a notification that had nothing wrong with it.
     */
    private String accessToken() {
        CachedToken current = token;
        if (current.value() != null && Instant.now().isBefore(current.expiresAt())) {
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
        CachedToken fresh = new CachedToken(
                response.get("access_token").asText(),
                Instant.now().plusSeconds(Math.max(expiresIn - TOKEN_REFRESH_MARGIN_SECONDS, 5)));
        token = fresh;
        return fresh.value();
    }

    private static final long TOKEN_REFRESH_MARGIN_SECONDS = 30;

    private record CachedContacts(Map<String, String> contacts, Instant expiresAt) {
    }

    private record CachedToken(String value, Instant expiresAt) {
    }
}
