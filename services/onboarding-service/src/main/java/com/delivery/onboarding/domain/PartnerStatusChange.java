package com.delivery.onboarding.domain;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * One act on a partner's standing: suspended, or reinstated — with the typed reason and the actor.
 *
 * <p>History rather than a flag, deliberately. The current state is the newest row (no rows means
 * active), and every earlier row stays: "why was this partner suspended in March, and who lifted
 * it in May" is a query against this table and nothing else. Rows are immutable for the same
 * reason {@link PartnerEditEntry} rows are.
 *
 * <p>What a suspension actually does lives elsewhere: the live realm role is revoked in Keycloak,
 * so every committing endpoint across the platform — publishing goods, claiming a delivery,
 * dispatching a fleet — refuses on its own {@code @PreAuthorize}. The sign-in itself keeps
 * working, which is a feature: a suspended partner's money and history must stay reachable.
 */
@Entity
@Table(name = "partner_status_changes")
public class PartnerStatusChange {

    /**
     * Why access was pulled, from a fixed vocabulary so suspensions can be counted by cause.
     * The free-text note beside it is for the sentence; this is for the query.
     */
    public enum Reason { FRAUD, ABUSE, NON_PAYMENT, POLICY_VIOLATION, PARTNER_REQUEST, OTHER }

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "application_id", nullable = false, updatable = false)
    private UUID applicationId;

    /**
     * The Keycloak account whose role was actually revoked or re-granted. Denormalised from the
     * application so the answer to "whose access did we change" cannot move under later edits.
     */
    @Column(name = "user_ref", nullable = false, updatable = false, length = 64)
    private String userRef;

    /** true records a suspension, false a reinstatement. */
    @Column(name = "suspended", nullable = false, updatable = false)
    private boolean suspended;

    @Enumerated(EnumType.STRING)
    @Column(name = "reason", updatable = false, length = 32)
    private Reason reason;

    @Column(name = "reason_note", updatable = false, length = 500)
    private String reasonNote;

    @Column(name = "actor", nullable = false, updatable = false, length = 64)
    private String actor;

    @Column(name = "created_at", nullable = false, insertable = false, updatable = false)
    private Instant createdAt;

    protected PartnerStatusChange() {
        // for JPA
    }

    private PartnerStatusChange(UUID applicationId, String userRef, boolean suspended,
                                Reason reason, String reasonNote, String actor) {
        this.id = UUID.randomUUID();
        this.applicationId = applicationId;
        this.userRef = userRef;
        this.suspended = suspended;
        this.reason = reason;
        this.reasonNote = reasonNote;
        this.actor = actor;
    }

    /** A suspension has to say why — enforced here and by the database CHECK, so neither can lie. */
    public static PartnerStatusChange suspension(UUID applicationId, String userRef,
                                                 Reason reason, String reasonNote, String actor) {
        if (reason == null) {
            throw new IllegalArgumentException("A suspension has to say why");
        }
        return new PartnerStatusChange(applicationId, userRef, true, reason, reasonNote, actor);
    }

    /** A reinstatement needs no cause beyond the actor who decided it; the note may carry one. */
    public static PartnerStatusChange reinstatement(UUID applicationId, String userRef,
                                                    String reasonNote, String actor) {
        return new PartnerStatusChange(applicationId, userRef, false, null, reasonNote, actor);
    }

    public UUID getId() {
        return id;
    }

    public UUID getApplicationId() {
        return applicationId;
    }

    public String getUserRef() {
        return userRef;
    }

    public boolean isSuspended() {
        return suspended;
    }

    public Reason getReason() {
        return reason;
    }

    public String getReasonNote() {
        return reasonNote;
    }

    public String getActor() {
        return actor;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }
}
