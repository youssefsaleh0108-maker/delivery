package com.delivery.accounting.api;

import java.util.Map;
import java.util.regex.Pattern;

import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;

import com.delivery.accounting.service.CashFloatService;

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

    /**
     * What a client's idempotency key may look like, on every cash route that takes one: a uuid or a
     * similar opaque token, and never longer than the {@code request_key} column. Checked before
     * anything is recorded, so a key the database would refuse at commit is a 400 the client can act
     * on rather than a 500. Kept here, beside the caller, so the routes cannot accept two shapes —
     * which is how one of them came to take a key its column could not hold.
     */
    static final Pattern REQUEST_KEY = Pattern.compile("^[A-Za-z0-9_-]{8,64}$");

    private Callers() {
    }

    /**
     * Why a client's request key is refused, or null when there is no key or it is fine.
     *
     * <p>The shape is {@link #REQUEST_KEY}. On top of it, a key starting {@code payroll-} is refused
     * on every route a person calls: a pay run records its cash deduction under a key derived from
     * the run and the rider, both of which are on the company's own pages, and a hand-over recorded
     * under that key just before the run was approved would otherwise stand in for the deduction —
     * see {@link CashFloatService#PAYROLL_KEY_PREFIX}. Nobody at a counter needs such a key.
     */
    static String requestKeyProblem(String key) {
        if (key == null) {
            return null;
        }
        if (!REQUEST_KEY.matcher(key).matches()) {
            return "requestKey must be 8 to 64 letters, digits, - or _";
        }
        if (CashFloatService.isPayrollKey(key)) {
            return "requestKey must not start with " + CashFloatService.PAYROLL_KEY_PREFIX
                    + ": those keys belong to pay runs";
        }
        return null;
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
