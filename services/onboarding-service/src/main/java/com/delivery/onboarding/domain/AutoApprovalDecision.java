package com.delivery.onboarding.domain;

import java.time.Instant;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import com.delivery.onboarding.domain.OnboardingApplication.Kind;

/**
 * The portal's standing decision about one kind: approved on submission, or reviewed by a person.
 *
 * <p>One row per kind, and <strong>the absence of a row is meaningful</strong> — it is what
 * {@link AutoApprovalSource#CONFIG} reports. A kind nobody has decided has no row here and falls
 * back to the deployed {@code delivery.onboarding.auto-approve.*} default, which is what lets this
 * feature land in a running environment without changing what that environment does.
 *
 * <p>Mutable, unlike {@link AutoApprovalAudit} beside it, because this row is the current position
 * rather than the history: the history is the audit table, and it is append-only precisely so that
 * overwriting this row loses nothing.
 */
@Entity
@Table(name = "auto_approval_settings")
public class AutoApprovalDecision {

    @Id
    @Enumerated(EnumType.STRING)
    @Column(name = "kind", nullable = false, updatable = false, length = 16)
    private Kind kind;

    /** true = applications of this kind are approved on submission, with no human review. */
    @Column(name = "automatic", nullable = false)
    private boolean automatic;

    /** The Keycloak sub of the BACKOFFICE user who last set it. Read from the token, never sent. */
    @Column(name = "changed_by", nullable = false, length = 64)
    private String changedBy;

    /**
     * Stamped by the service rather than by the database default.
     *
     * <p>The API returns this timestamp in the same response that writes it, and a column populated
     * by {@code DEFAULT now()} is not readable from the entity until the row is fetched back — so
     * the deployment default would answer the PUT with a null {@code lastChangedAt} and the honest
     * value only on the next GET.
     */
    @Column(name = "changed_at", nullable = false)
    private Instant changedAt;

    protected AutoApprovalDecision() {
        // for JPA
    }

    public AutoApprovalDecision(Kind kind, boolean automatic, String changedBy, Instant changedAt) {
        this.kind = kind;
        this.automatic = automatic;
        this.changedBy = changedBy;
        this.changedAt = changedAt;
    }

    /** Records a new position for this kind. The previous one survives in the audit table. */
    public void change(boolean automatic, String changedBy, Instant changedAt) {
        this.automatic = automatic;
        this.changedBy = changedBy;
        this.changedAt = changedAt;
    }

    public Kind getKind() {
        return kind;
    }

    public boolean isAutomatic() {
        return automatic;
    }

    public String getChangedBy() {
        return changedBy;
    }

    public Instant getChangedAt() {
        return changedAt;
    }
}
