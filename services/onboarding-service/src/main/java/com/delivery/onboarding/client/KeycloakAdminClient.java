package com.delivery.onboarding.client;

import java.net.URI;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Map;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.util.MultiValueMap;
import org.springframework.http.ResponseEntity;
import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.RestClient;

import com.fasterxml.jackson.databind.JsonNode;

/**
 * Creating the account a new partner signs in with.
 *
 * <p>Follows the pattern {@code RecipientDirectory} established in the notification layer: a
 * client-credentials token for the realm's admin API, cached and refreshed early. The service
 * account is the only credential this service holds, and it is the reason this service is separate
 * from the ones that merely read the realm.
 *
 * <p><strong>No password is ever set here.</strong> The account is created with a required action
 * to set one, and the applicant follows a link to do it themselves. A password this service chose
 * would have to be transmitted somehow — email, a screen, a log line — and every one of those is a
 * place it can be read by somebody else.
 */
@Component
public class KeycloakAdminClient {

    private static final Logger log = LoggerFactory.getLogger(KeycloakAdminClient.class);

    private final RestClient keycloak;
    private final String realm;
    private final String clientId;
    private final String clientSecret;

    private volatile Cached token = new Cached(null, Instant.EPOCH);

    public KeycloakAdminClient(
            RestClient.Builder builder,
            @Value("${delivery.keycloak.base-url:http://localhost:8180}") String baseUrl,
            @Value("${delivery.keycloak.realm:delivery-platform}") String realm,
            @Value("${delivery.keycloak.client-id:onboarding-service}") String clientId,
            @Value("${delivery.keycloak.client-secret:}") String clientSecret) {
        this.keycloak = builder.baseUrl(baseUrl).build();
        this.realm = realm;
        this.clientId = clientId;
        this.clientSecret = clientSecret;
    }

    private record Cached(String value, Instant expiresAt) {
        boolean usable() {
            return value != null && Instant.now().isBefore(expiresAt);
        }
    }

    /** Thrown when the account could not be created. The process retries the step, not the flow. */
    public static class ProvisioningException extends RuntimeException {
        public ProvisioningException(String message) {
            super(message);
        }
    }

    /**
     * Creates a partner's account and gives it the role their portal requires.
     *
     * @return the Keycloak {@code sub}, which is the id every service in the platform uses
     */
    public String createPartner(String email, String firstName, String lastName, String role) {
        String bearer = adminToken();

        Map<String, Object> user = Map.of(
                "username", email,
                "email", email,
                "firstName", firstName == null ? "" : firstName,
                "lastName", lastName == null ? "" : lastName,
                "enabled", true,
                // They set their own. See the class note.
                "requiredActions", List.of("UPDATE_PASSWORD"),
                "emailVerified", false);

        String userId;
        try {
            // Same as the customer path: the id comes from the Location header, so a plus-alias in
            // the address cannot leave a created account that we then fail to find.
            ResponseEntity<Void> created = keycloak.post()
                    .uri("/admin/realms/{realm}/users", realm)
                    .header("Authorization", "Bearer " + bearer)
                    .contentType(MediaType.APPLICATION_JSON)
                    .body(user)
                    .retrieve()
                    .toBodilessEntity();
            userId = idFromLocation(created);
        } catch (Exception e) {
            // A 409 means the username is taken, which on this path means somebody already has an
            // account with that email — worth failing loudly rather than attaching a second
            // business to an existing person by accident.
            log.error("Could not create a Keycloak account for {}", email, e);
            throw new ProvisioningException("The account could not be created: " + e.getMessage());
        }


        // No second lookup: userId came from the Location header above.
        assignRealmRole(bearer, userId, role);
        log.info("Provisioned {} as {}", email, role);
        return userId;
    }

    /**
     * Creates a customer's own account, with the password they just chose.
     *
     * <p>Three deliberate differences from {@link #createPartner}, and each of them follows from
     * the customer being present at the keyboard rather than being provisioned later by somebody
     * else:
     *
     * <ul>
     *   <li>The password is set here, not left as an {@code UPDATE_PASSWORD} required action. A
     *       shopper who has just typed a password twice should not be asked for a new one at their
     *       first login.
     *   <li>{@code emailVerified} is true. It genuinely is — a one-time code was sent to that
     *       address and answered before this is called, and the proof is spent in the same
     *       transaction.
     *   <li>The role is CUSTOMER. Nothing on this path can grant anything else; a merchant or a
     *       rider account is what the reviewed onboarding flow is for.
     * </ul>
     *
     * @return the Keycloak {@code sub}
     */
    public String createCustomer(String email, String firstName, String lastName, String password) {
        String bearer = adminToken();

        Map<String, Object> user = Map.of(
                "username", email,
                "email", email,
                "firstName", firstName == null ? "" : firstName,
                "lastName", lastName == null ? "" : lastName,
                "enabled", true,
                // Verified before we got here — see the class note.
                "emailVerified", true,
                "credentials", List.of(Map.of(
                        "type", "password",
                        "value", password,
                        // Not a one-time credential: this is the password they chose and expect to
                        // use. `temporary: true` would force a reset screen on first sign-in.
                        "temporary", false)));

        String userId;
        try {
            // The created id comes back in the Location header, and taking it from there is the
            // whole point of not searching for the account again afterwards.
            //
            // Looking the account up again by email does not survive a plus-alias. The address goes
            // into a query parameter, and a '+' in a query is decoded server-side as a space, so
            // 'me+shop@gmail.com' is searched for as 'me shop@gmail.com' and matches nothing. The
            // account had already been created at that point, so the caller saw a failure, no
            // account, and an orphan in Keycloak — for an address form people genuinely use.
            ResponseEntity<Void> created = keycloak.post()
                    .uri("/admin/realms/{realm}/users", realm)
                    .header("Authorization", "Bearer " + bearer)
                    .contentType(MediaType.APPLICATION_JSON)
                    .body(user)
                    .retrieve()
                    .toBodilessEntity();
            userId = idFromLocation(created);
        } catch (HttpClientErrorException.Conflict e) {
            // 409, and only 409, means somebody already holds that email. Said plainly rather than
            // as a generic failure: the caller has verified the address, so the person on the other
            // end owns it and the useful answer is "you already have an account".
            log.warn("An account already exists for {}", email);
            throw new ProvisioningException("An account already exists for that email address");

        } catch (Exception e) {
            // Everything else is OUR failure and must not be dressed up as a duplicate. This catch
            // used to fold every status into the message above, so a 403 from a service account
            // without manage-users told a brand new user that they already had an account — and
            // sent them off to reset a password for something that did not exist.
            log.error("Could not create a customer account for {}", email, e);
            throw new ProvisioningException(
                    "We could not create the account just now. Please try again in a moment.");
        }

        // No second lookup: userId came from the Location header above.
        assignRealmRole(bearer, userId, "CUSTOMER");
        log.info("Signed up {} as CUSTOMER", email);
        return userId;
    }

    /**
     * Pulls the new account's id out of the {@code Location} header Keycloak returns on 201.
     *
     * <p>Preferred over searching for the account again because it cannot be defeated by how the
     * address is spelled — see the note at the call site about plus-aliases.
     */
    private String idFromLocation(ResponseEntity<Void> created) {
        URI location = created.getHeaders().getLocation();
        if (location == null) {
            throw new ProvisioningException("The account was created but Keycloak returned no id");
        }
        String path = location.getPath();
        String id = path.substring(path.lastIndexOf('/') + 1);
        if (id.isBlank()) {
            throw new ProvisioningException("The account was created but Keycloak returned no id");
        }
        return id;
    }

    private void assignRealmRole(String bearer, String userId, String role) {
        JsonNode representation = keycloak.get()
                .uri("/admin/realms/{realm}/roles/{role}", realm, role)
                .header("Authorization", "Bearer " + bearer)
                .retrieve()
                .body(JsonNode.class);

        if (representation == null || !representation.hasNonNull("id")) {
            throw new ProvisioningException("The realm has no role called " + role);
        }

        keycloak.post()
                .uri("/admin/realms/{realm}/users/{id}/role-mappings/realm", realm, userId)
                .header("Authorization", "Bearer " + bearer)
                .contentType(MediaType.APPLICATION_JSON)
                .body(List.of(Map.of(
                        "id", representation.path("id").asText(),
                        "name", representation.path("name").asText())))
                .retrieve()
                .toBodilessEntity();
    }

    /**
     * A client-credentials token, reused until shortly before it expires.
     *
     * <p>Refreshed early rather than on expiry: a token that runs out mid-request produces a 401
     * that looks like a permissions problem and is not.
     */
    private String adminToken() {
        Cached current = token;
        if (current.usable()) {
            return current.value();
        }
        if (clientSecret == null || clientSecret.isBlank()) {
            throw new ProvisioningException(
                    "No Keycloak service-account secret is configured, so no account can be created");
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
            throw new ProvisioningException("Keycloak refused a service-account token");
        }
        long seconds = response.path("expires_in").asLong(60);
        Cached fresh = new Cached(response.path("access_token").asText(),
                Instant.now().plus(Duration.ofSeconds(Math.max(10, seconds - 30))));
        token = fresh;
        return fresh.value();
    }

}
