package com.delivery.accounting.api;

import java.util.Map;

import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;

/**
 * Who is calling, read from the security context — the second lock behind {@code @PreAuthorize}.
 *
 * <p>The same rule {@link StatementController} states: method security is a proxy that a
 * misconfigured filter chain or a direct call can bypass, and on a route that moves another party's
 * money the explicit check is what still holds without it. It is also what lets the refusals be
 * proved from a plain standalone MockMvc test. Shared here rather than copied into each new
 * controller, so the cash routes cannot drift into two slightly different ideas of "the caller".
 */
final class Callers {

    private Callers() {
    }

    /** The caller's token, or null for an anonymous request. */
    static Jwt jwt() {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        return (authentication instanceof JwtAuthenticationToken token) ? token.getToken() : null;
    }

    /**
     * Null when the caller holds {@code role}; otherwise the refusal to return.
     *
     * <p>401 for no token at all, 403 for the wrong role — they are different mistakes and a client
     * should be able to tell "sign in" from "this is not your page".
     */
    static ResponseEntity<?> requireRole(String role) {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        if (authentication == null || jwt() == null) {
            return ResponseEntity.status(401).body(Map.of("error", "Sign in first."));
        }
        boolean holds = authentication.getAuthorities().stream()
                .anyMatch(granted -> ("ROLE_" + role).equals(granted.getAuthority()));
        return holds ? null : ResponseEntity.status(403).body(Map.of(
                "error", "That is a " + role + " view."));
    }
}
