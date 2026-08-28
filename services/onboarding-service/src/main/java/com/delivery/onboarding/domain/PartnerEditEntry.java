package com.delivery.onboarding.domain;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * One field of one partner's record, changed by one backoffice user: who, when, from what, to what.
 *
 * <p>A row per changed field rather than a log line, because the question this answers arrives
 * months later — "who changed this partner's contact email, and what was it before" — and a log
 * line has rotated away by then. Immutable once written: every column is {@code updatable = false},
 * because an audit trail that can be edited is testimony that can be coached.
 */
@Entity
@Table(name = "partner_edits")
public class PartnerEditEntry {

    /** The editable fields, by machine name. The service writes these; nothing user-typed does. */
    public enum Field { businessName, contactName, contactEmail, contactPhone }

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "application_id", nullable = false, updatable = false)
    private UUID applicationId;

    @Column(name = "actor", nullable = false, updatable = false, length = 64)
    private String actor;

    @Column(name = "field", nullable = false, updatable = false, length = 40)
    private String field;

    @Column(name = "old_value", updatable = false, length = 500)
    private String oldValue;

    @Column(name = "new_value", updatable = false, length = 500)
    private String newValue;

    @Column(name = "created_at", nullable = false, insertable = false, updatable = false)
    private Instant createdAt;

    protected PartnerEditEntry() {
        // for JPA
    }

    public PartnerEditEntry(UUID applicationId, String actor, Field field,
                            String oldValue, String newValue) {
        this.id = UUID.randomUUID();
        this.applicationId = applicationId;
        this.actor = actor;
        this.field = field.name();
        this.oldValue = oldValue;
        this.newValue = newValue;
    }

    public UUID getId() {
        return id;
    }

    public UUID getApplicationId() {
        return applicationId;
    }

    public String getActor() {
        return actor;
    }

    public String getField() {
        return field;
    }

    public String getOldValue() {
        return oldValue;
    }

    public String getNewValue() {
        return newValue;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }
}
