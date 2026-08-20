package com.delivery.platform.security;

import java.util.Optional;

import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;

/**
 * Reads the calling user's identity out of the validated access token.
 *
 * <p>Section 3 is explicit that ownership is enforced in service code against the {@code sub}
 * claim, not by Keycloak alone — this is the single place that claim gets read, so a service never
 * has to reach into the SecurityContext by hand and accidentally trust a client-supplied user id.
 */
public final class CurrentUser {

    private CurrentUser() {
    }

    /** The Keycloak user id ({@code sub}) of the caller, if the request is authenticated. */
    public static Optional<String> id() {
        return jwt().map(Jwt::getSubject);
    }

    /**
     * The caller's user id, or a thrown {@link IllegalStateException} if there isn't one. Use this
     * on paths that are already behind an authenticated route, where an anonymous caller is a bug
     * rather than an expected case.
     */
    public static String requireId() {
        return id().orElseThrow(() -> new IllegalStateException(
                "No authenticated subject on the current request - is this endpoint permitAll?"));
    }

    public static Optional<String> username() {
        return jwt().map(jwt -> jwt.getClaimAsString("preferred_username"));
    }

    public static Optional<String> email() {
        return jwt().map(jwt -> jwt.getClaimAsString("email"));
    }

    /** True when the caller holds the given realm role, e.g. {@code hasRole("BACKOFFICE")}. */
    public static boolean hasRole(String role) {
        String authority = role.startsWith("ROLE_") ? role : "ROLE_" + role;
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        return authentication != null && authentication.getAuthorities().stream()
                .anyMatch(granted -> authority.equals(granted.getAuthority()));
    }

    public static Optional<Jwt> jwt() {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        return (authentication instanceof JwtAuthenticationToken token)
                ? Optional.of(token.getToken())
                : Optional.empty();
    }
}
