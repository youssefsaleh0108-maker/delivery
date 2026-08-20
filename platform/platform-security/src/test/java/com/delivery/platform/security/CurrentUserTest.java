package com.delivery.platform.security;

import java.time.Instant;
import java.util.List;
import java.util.Map;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * Reading the caller's identity out of the validated token.
 *
 * <p>Ownership across this platform — a merchant editing only their own products, a rider seeing
 * only their own jobs — is enforced against {@code sub}, and this is the only place that claim is
 * read. The tests that matter are the negative ones: an unauthenticated context must never quietly
 * produce a user id, because a service that treats an empty id as "matches everything" turns an
 * ownership check into an open door.
 */
class CurrentUserTest {

    @AfterEach
    void clearContext() {
        SecurityContextHolder.clearContext();
    }

    private static void authenticateAs(String subject, String... roles) {
        Jwt jwt = Jwt.withTokenValue("token")
                .header("alg", "RS256")
                .subject(subject)
                .claim("preferred_username", "merchant")
                .claim("email", "merchant@example.test")
                .issuedAt(Instant.now())
                .expiresAt(Instant.now().plusSeconds(300))
                .build();
        List<SimpleGrantedAuthority> authorities =
                java.util.Arrays.stream(roles).map(SimpleGrantedAuthority::new).toList();
        SecurityContextHolder.getContext()
                .setAuthentication(new JwtAuthenticationToken(jwt, authorities));
    }

    @Nested
    @DisplayName("when the request carries a token")
    class Authenticated {

        @Test
        void the_subject_claim_is_the_user_id() {
            authenticateAs("keycloak-sub-123");

            assertThat(CurrentUser.id()).contains("keycloak-sub-123");
            assertThat(CurrentUser.requireId()).isEqualTo("keycloak-sub-123");
        }

        @Test
        void the_profile_claims_are_readable() {
            authenticateAs("keycloak-sub-123");

            assertThat(CurrentUser.username()).contains("merchant");
            assertThat(CurrentUser.email()).contains("merchant@example.test");
        }

        @Test
        void a_held_role_is_recognised_with_or_without_the_prefix() {
            authenticateAs("sub", "ROLE_MERCHANT");

            assertThat(CurrentUser.hasRole("MERCHANT")).isTrue();
            assertThat(CurrentUser.hasRole("ROLE_MERCHANT")).isTrue();
        }

        @Test
        void a_role_the_caller_does_not_hold_is_refused() {
            authenticateAs("sub", "ROLE_CUSTOMER");

            assertThat(CurrentUser.hasRole("BACKOFFICE")).isFalse();
        }

        /** Role names are exact. A caller holding MERCHANT is not a MERCHANT_ADMIN. */
        @Test
        void role_matching_is_exact_rather_than_a_prefix_match() {
            authenticateAs("sub", "ROLE_MERCHANT");

            assertThat(CurrentUser.hasRole("MERCHANT_ADMIN")).isFalse();
            assertThat(CurrentUser.hasRole("MERCH")).isFalse();
        }
    }

    @Nested
    @DisplayName("when there is no token")
    class Anonymous {

        @Test
        void there_is_no_user_id_at_all() {
            assertThat(CurrentUser.id()).isEmpty();
            assertThat(CurrentUser.jwt()).isEmpty();
            assertThat(CurrentUser.username()).isEmpty();
            assertThat(CurrentUser.email()).isEmpty();
        }

        /**
         * Loud rather than empty. A silent null here becomes a merchant id of {@code null} in an
         * ownership query, and what that matches depends on the query — which is not a thing to
         * leave to chance on a write path.
         */
        @Test
        void requiring_an_id_fails_loudly_instead_of_returning_nothing() {
            assertThatThrownBy(CurrentUser::requireId)
                    .isInstanceOf(IllegalStateException.class)
                    .hasMessageContaining("No authenticated subject");
        }

        @Test
        void no_role_is_held() {
            assertThat(CurrentUser.hasRole("BACKOFFICE")).isFalse();
        }
    }

    @Nested
    @DisplayName("when the context holds a non-JWT authentication")
    class OtherAuthentication {

        /**
         * A form-login or basic-auth token has no {@code sub} claim to trust. Treating its principal
         * name as a Keycloak user id would let a non-OIDC authentication satisfy an ownership check.
         */
        @Test
        void it_is_not_mistaken_for_a_platform_user() {
            SecurityContextHolder.getContext().setAuthentication(
                    new UsernamePasswordAuthenticationToken("someone", "password",
                            List.of(new SimpleGrantedAuthority("ROLE_MERCHANT"))));

            assertThat(CurrentUser.id()).isEmpty();
            assertThat(CurrentUser.jwt()).isEmpty();
            assertThatThrownBy(CurrentUser::requireId).isInstanceOf(IllegalStateException.class);
        }

        /** Authorities still apply — role checks are not an OIDC-only concern. */
        @Test
        void its_authorities_are_still_honoured_for_role_checks() {
            SecurityContextHolder.getContext().setAuthentication(
                    new UsernamePasswordAuthenticationToken("someone", "password",
                            List.of(new SimpleGrantedAuthority("ROLE_MERCHANT"))));

            assertThat(CurrentUser.hasRole("MERCHANT")).isTrue();
        }
    }

    /** Claims the token simply does not carry read as empty rather than throwing. */
    @Test
    void a_token_missing_the_optional_profile_claims_is_tolerated() {
        Jwt bare = Jwt.withTokenValue("token")
                .header("alg", "RS256")
                .subject("sub-only")
                .claim("realm_access", Map.of("roles", List.of("CUSTOMER")))
                .issuedAt(Instant.now())
                .expiresAt(Instant.now().plusSeconds(300))
                .build();
        SecurityContextHolder.getContext()
                .setAuthentication(new JwtAuthenticationToken(bare, List.of()));

        assertThat(CurrentUser.id()).contains("sub-only");
        assertThat(CurrentUser.username()).isEmpty();
        assertThat(CurrentUser.email()).isEmpty();
    }
}
