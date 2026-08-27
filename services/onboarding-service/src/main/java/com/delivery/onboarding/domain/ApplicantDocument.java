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
 * One identity or vehicle document an applicant uploaded, and what a reviewer made of it.
 *
 * <p>The bytes are not here and never pass through this service. They go straight from the
 * applicant's device to the {@code merchant-kyc} bucket with a presigned PUT, and this row is the
 * pointer plus the verdict. See {@code ApplicantDocumentService} for the three-step flow and for
 * why that bucket must stay unrouted.
 *
 * <p>A document's state is deliberately independent of its application's. They are decided by the
 * same person but they are not the same decision: a licence can be refused for a photograph nobody
 * can read while the applicant is perfectly acceptable, and an application can be approved by
 * somebody holding the paper in their hand. Coupling them would force a reviewer to lie in one
 * direction or the other.
 */
@Entity
@Table(name = "applicant_documents")
public class ApplicantDocument {

    public enum Status {
        /** Uploaded, waiting for somebody to look at it. */
        PENDING,
        /** A reviewer read it and accepted it. */
        APPROVED,
        /** A reviewer refused it, with a reason the applicant is shown. */
        REJECTED
    }

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    /** Never updatable: moving a document between applications would move somebody's identity papers. */
    @Column(name = "application_id", nullable = false, updatable = false)
    private UUID applicationId;

    @Enumerated(EnumType.STRING)
    @Column(name = "kind", nullable = false, updatable = false, length = 32)
    private DocumentKind kind;

    /**
     * The {@code file_metadata} row: bucket, object key, and the Keycloak {@code sub} of whoever
     * uploaded it. Held as an id rather than a JPA association because the entity lives in the
     * platform-storage jar and every read of the object goes through {@code StorageService}, which
     * wants the metadata row it loaded itself — not one this entity handed it.
     */
    @Column(name = "file_id", nullable = false, updatable = false)
    private UUID fileId;

    @Column(name = "object_key", nullable = false, updatable = false, length = 512)
    private String objectKey;

    @Column(name = "content_type", nullable = false, updatable = false, length = 128)
    private String contentType;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false, length = 16)
    private Status status = Status.PENDING;

    /** Shown to the applicant. "Rejected" with no reason is the message that produces a phone call. */
    @Column(name = "rejection_reason", length = 500)
    private String rejectionReason;

    /**
     * The reviewer's own note, for other reviewers.
     *
     * <p>A separate column from {@link #rejectionReason} rather than a visibility flag on one
     * column: a flag is one forgotten condition away from showing an applicant what a reviewer
     * wrote about them, and there is no shape of that mistake that is recoverable afterwards.
     * Nothing on an applicant-facing endpoint reads this field.
     */
    @Column(name = "reviewer_note", length = 1000)
    private String reviewerNote;

    @Column(name = "reviewed_at")
    private Instant reviewedAt;

    @Column(name = "reviewed_by", length = 64)
    private String reviewedBy;

    @Column(name = "uploaded_at", nullable = false, insertable = false, updatable = false)
    private Instant uploadedAt;

    /**
     * Set when a newer upload of the same kind takes over.
     *
     * <p>Superseded rather than deleted or overwritten. "Which licence did we approve, and what did
     * the one before it look like" is the first question when a KYC decision is challenged, and an
     * UPDATE in place has no answer to it.
     */
    @Column(name = "superseded_at")
    private Instant supersededAt;

    protected ApplicantDocument() {
        // for JPA
    }

    public ApplicantDocument(UUID applicationId, DocumentKind kind, UUID fileId,
                             String objectKey, String contentType) {
        this.id = UUID.randomUUID();
        this.applicationId = applicationId;
        this.kind = kind;
        this.fileId = fileId;
        this.objectKey = objectKey;
        this.contentType = contentType;
        this.status = Status.PENDING;
    }

    /**
     * @throws IllegalStateException if it has already been decided. A second verdict silently
     *         replacing the first would make the audit trail describe a decision nobody took; a
     *         reviewer who has changed their mind asks the applicant to re-upload, which leaves
     *         both verdicts on the record.
     */
    public void approve(String reviewer, String note) {
        requireUndecided();
        this.status = Status.APPROVED;
        this.reviewedAt = Instant.now();
        this.reviewedBy = reviewer;
        this.reviewerNote = note;
    }

    public void reject(String reviewer, String reason, String note) {
        requireUndecided();
        if (reason == null || reason.isBlank()) {
            throw new IllegalArgumentException("A rejected document has to say why");
        }
        this.status = Status.REJECTED;
        this.reviewedAt = Instant.now();
        this.reviewedBy = reviewer;
        this.rejectionReason = reason;
        this.reviewerNote = note;
    }

    /** Replaced by a newer upload of the same kind. */
    public void supersede() {
        if (this.supersededAt == null) {
            this.supersededAt = Instant.now();
        }
    }

    private void requireUndecided() {
        if (status != Status.PENDING) {
            throw new IllegalStateException(
                    "This document was already " + status.name().toLowerCase());
        }
    }

    public boolean isLive() {
        return supersededAt == null;
    }

    /** True when this document is still holding an application up, from a reviewer's point of view. */
    public boolean isOutstanding() {
        return isLive() && status != Status.APPROVED;
    }

    public UUID getId() {
        return id;
    }

    public UUID getApplicationId() {
        return applicationId;
    }

    public DocumentKind getKind() {
        return kind;
    }

    public UUID getFileId() {
        return fileId;
    }

    public String getObjectKey() {
        return objectKey;
    }

    public String getContentType() {
        return contentType;
    }

    public Status getStatus() {
        return status;
    }

    public String getRejectionReason() {
        return rejectionReason;
    }

    /** Reviewer-only. See the field: nothing on an applicant-facing path may call this. */
    public String getReviewerNote() {
        return reviewerNote;
    }

    public Instant getReviewedAt() {
        return reviewedAt;
    }

    public String getReviewedBy() {
        return reviewedBy;
    }

    public Instant getUploadedAt() {
        return uploadedAt;
    }

    public Instant getSupersededAt() {
        return supersededAt;
    }
}
