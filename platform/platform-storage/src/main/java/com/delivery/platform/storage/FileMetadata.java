package com.delivery.platform.storage;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.Table;

/**
 * The Postgres-side pointer to a MinIO object, so the application never has to list a bucket to
 * know what exists (Section 4).
 *
 * <p><strong>Deviation from the brief:</strong> Section 4 puts {@code file_metadata} in a single
 * shared {@code files} schema. This table is instead created in each owning service's own schema,
 * the same way {@code outbox_event} is. A single shared table would mean several independently
 * deployed services writing the same rows — the shared-database coupling that schema-per-service
 * exists to prevent, and which the per-schema database roles in Phase 0 physically block anyway.
 * When a dedicated File Service is introduced (Section 5 leaves that open), it can own a
 * consolidated table and this becomes its private one.
 */
@Entity
@Table(name = "file_metadata", indexes = {
        @Index(name = "idx_file_metadata_owner", columnList = "owner_id"),
        @Index(name = "idx_file_metadata_purpose", columnList = "purpose, status")
})
public class FileMetadata {

    public enum Status {
        /**
         * A presigned PUT was issued but the client has not confirmed the upload. Rows can sit here
         * forever if a client abandons an upload, which is why they are excluded from reads.
         */
        PENDING,
        /** The object was confirmed present in the bucket. */
        UPLOADED,
        /** Soft-deleted; the object may or may not still exist in the bucket. */
        DELETED
    }

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "bucket", nullable = false, length = 64)
    private String bucket;

    @Column(name = "object_key", nullable = false, length = 512)
    private String objectKey;

    /** The Keycloak {@code sub} of whoever uploaded it — the basis of every ownership check. */
    @Column(name = "owner_id", nullable = false, length = 64)
    private String ownerId;

    @Column(name = "content_type", nullable = false, length = 128)
    private String contentType;

    @Enumerated(EnumType.STRING)
    @Column(name = "purpose", nullable = false, length = 32)
    private FilePurpose purpose;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false, length = 16)
    private Status status = Status.PENDING;

    @Column(name = "size_bytes")
    private Long sizeBytes;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    @Column(name = "uploaded_at")
    private Instant uploadedAt;

    protected FileMetadata() {
        // for JPA
    }

    public FileMetadata(String bucket, String objectKey, String ownerId,
                        String contentType, FilePurpose purpose) {
        this.id = UUID.randomUUID();
        this.bucket = bucket;
        this.objectKey = objectKey;
        this.ownerId = ownerId;
        this.contentType = contentType;
        this.purpose = purpose;
        this.status = Status.PENDING;
        this.createdAt = Instant.now();
    }

    public void markUploaded(long sizeBytes) {
        this.status = Status.UPLOADED;
        this.sizeBytes = sizeBytes;
        this.uploadedAt = Instant.now();
    }

    public void markDeleted() {
        this.status = Status.DELETED;
    }

    public boolean isOwnedBy(String userId) {
        return this.ownerId.equals(userId);
    }

    public UUID getId() {
        return id;
    }

    public String getBucket() {
        return bucket;
    }

    public String getObjectKey() {
        return objectKey;
    }

    public String getOwnerId() {
        return ownerId;
    }

    public String getContentType() {
        return contentType;
    }

    public FilePurpose getPurpose() {
        return purpose;
    }

    public Status getStatus() {
        return status;
    }

    public Long getSizeBytes() {
        return sizeBytes;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public Instant getUploadedAt() {
        return uploadedAt;
    }
}
