package com.delivery.settings.domain;

import java.time.Instant;
import java.util.Map;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

/**
 * Append-only record of every settings change (Section 8).
 *
 * <p>This page can redirect real SMS traffic and, once Phase 4 lands, real money — so who changed
 * what, from what, and when has to be answerable long after the fact. Rows are never updated or
 * deleted.
 */
@Entity
@Table(name = "connector_settings_audit")
public class ConnectorSettingAudit {

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Enumerated(EnumType.STRING)
    @Column(name = "connector_type", nullable = false, length = 32)
    private ConnectorType connectorType;

    /** Null for the first recorded change. */
    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "old_value", columnDefinition = "jsonb")
    private Map<String, Object> oldValue;

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "new_value", nullable = false, columnDefinition = "jsonb")
    private Map<String, Object> newValue;

    @Column(name = "changed_by", nullable = false, length = 64)
    private String changedBy;

    @Column(name = "changed_at", nullable = false)
    private Instant changedAt;

    protected ConnectorSettingAudit() {
        // for JPA
    }

    public ConnectorSettingAudit(ConnectorType connectorType, Map<String, Object> oldValue,
                                 Map<String, Object> newValue, String changedBy) {
        this.id = UUID.randomUUID();
        this.connectorType = connectorType;
        this.oldValue = oldValue;
        this.newValue = newValue;
        this.changedBy = changedBy;
        this.changedAt = Instant.now();
    }

    public UUID getId() {
        return id;
    }

    public ConnectorType getConnectorType() {
        return connectorType;
    }

    public Map<String, Object> getOldValue() {
        return oldValue;
    }

    public Map<String, Object> getNewValue() {
        return newValue;
    }

    public String getChangedBy() {
        return changedBy;
    }

    public Instant getChangedAt() {
        return changedAt;
    }
}
