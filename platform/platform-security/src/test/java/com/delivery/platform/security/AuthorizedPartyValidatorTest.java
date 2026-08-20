package com.delivery.platform.security;

import java.time.Instant;
import java.util.List;
import java.util.Map;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.security.oauth2.core.OAuth2TokenValidatorResult;
import org.springframework.security.oauth2.jwt.Jwt;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * The check that stops one realm from meaning one blanket permission.
 *
 * <p>Spring validates issuer, signature and expiry and stops there. Every service here trusts the
 * same Keycloak realm, so without this validator a token minted for any client in that realm is
 * accepted by every service — and the day someone adds a partner integration or an internal tool to
 * the realm, that client silently inherits the whole API surface. The finding is recorded in the
 * Phase 5 security review; these are its regression tests.
 */
class AuthorizedPartyValidatorTest {

    private static final List<String> PLATFORM_CLIENTS =
            List.of("mobile-app", "merchant-portal", "backoffice-web", "carrier-portal");

    private static Jwt tokenFrom(String azp) {
        Jwt.Builder builder = Jwt.withTokenValue("token")
                .header("alg", "RS256")
                .subject("user-sub")
                .claim("realm_access", Map.of("roles", List.of("CUSTOMER")))
                .issuedAt(Instant.now())
                .expiresAt(Instant.now().plusSeconds(300));
        if (azp != null) {
            builder.claim("azp", azp);
        }
        return builder.build();
    }

    @Nested
    @DisplayName("with an allow-list configured")
    class Enforcing {

        private final AuthorizedPartyValidator validator =
                new AuthorizedPartyValidator(PLATFORM_CLIENTS);

        @Test
        void accepts_every_client_this_platform_serves() {
            for (String client : PLATFORM_CLIENTS) {
                assertThat(validator.validate(tokenFrom(client)).hasErrors())
                        .as("token from %s", client)
                        .isFalse();
            }
        }

        /** The case the validator exists for: a real, correctly signed token from the same realm. */
        @Test
        void refuses_a_client_from_the_same_realm_that_is_not_ours() {
            OAuth2TokenValidatorResult result = validator.validate(tokenFrom("partner-integration"));

            assertThat(result.hasErrors()).isTrue();
            assertThat(result.getErrors()).first()
                    .satisfies(error -> assertThat(error.getErrorCode()).isEqualTo("invalid_token"));
        }

        /**
         * A token with no {@code azp} must fail closed. Failing open would make the check trivially
         * bypassable by anyone able to mint a token without that claim.
         */
        @Test
        void refuses_a_token_with_no_authorized_party_claim() {
            assertThat(validator.validate(tokenFrom(null)).hasErrors()).isTrue();
        }

        @Test
        void refuses_a_blank_authorized_party() {
            assertThat(validator.validate(tokenFrom("")).hasErrors()).isTrue();
        }

        /** Client ids are case-sensitive in Keycloak, so the comparison here must be too. */
        @Test
        void does_not_match_a_client_id_on_case_alone() {
            assertThat(validator.validate(tokenFrom("Mobile-App")).hasErrors()).isTrue();
        }

        /** The rejection is generic on purpose — it must not tell a caller who is on the list. */
        @Test
        void the_rejection_does_not_name_the_allowed_clients() {
            OAuth2TokenValidatorResult result = validator.validate(tokenFrom("attacker-client"));

            assertThat(result.getErrors()).first().satisfies(error ->
                    assertThat(error.getDescription()).doesNotContain("mobile-app", "backoffice"));
        }
    }

    @Nested
    @DisplayName("with an empty allow-list")
    class Disabled {

        /** Opting out has to be possible, for a service that genuinely serves an open client set. */
        @Test
        void accepts_anything_so_a_service_can_opt_out() {
            AuthorizedPartyValidator validator = new AuthorizedPartyValidator(List.of());

            assertThat(validator.validate(tokenFrom("anything-at-all")).hasErrors()).isFalse();
            assertThat(validator.validate(tokenFrom(null)).hasErrors()).isFalse();
        }
    }

    /**
     * The allow-list is copied at construction, so a caller mutating the list it passed in cannot
     * widen the accepted set of a validator that is already running.
     */
    @Test
    void the_allow_list_cannot_be_widened_after_construction() {
        List<String> mutable = new java.util.ArrayList<>(List.of("mobile-app"));
        AuthorizedPartyValidator validator = new AuthorizedPartyValidator(mutable);

        mutable.add("smuggled-client");

        assertThat(validator.validate(tokenFrom("smuggled-client")).hasErrors()).isTrue();
    }
}
