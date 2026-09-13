package com.delivery.product.domain;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import org.hibernate.annotations.Generated;
import org.hibernate.generator.EventType;

/**
 * One shelf photo on a scan.
 *
 * <p>Created PENDING the moment its upload is presigned, and trusted only once confirmed: the
 * confirm step is where platform-storage checks the object really exists, belongs to the caller
 * and is within the size cap. Only UPLOADED photos are ever read and sent to a provider.
 */
@Entity
@Table(name = "catalog_scan_photos")
public class CatalogScanPhoto {

    public enum Status { PENDING, UPLOADED }

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "scan_id", nullable = false, updatable = false)
    private UUID scanId;

    @Column(name = "file_id", nullable = false, updatable = false)
    private UUID fileId;

    @Column(name = "object_key", nullable = false, length = 512, updatable = false)
    private String objectKey;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false, length = 16)
    private Status status = Status.PENDING;

    @Column(name = "position", nullable = false)
    private short position;

    @Generated(event = EventType.INSERT)
    @Column(name = "created_at", nullable = false, insertable = false, updatable = false)
    private Instant createdAt;

    protected CatalogScanPhoto() {
        // for JPA
    }

    public CatalogScanPhoto(UUID scanId, UUID fileId, String objectKey, int position) {
        this.id = UUID.randomUUID();
        this.scanId = scanId;
        this.fileId = fileId;
        this.objectKey = objectKey;
        this.position = (short) position;
        this.status = Status.PENDING;
    }

    public void markUploaded() {
        this.status = Status.UPLOADED;
    }

    public boolean isUploaded() {
        return status == Status.UPLOADED;
    }

    public UUID getId() {
        return id;
    }

    public UUID getScanId() {
        return scanId;
    }

    public UUID getFileId() {
        return fileId;
    }

    public String getObjectKey() {
        return objectKey;
    }

    public Status getStatus() {
        return status;
    }

    public int getPosition() {
        return position;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }
}
