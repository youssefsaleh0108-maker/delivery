package com.delivery.settings.domain;

import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

@Entity
@Table(name = "connector_settings")
public class ConnectorSetting {

    @Id
    @Enumerated(EnumType.STRING)
    @Column(name = "connector_type", nullable = false, updatable = false, length = 32)
    private ConnectorType connectorType;

    @Column(name = "provider", nullable = false, length = 64)
    private String provider;

    /** Non-secret configuration only. See {@link #assertNoSecrets}. */
    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "config_json", nullable = false, columnDefinition = "jsonb")
    private Map<String, Object> config = new LinkedHashMap<>();

    /** Where the real credentials live. The value itself is never read by this service. */
    @Column(name = "vault_path", length = 255)
    private String vaultPath;

    @Column(name = "secret_rotated_at")
    private Instant secretRotatedAt;

    @Column(name = "is_active", nullable = false)
    private boolean active = true;

    @Column(name = "updated_by", nullable = false, length = 64)
    private String updatedBy;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    protected ConnectorSetting() {
        // for JPA
    }

    /**
     * Applies a change from the Backoffice.
     *
     * @throws IllegalArgumentException if the provider is not one this connector supports, or if
     *         the config looks like it contains a secret
     */
    public void update(String provider, Map<String, Object> config, String changedBy) {
        if (!connectorType.supports(provider)) {
            throw new IllegalArgumentException(
                    provider + " is not a valid provider for " + connectorType
                            + " (expected one of " + connectorType.providers() + ")");
        }
        assertNoSecrets(config);
        assertCanaryIsValid(config);

        this.provider = provider;
        this.config = new LinkedHashMap<>(config);
        this.updatedBy = changedBy;
        this.updatedAt = Instant.now();
    }

    /**
     * Refuses anything that looks like a credential.
     *
     * <p>Section 8 requires secrets to live in Vault and never in this table or the UI. A settings
     * form is exactly where someone will eventually paste an API key "just to test", and once it is
     * committed to a jsonb column it is in backups, in audit rows, and on a Backoffice screen. This
     * makes that mistake fail loudly instead of silently.
     */
    static void assertNoSecrets(Map<String, Object> config) {
        for (String key : config.keySet()) {
            String lower = key.toLowerCase(java.util.Locale.ROOT);
            // Matched on substrings rather than exact names, because the field will be called
            // whatever the person pasting it happens to type. The key-bearing entries are spelled
            // out instead of matching "key" alone: routingKey and idempotencyKey are ordinary
            // config, and rejecting them would push someone towards a worse workaround.
            if (lower.contains("secret") || lower.contains("password") || lower.contains("passphrase")
                    || lower.contains("token") || lower.contains("apikey") || lower.contains("api_key")
                    || lower.contains("privatekey") || lower.contains("private_key")
                    || lower.contains("signingkey") || lower.contains("signing_key")
                    || lower.contains("credential")) {
                throw new IllegalArgumentException(
                        "'" + key + "' looks like a secret. Secrets belong in Vault; store only the "
                                + "vault path here (Section 8).");
            }
        }
    }

    /**
     * Applies the same closed-list rule to a canary as to the primary provider.
     *
     * <p>Phase 6 routes a percentage of traffic to {@code canaryProvider} from this config map. The
     * primary is validated against {@link ConnectorType}, and without this the canary would be an
     * unvalidated free-text field that decides where real messages go — the exact hole the closed
     * provider list exists to close, reopened through the back door.
     *
     * <p>The percentage is checked too. A canary set to a value that will not parse silently routes
     * nothing, which looks identical to a ramp that is working and finding no problems.
     */
    void assertCanaryIsValid(Map<String, Object> config) {
        Object canary = config.get("canaryProvider");
        if (canary == null || String.valueOf(canary).isBlank()) {
            return;
        }
        String name = String.valueOf(canary);
        if (!connectorType.supports(name)) {
            throw new IllegalArgumentException(
                    name + " is not a valid canary provider for " + connectorType
                            + " (expected one of " + connectorType.providers() + ")");
        }

        Object percentage = config.get("canaryPercentage");
        if (percentage == null) {
            throw new IllegalArgumentException(
                    "canaryProvider was set without canaryPercentage, so nothing would be routed to it");
        }
        try {
            int value = Integer.parseInt(String.valueOf(percentage).trim());
            if (value < 0 || value > 100) {
                throw new IllegalArgumentException("canaryPercentage must be between 0 and 100");
            }
        } catch (NumberFormatException e) {
            throw new IllegalArgumentException("canaryPercentage must be a whole number, got " + percentage);
        }
    }

    public Map<String, Object> snapshot() {
        Map<String, Object> snapshot = new LinkedHashMap<>();
        snapshot.put("connectorType", connectorType.name());
        snapshot.put("provider", provider);
        snapshot.put("config", new LinkedHashMap<>(config));
        snapshot.put("active", active);
        return snapshot;
    }

    public ConnectorType getConnectorType() {
        return connectorType;
    }

    public String getProvider() {
        return provider;
    }

    public Map<String, Object> getConfig() {
        return Map.copyOf(config);
    }

    public String getVaultPath() {
        return vaultPath;
    }

    public Instant getSecretRotatedAt() {
        return secretRotatedAt;
    }

    public boolean isActive() {
        return active;
    }

    public String getUpdatedBy() {
        return updatedBy;
    }

    public Instant getUpdatedAt() {
        return updatedAt;
    }
}
