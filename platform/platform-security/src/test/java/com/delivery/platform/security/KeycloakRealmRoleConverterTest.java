package com.delivery.platform.security;

import java.time.Instant;
import java.util.Collection;
import java.util.List;
import java.util.Map;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.oauth2.jwt.Jwt;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Keycloak's claim shape translated into Spring Security authorities.
 *
 * <p>This converter is the hinge every {@code hasRole(...)} in the platform turns on. If it silently
 * produces nothing — a claim missing, a role in an unexpected case, a resource_access block shaped
 * differently than expected — every endpoint guarded by a role check refuses every caller, and the
 * symptom shows up as a blanket 403 with no obvious cause. Each of those shapes is pinned here.
 */
class KeycloakRealmRoleConverterTest {

    private static Jwt jwt(Map<String, Object> claims) {
        Jwt.Builder builder = Jwt.withTokenValue("token")
                .header("alg", "RS256")
                .subject("user-sub")
                .issuedAt(Instant.now())
                .expiresAt(Instant.now().plusSeconds(300));
        claims.forEach(builder::claim);
        return builder.build();
    }

    private static Jwt withRealmRoles(Object... roles) {
        return jwt(Map.of("realm_access", Map.of("roles", List.of(roles))));
    }

    private static List<String> namesOf(Collection<GrantedAuthority> authorities) {
        return authorities.stream().map(GrantedAuthority::getAuthority).toList();
    }

    @Nested
    @DisplayName("realm roles")
    class RealmRoles {

        @Test
        void become_role_prefixed_authorities() {
            Collection<GrantedAuthority> authorities =
                    new KeycloakRealmRoleConverter().convert(withRealmRoles("MERCHANT", "CUSTOMER"));

            assertThat(namesOf(authorities))
                    .containsExactlyInAnyOrder("ROLE_MERCHANT", "ROLE_CUSTOMER");
        }

        /** The four roles Section 3 defines, checked together so a rename cannot pass unnoticed. */
        @Test
        void cover_the_four_platform_roles() {
            Collection<GrantedAuthority> authorities = new KeycloakRealmRoleConverter()
                    .convert(withRealmRoles("CUSTOMER", "DELIVERY", "MERCHANT", "BACKOFFICE"));

            assertThat(namesOf(authorities)).containsExactlyInAnyOrder(
                    "ROLE_CUSTOMER", "ROLE_DELIVERY", "ROLE_MERCHANT", "ROLE_BACKOFFICE");
        }

        /** A realm exported with lower-case roles still has to line up with hasRole('MERCHANT'). */
        @Test
        void are_normalised_to_upper_case() {
            Collection<GrantedAuthority> authorities =
                    new KeycloakRealmRoleConverter().convert(withRealmRoles("merchant"));

            assertThat(namesOf(authorities)).containsExactly("ROLE_MERCHANT");
        }

        /** Keycloak's own composite roles use hyphens; Spring role names cannot. */
        @Test
        void have_hyphens_folded_to_underscores() {
            Collection<GrantedAuthority> authorities =
                    new KeycloakRealmRoleConverter().convert(withRealmRoles("backoffice-admin"));

            assertThat(namesOf(authorities)).containsExactly("ROLE_BACKOFFICE_ADMIN");
        }

        /** A role already carrying the prefix must not come out as ROLE_ROLE_MERCHANT. */
        @Test
        void are_not_double_prefixed() {
            Collection<GrantedAuthority> authorities =
                    new KeycloakRealmRoleConverter().convert(withRealmRoles("ROLE_MERCHANT"));

            assertThat(namesOf(authorities)).containsExactly("ROLE_MERCHANT");
        }

        @Test
        void deduplicate_when_the_same_role_arrives_twice() {
            Collection<GrantedAuthority> authorities = new KeycloakRealmRoleConverter()
                    .convert(withRealmRoles("MERCHANT", "merchant", "ROLE_MERCHANT"));

            assertThat(namesOf(authorities)).containsExactly("ROLE_MERCHANT");
        }
    }

    @Nested
    @DisplayName("malformed or missing claims")
    class Defensive {

        /** A service token has no realm_access at all. It must convert to nothing, not throw. */
        @Test
        void a_token_with_no_realm_access_yields_no_authorities() {
            assertThat(new KeycloakRealmRoleConverter().convert(jwt(Map.of()))).isEmpty();
        }

        @Test
        void a_realm_access_block_with_no_roles_key_yields_no_authorities() {
            Jwt token = jwt(Map.of("realm_access", Map.of("other", "value")));

            assertThat(new KeycloakRealmRoleConverter().convert(token)).isEmpty();
        }

        /** Anything but a collection here is a malformed token, not a reason to 500. */
        @Test
        void a_roles_claim_of_the_wrong_type_yields_no_authorities() {
            Jwt token = jwt(Map.of("realm_access", Map.of("roles", "MERCHANT")));

            assertThat(new KeycloakRealmRoleConverter().convert(token)).isEmpty();
        }

        @Test
        void blank_and_whitespace_role_names_are_dropped() {
            Collection<GrantedAuthority> authorities = new KeycloakRealmRoleConverter()
                    .convert(withRealmRoles("MERCHANT", "", "   "));

            assertThat(namesOf(authorities)).containsExactly("ROLE_MERCHANT");
        }

        @Test
        void surrounding_whitespace_is_trimmed_rather_than_baked_into_the_authority() {
            Collection<GrantedAuthority> authorities =
                    new KeycloakRealmRoleConverter().convert(withRealmRoles("  MERCHANT  "));

            assertThat(namesOf(authorities)).containsExactly("ROLE_MERCHANT");
        }
    }

    @Nested
    @DisplayName("client roles")
    class ClientRoles {

        private Jwt withBoth() {
            return jwt(Map.of(
                    "realm_access", Map.of("roles", List.of("BACKOFFICE")),
                    "resource_access", Map.of(
                            "backoffice-web", Map.of("roles", List.of("BACKOFFICE_ADMIN")),
                            "some-other-client", Map.of("roles", List.of("SHOULD_NOT_APPEAR")))));
        }

        /** Ignored unless a client id is configured — that is what keeps the default surface small. */
        @Test
        void are_ignored_when_no_client_id_is_configured() {
            Collection<GrantedAuthority> authorities =
                    new KeycloakRealmRoleConverter().convert(withBoth());

            assertThat(namesOf(authorities)).containsExactly("ROLE_BACKOFFICE");
        }

        @Test
        void are_added_for_the_configured_client_only() {
            Collection<GrantedAuthority> authorities =
                    new KeycloakRealmRoleConverter(List.of("backoffice-web")).convert(withBoth());

            assertThat(namesOf(authorities))
                    .containsExactlyInAnyOrder("ROLE_BACKOFFICE", "ROLE_BACKOFFICE_ADMIN");
            assertThat(namesOf(authorities)).doesNotContain("ROLE_SHOULD_NOT_APPEAR");
        }

        /** A configured client the token happens not to carry is normal, not an error. */
        @Test
        void a_configured_client_absent_from_the_token_is_skipped() {
            Collection<GrantedAuthority> authorities =
                    new KeycloakRealmRoleConverter(List.of("not-in-this-token"))
                            .convert(withBoth());

            assertThat(namesOf(authorities)).containsExactly("ROLE_BACKOFFICE");
        }

        @Test
        void a_token_with_no_resource_access_block_is_tolerated() {
            Collection<GrantedAuthority> authorities =
                    new KeycloakRealmRoleConverter(List.of("backoffice-web"))
                            .convert(withRealmRoles("BACKOFFICE"));

            assertThat(namesOf(authorities)).containsExactly("ROLE_BACKOFFICE");
        }
    }
}
