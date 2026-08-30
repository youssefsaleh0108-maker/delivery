package com.delivery.onboarding.api;

import java.util.List;
import java.util.Map;

import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.delivery.onboarding.client.KeycloakAdminClient;

/**
 * The split-payment friend picker's search box.
 *
 * <p>Prefix search on USERNAME only, capped small, returning username and display name and
 * nothing else — the username is the address the split flow speaks, and this endpoint exists so
 * a host can find "@rami.k" without typing it perfectly. Customer role required: the people
 * directory is for people in it.
 */
@RestController
@RequestMapping("/api/profile")
public class UserSearchController {

    private final KeycloakAdminClient keycloak;

    public UserSearchController(KeycloakAdminClient keycloak) {
        this.keycloak = keycloak;
    }

    @GetMapping("/search")
    @PreAuthorize("hasRole('CUSTOMER')")
    public List<Map<String, String>> search(@RequestParam("q") String query) {
        String q = query == null ? "" : query.trim();
        if (q.length() < 2) {
            // One letter matches half the realm; that is a directory dump, not a search.
            return List.of();
        }
        return keycloak.searchByUsername(q, 5);
    }
}
