package com.delivery.accounting.service;

import java.time.Duration;
import java.time.Instant;
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

import com.fasterxml.jackson.databind.JsonNode;

/**
 * Maps a Keycloak user id to the bank account they settle through.
 *
 * <p>Same reasoning as the notification layer's recipient directory: order events carry subs, not
 * account numbers, and Keycloak already holds the per-user attributes. Copying them into an
 * accounting-owned table would create a second source of truth that goes stale the moment someone
 * changes their payout account.
 *
 * <p><strong>The fallback is deliberate and load-bearing.</strong> A user with no
 * {@code bankAccountRef} attribute resolves to a per-role dev account rather than to null, because
 * failing the settlement outright would mean a delivered order that can never be reconciled. In
 * production the attribute is mandatory at onboarding, and the fallback is what makes its absence
 * show up as a posting to an obviously-wrong account in the reconciliation view rather than as
 * silence.
 */
@Service
public class AccountDirectory {

    private static final Logger log = LoggerFactory.getLogger(AccountDirectory.class);

    /** Keycloak user attribute holding the account this person settles through. */
    private static final String ACCOUNT_ATTRIBUTE = "bankAccountRef";

    private final RestClient keycloak;
    private final String realm;
    private final String clientId;
    private final String clientSecret;
    private final String unmappedAccount;
    private final Duration cacheTtl;

    private final Map<String, Cached> cache = new ConcurrentHashMap<>();
    private volatile CachedToken token = new CachedToken(null, Instant.EPOCH);

    public AccountDirectory(
            RestClient.Builder builder,
            @Value("${delivery.accounting.keycloak.base-url:http://localhost:8180}") String baseUrl,
            @Value("${delivery.accounting.keycloak.realm:delivery-platform}") String realm,
            @Value("${delivery.accounting.keycloak.client-id:accounting-service}") String clientId,
            @Value("${delivery.accounting.keycloak.client-secret:}") String clientSecret,
            @Value("${delivery.accounting.unmapped-account:ACC-UNMAPPED}") String unmappedAccount,
            @Value("${delivery.accounting.account-cache-ttl:15m}") Duration cacheTtl) {
        this.keycloak = builder.baseUrl(baseUrl).build();
        this.realm = realm;
        this.clientId = clientId;
        this.clientSecret = clientSecret;
        this.unmappedAccount = unmappedAccount;
        this.cacheTtl = cacheTtl;
    }

    public String forUser(String userId) {
        Cached cached = cache.get(userId);
        if (cached != null && Instant.now().isBefore(cached.expiresAt())) {
            return cached.accountRef();
        }

        String accountRef = load(userId);
        cache.put(userId, new Cached(accountRef, Instant.now().plus(cacheTtl)));
        return accountRef;
    }

    private String load(String userId) {
        try {
            JsonNode user = keycloak.get()
                    .uri("/admin/realms/{realm}/users/{id}", realm, userId)
                    .header("Authorization", "Bearer " + accessToken())
                    .retrieve()
                    .body(JsonNode.class);

            if (user != null) {
                JsonNode values = user.path("attributes").path(ACCOUNT_ATTRIBUTE);
                if (values.isArray() && !values.isEmpty()) {
                    String accountRef = values.get(0).asText(null);
                    if (accountRef != null && !accountRef.isBlank()) {
                        return accountRef;
                    }
                }
            }
            log.warn("User {} has no {} attribute; settling to {}",
                    userId, ACCOUNT_ATTRIBUTE, unmappedAccount);

        } catch (Exception e) {
            log.error("Could not read the bank account for {}: {}", userId, e.getMessage());
        }
        return unmappedAccount;
    }

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
        // Refreshed early: a token expiring mid-request produces a 401 for a settlement that had
        // nothing wrong with it.
        CachedToken fresh = new CachedToken(response.get("access_token").asText(),
                Instant.now().plusSeconds(Math.max(expiresIn - 30, 5)));
        token = fresh;
        return fresh.value();
    }

    private record Cached(String accountRef, Instant expiresAt) {
    }

    private record CachedToken(String value, Instant expiresAt) {
    }
}
