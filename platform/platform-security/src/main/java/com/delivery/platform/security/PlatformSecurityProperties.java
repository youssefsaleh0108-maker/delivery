package com.delivery.platform.security;

import java.util.ArrayList;
import java.util.List;

import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "delivery.security")
public class PlatformSecurityProperties {

    /**
     * Whether the shared default security chain is contributed at all. Set false in a service that
     * wants to write its own {@code SecurityFilterChain} from scratch rather than layering on top.
     */
    private boolean enabled = true;

    /**
     * Keycloak client ids whose {@code resource_access.<id>.roles} should also be mapped to
     * authorities. Realm roles are always mapped; this is only needed once client-level sub-roles
     * are introduced.
     */
    private List<String> clientIds = new ArrayList<>();

    /**
     * Client ids whose tokens this service accepts, matched against the {@code azp} claim.
     *
     * <p>Empty disables the check. See {@link AuthorizedPartyValidator} for why this is not the
     * same list as {@link #clientIds} and why it is {@code azp} rather than {@code aud}.
     */
    private List<String> allowedClientIds = new ArrayList<>();

    /**
     * Paths reachable without a token. Kept deliberately short — actuator probes and API docs.
     * Anything else should be opened by the owning service's own chain, so a permit-all can never
     * be introduced platform-wide by accident.
     */
    private List<String> permitAll = new ArrayList<>(List.of(
            "/actuator/health",
            "/actuator/health/**",
            "/actuator/info",
            "/actuator/prometheus",
            "/v3/api-docs/**",
            "/swagger-ui/**",
            "/swagger-ui.html"
    ));

    public boolean isEnabled() {
        return enabled;
    }

    public void setEnabled(boolean enabled) {
        this.enabled = enabled;
    }

    public List<String> getClientIds() {
        return clientIds;
    }

    public void setClientIds(List<String> clientIds) {
        this.clientIds = clientIds;
    }

    public List<String> getAllowedClientIds() {
        return allowedClientIds;
    }

    public void setAllowedClientIds(List<String> allowedClientIds) {
        this.allowedClientIds = allowedClientIds;
    }

    public List<String> getPermitAll() {
        return permitAll;
    }

    public void setPermitAll(List<String> permitAll) {
        this.permitAll = permitAll;
    }
}
