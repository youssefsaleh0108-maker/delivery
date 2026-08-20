package com.delivery.platform.security;

import java.util.Collection;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

import org.springframework.core.convert.converter.Converter;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.util.StringUtils;

/**
 * Maps a Keycloak access token onto Spring Security authorities.
 *
 * <p>Realm roles live under {@code realm_access.roles} and become {@code ROLE_<NAME>} — so the
 * {@code DELIVERY}, {@code MERCHANT}, {@code BACKOFFICE} and {@code CUSTOMER} realm roles from
 * Section 3 are usable directly as {@code hasRole('MERCHANT')}.
 *
 * <p>Client roles under {@code resource_access.<clientId>.roles} are also mapped when a client id
 * is configured, which is how composite sub-roles (BACKOFFICE_ADMIN vs BACKOFFICE_SUPPORT) can be
 * added later without touching this converter.
 *
 * <p>Note this handles authentication-level roles only. Ownership checks — a merchant editing only
 * their own products, a rider seeing only their own assigned orders — are enforced in service code
 * against the {@code sub} claim; see {@link CurrentUser}.
 */
public class KeycloakRealmRoleConverter implements Converter<Jwt, Collection<GrantedAuthority>> {

    private static final String REALM_ACCESS = "realm_access";
    private static final String RESOURCE_ACCESS = "resource_access";
    private static final String ROLES = "roles";
    private static final String ROLE_PREFIX = "ROLE_";

    private final Set<String> clientIds;

    public KeycloakRealmRoleConverter() {
        this(List.of());
    }

    public KeycloakRealmRoleConverter(Collection<String> clientIds) {
        this.clientIds = Set.copyOf(clientIds);
    }

    @Override
    public Collection<GrantedAuthority> convert(Jwt jwt) {
        Set<GrantedAuthority> authorities = new LinkedHashSet<>();
        addRoles(authorities, rolesFrom(jwt.getClaimAsMap(REALM_ACCESS)));

        if (!clientIds.isEmpty()) {
            Map<String, Object> resourceAccess = jwt.getClaimAsMap(RESOURCE_ACCESS);
            if (resourceAccess != null) {
                for (String clientId : clientIds) {
                    Object client = resourceAccess.get(clientId);
                    if (client instanceof Map<?, ?> clientMap) {
                        addRoles(authorities, rolesFrom(clientMap));
                    }
                }
            }
        }
        return authorities;
    }

    private static Collection<?> rolesFrom(Map<?, ?> claim) {
        if (claim == null) {
            return List.of();
        }
        Object roles = claim.get(ROLES);
        return (roles instanceof Collection<?> collection) ? collection : List.of();
    }

    private static void addRoles(Set<GrantedAuthority> target, Collection<?> roles) {
        for (Object role : roles) {
            if (role == null) {
                continue;
            }
            String name = role.toString().trim();
            if (!StringUtils.hasText(name)) {
                continue;
            }
            // Keycloak realm roles are conventionally upper-case already, but normalise so a
            // realm exported with lower-case roles still lines up with hasRole('MERCHANT').
            String normalised = name.toUpperCase(Locale.ROOT).replace('-', '_');
            target.add(new SimpleGrantedAuthority(
                    normalised.startsWith(ROLE_PREFIX) ? normalised : ROLE_PREFIX + normalised));
        }
    }
}
