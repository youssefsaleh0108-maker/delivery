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

    /**
     * Attributes a partner's trading name might be under.
     *
     * <p>None of them is written today: onboarding provisions a Keycloak account with the CONTACT
     * PERSON's first and last name and keeps the business name in its own table. So in practice the
     * fallback below is what a statement shows, and that is stated rather than hidden — a statement
     * headed with the owner's name is legible, and one headed with a UUID is not. The list is here
     * so that whichever of these onboarding eventually sets, this picks it up without a change.
     */
    private static final java.util.List<String> NAME_ATTRIBUTES =
            java.util.List.of("businessName", "storeName", "companyName", "tradingName");

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
        return profileOf(userId).accountRef();
    }

    /**
     * Everything this service needs to know about one account holder.
     *
     * <p>One record and one cache entry rather than a second directory, because the underlying call
     * is the same: {@code load} already fetched the whole user document and threw away everything
     * but one attribute. A statement needs a name to head it with and an address to send it to, and
     * fetching those separately would double the traffic to Keycloak and leave two caches that can
     * disagree about the same person.
     *
     * @param accountRef where the money would post. Never null — see the class note on the fallback
     * @param name       what to call them on a statement, or null if Keycloak knows no name
     * @param email      where to send it, or null. Null is an ANSWER, not a failure: the send
     *                   endpoint refuses with a 409 rather than guessing an address
     */
    public record Profile(String accountRef, String name, String email) {
    }

    /**
     * The account holder behind a Keycloak subject.
     *
     * <p>Returns a profile with the fallback account and no name for an id Keycloak does not know —
     * a delivery company's id, for instance, which is an Order Manager row and was never a user.
     * Throwing there would take a statement down over a missing display name.
     */
    public Profile profileOf(String userId) {
        Cached cached = cache.get(userId);
        if (cached != null && Instant.now().isBefore(cached.expiresAt())) {
            return cached.profile();
        }

        Profile profile = load(userId);
        cache.put(userId, new Cached(profile, Instant.now().plus(cacheTtl)));
        return profile;
    }

    private Profile load(String userId) {
        try {
            JsonNode user = keycloak.get()
                    .uri("/admin/realms/{realm}/users/{id}", realm, userId)
                    .header("Authorization", "Bearer " + accessToken())
                    .retrieve()
                    .body(JsonNode.class);

            if (user != null) {
                String accountRef = attribute(user, ACCOUNT_ATTRIBUTE);
                if (accountRef == null) {
                    log.warn("User {} has no {} attribute; settling to {}",
                            userId, ACCOUNT_ATTRIBUTE, unmappedAccount);
                }
                return new Profile(accountRef == null ? unmappedAccount : accountRef,
                        nameOf(user), text(user.path("email")));
            }
            log.warn("Keycloak returned nothing for user {}; settling to {}",
                    userId, unmappedAccount);

        } catch (Exception e) {
            log.error("Could not read the account for {}: {}", userId, e.getMessage());
        }
        return new Profile(unmappedAccount, null, null);
    }

    /**
     * What to head a statement with.
     *
     * <p>The trading name if anybody has recorded one, otherwise the contact person's name, and only
     * then the username. Never the raw subject: a statement addressed to a UUID is one nobody can
     * check, and the caller can fall back to the id itself if this returns null.
     */
    private static String nameOf(JsonNode user) {
        for (String attribute : NAME_ATTRIBUTES) {
            String value = attribute(user, attribute);
            if (value != null) {
                return value;
            }
        }
        String first = text(user.path("firstName"));
        String last = text(user.path("lastName"));
        if (first != null || last != null) {
            return ((first == null ? "" : first) + " " + (last == null ? "" : last)).trim();
        }
        return text(user.path("username"));
    }

    /** The first value of a Keycloak user attribute, which is always modelled as an array. */
    private static String attribute(JsonNode user, String name) {
        JsonNode values = user.path("attributes").path(name);
        return values.isArray() && !values.isEmpty() ? text(values.get(0)) : null;
    }

    private static String text(JsonNode node) {
        String value = node.asText(null);
        return value == null || value.isBlank() ? null : value;
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

    private record Cached(Profile profile, Instant expiresAt) {
    }

    private record CachedToken(String value, Instant expiresAt) {
    }
}
