package com.delivery.platform.security;

import java.util.List;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.security.oauth2.core.OAuth2Error;
import org.springframework.security.oauth2.core.OAuth2TokenValidator;
import org.springframework.security.oauth2.core.OAuth2TokenValidatorResult;
import org.springframework.security.oauth2.jwt.Jwt;

/**
 * Rejects a token that was issued to a client this platform does not serve.
 *
 * <p><strong>Why this is needed.</strong> Spring's default JWT validation checks the issuer, the
 * signature and the expiry — and nothing else. Every service in this platform trusts the same
 * Keycloak realm, so without this check a token minted for <em>any</em> client in that realm is
 * accepted by <em>every</em> service. Today the realm only holds our own clients and the realm-role
 * checks catch most of it, but the first partner integration or internal tool added to the realm
 * silently inherits access to the whole API surface. That is a configuration change in Keycloak
 * becoming a security change in fifteen services, with nothing in this repo to notice it.
 *
 * <p><strong>Why {@code azp} and not {@code aud}.</strong> Keycloak leaves {@code aud} empty on the
 * tokens it issues to these public clients — audience only appears once an audience mapper is
 * configured per client. {@code azp} (authorized party) is populated by default and names the
 * client the token was issued to, which is exactly the question being asked. Validating {@code aud}
 * instead would require a realm change per client and would fail closed the moment someone forgot
 * one, which is a worse failure mode than this.
 *
 * <p>Disabled when the allow-list is empty, so a service that genuinely serves an open set of
 * clients can opt out rather than being forced to enumerate them.
 */
public class AuthorizedPartyValidator implements OAuth2TokenValidator<Jwt> {

    private static final Logger log = LoggerFactory.getLogger(AuthorizedPartyValidator.class);

    private static final String CLAIM = "azp";

    private final List<String> allowed;

    public AuthorizedPartyValidator(List<String> allowed) {
        this.allowed = List.copyOf(allowed);
    }

    @Override
    public OAuth2TokenValidatorResult validate(Jwt token) {
        if (allowed.isEmpty()) {
            return OAuth2TokenValidatorResult.success();
        }

        String azp = token.getClaimAsString(CLAIM);
        if (azp != null && allowed.contains(azp)) {
            return OAuth2TokenValidatorResult.success();
        }

        // Logged at WARN with the client but never the token: this is either a misconfiguration
        // worth finding quickly, or someone presenting a credential from elsewhere in the realm.
        log.warn("Rejecting token issued to client '{}' - not in the allowed set {}", azp, allowed);

        return OAuth2TokenValidatorResult.failure(new OAuth2Error(
                "invalid_token",
                "The token was issued to a client this service does not accept",
                null));
    }
}
