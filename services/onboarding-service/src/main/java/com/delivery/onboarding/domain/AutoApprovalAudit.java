package com.delivery.onboarding.domain;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import com.delivery.onboarding.domain.OnboardingApplication.Kind;

/**
 * Append-only record of every auto-approval change: which kind, from what, to what, by whom, when.
 *
 * <p>The same shape and the same rule as {@code ConnectorSettingAudit} in connector-settings — rows
 * are never updated or deleted — because the question is the same one asked later: this switch
 * decides whether a stranger becomes a live merchant without anybody reading their papers, and
 * "who turned it on, and what was it before" has to be answerable long after the person who did it
 * has left.
 *
 * <p>Where it differs is {@link #oldSource}. The connector table stores a null old value for a
 * first change; here the value actually in force is always recorded, with a flag saying whether it
 * was the deployment default or an earlier portal decision. A null would throw away the fact that
 * matters most about a first change — whether the kind was already automatic via the environment
 * when somebody pinned it, or whether that click is what switched it on.
 */
@Entity
@Table(name = "auto_approval_audit")
public class AutoApprovalAudit {

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Enumerated(EnumType.STRING)
    @Column(name = "kind", nullable = false, updatable = false, length = 16)
    private Kind kind;

    @Column(name = "old_automatic", nullable = false, updatable = false)
    private boolean oldAutomatic;

    /** Where {@link #oldAutomatic} came from: the deployment default, or an earlier decision. */
    @Enumerated(EnumType.STRING)
    @Column(name = "old_source", nullable = false, updatable = false, length = 8)
    private AutoApprovalSource oldSource;

    /** No matching source column: everything written to this table is a portal decision. */
    @Column(name = "new_automatic", nullable = false, updatable = false)
    private boolean newAutomatic;

    @Column(name = "changed_by", nullable = false, updatable = false, length = 64)
    private String changedBy;

    @Column(name = "changed_at", nullable = false, updatable = false)
    private Instant changedAt;

    protected AutoApprovalAudit() {
        // for JPA
    }

    public AutoApprovalAudit(Kind kind, boolean oldAutomatic, AutoApprovalSource oldSource,
                             boolean newAutomatic, String changedBy, Instant changedAt) {
        this.id = UUID.randomUUID();
        this.kind = kind;
        this.oldAutomatic = oldAutomatic;
        this.oldSource = oldSource;
        this.newAutomatic = newAutomatic;
        this.changedBy = changedBy;
        this.changedAt = changedAt;
    }

    public UUID getId() {
        return id;
    }

    public Kind getKind() {
        return kind;
    }

    public boolean isOldAutomatic() {
        return oldAutomatic;
    }

    public AutoApprovalSource getOldSource() {
        return oldSource;
    }

    public boolean isNewAutomatic() {
        return newAutomatic;
    }

    public String getChangedBy() {
        return changedBy;
    }

    public Instant getChangedAt() {
        return changedAt;
    }
}
