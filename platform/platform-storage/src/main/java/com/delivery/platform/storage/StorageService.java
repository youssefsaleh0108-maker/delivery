package com.delivery.platform.storage;

import java.time.Instant;
import java.util.UUID;
import java.util.concurrent.TimeUnit;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.transaction.annotation.Transactional;

import io.minio.GetPresignedObjectUrlArgs;
import io.minio.MinioClient;
import io.minio.RemoveObjectArgs;
import io.minio.StatObjectArgs;
import io.minio.StatObjectResponse;
import io.minio.http.Method;

/**
 * Issues short-lived presigned URLs and keeps {@code file_metadata} in step with the bucket.
 *
 * <p>Section 5: no client ever holds MinIO credentials. Every URL here is minted after the caller's
 * role and resource ownership have already been checked by the calling service, is scoped to a
 * single object, and expires in minutes.
 *
 * <p>Two MinIO clients are held deliberately. Presigned URLs are signed for the public endpoint
 * because the signature covers the host header — sign against the internal Docker hostname and the
 * browser's request is rejected. Server-side operations use the internal endpoint, which is
 * reachable from inside the network and avoids a pointless round trip through the host.
 */
public class StorageService {

    private static final Logger log = LoggerFactory.getLogger(StorageService.class);

    private final MinioClient internalClient;
    private final MinioClient presignClient;
    private final FileMetadataRepository repository;
    private final StorageProperties properties;

    public StorageService(MinioClient internalClient, MinioClient presignClient,
                          FileMetadataRepository repository, StorageProperties properties) {
        this.internalClient = internalClient;
        this.presignClient = presignClient;
        this.repository = repository;
        this.properties = properties;
    }

    /**
     * Issues a presigned PUT and records a PENDING metadata row.
     *
     * @param ownerId     the caller's Keycloak {@code sub}; ownership of the resulting object
     * @param purpose     determines the bucket and the read policy
     * @param contentType validated against the allow-list before a URL is issued
     * @param keyPrefix   caller-supplied path prefix, e.g. {@code products/{productId}}
     */
    @Transactional
    public PresignedUpload presignUpload(String ownerId, FilePurpose purpose,
                                         String contentType, String keyPrefix) {
        if (!properties.getAllowedImageContentTypes().contains(contentType)) {
            throw new StorageException(
                    "Content type '" + contentType + "' is not allowed for " + purpose);
        }

        // Server-generated key. A client-supplied object key would let a merchant overwrite another
        // merchant's image by guessing its path, since the presigned URL grants write access to
        // whatever key it was signed for.
        String objectKey = buildObjectKey(keyPrefix, contentType);
        FileMetadata metadata = new FileMetadata(
                purpose.bucket(), objectKey, ownerId, contentType, purpose);

        String url;
        try {
            url = presignClient.getPresignedObjectUrl(
                    GetPresignedObjectUrlArgs.builder()
                            .method(Method.PUT)
                            .bucket(purpose.bucket())
                            .object(objectKey)
                            .expiry((int) properties.getPresignTtl().toSeconds(), TimeUnit.SECONDS)
                            .build());
        } catch (Exception e) {
            throw new StorageException("Could not presign upload for " + objectKey, e);
        }

        repository.save(metadata);
        log.debug("Presigned upload {} for owner {} ({})", objectKey, ownerId, purpose);

        return new PresignedUpload(
                metadata.getId(),
                url,
                objectKey,
                purpose.bucket(),
                contentType,
                Instant.now().plus(properties.getPresignTtl()),
                properties.getMaxUploadSizeBytes());
    }

    /**
     * Confirms the client's upload actually landed, and enforces the size limit after the fact.
     *
     * <p>The size cap cannot be enforced by the presigned URL itself, so it is checked here and the
     * object deleted if it was exceeded. Without this step a service would happily record an image
     * that was never uploaded, or one far larger than the limit it advertised.
     */
    @Transactional
    public FileMetadata confirmUpload(UUID fileId, String callerId) {
        FileMetadata metadata = repository.findById(fileId)
                .orElseThrow(() -> new StorageException("No such file: " + fileId));

        if (!metadata.isOwnedBy(callerId)) {
            throw new StorageException("File " + fileId + " does not belong to the caller");
        }
        if (metadata.getStatus() == FileMetadata.Status.UPLOADED) {
            return metadata;
        }

        StatObjectResponse stat;
        try {
            stat = internalClient.statObject(StatObjectArgs.builder()
                    .bucket(metadata.getBucket())
                    .object(metadata.getObjectKey())
                    .build());
        } catch (Exception e) {
            throw new StorageException(
                    "Upload for " + fileId + " was not found in the bucket", e);
        }

        if (stat.size() > properties.getMaxUploadSizeBytes()) {
            delete(metadata.getBucket(), metadata.getObjectKey());
            metadata.markDeleted();
            throw new StorageException("Upload exceeds the maximum of "
                    + properties.getMaxUploadSizeBytes() + " bytes");
        }

        metadata.markUploaded(stat.size());
        return metadata;
    }

    /**
     * A URL the client can read the object from.
     *
     * <p>Publicly-readable buckets get a plain URL so the CDN can cache it; everything else gets a
     * short-TTL presigned GET, because those objects are private and a cacheable URL would defeat
     * the point.
     */
    public String readUrl(FileMetadata metadata) {
        if (metadata.getPurpose().isPubliclyReadable()) {
            return properties.getPublicEndpoint() + "/" + metadata.getBucket()
                    + "/" + metadata.getObjectKey();
        }
        try {
            return presignClient.getPresignedObjectUrl(
                    GetPresignedObjectUrlArgs.builder()
                            .method(Method.GET)
                            .bucket(metadata.getBucket())
                            .object(metadata.getObjectKey())
                            .expiry((int) properties.getPresignTtl().toSeconds(), TimeUnit.SECONDS)
                            .build());
        } catch (Exception e) {
            throw new StorageException("Could not presign download for " + metadata.getObjectKey(), e);
        }
    }

    @Transactional
    public void softDelete(UUID fileId, String callerId) {
        FileMetadata metadata = repository.findById(fileId)
                .orElseThrow(() -> new StorageException("No such file: " + fileId));
        if (!metadata.isOwnedBy(callerId)) {
            throw new StorageException("File " + fileId + " does not belong to the caller");
        }
        delete(metadata.getBucket(), metadata.getObjectKey());
        metadata.markDeleted();
    }

    private void delete(String bucket, String objectKey) {
        try {
            internalClient.removeObject(RemoveObjectArgs.builder()
                    .bucket(bucket)
                    .object(objectKey)
                    .build());
        } catch (Exception e) {
            // The metadata row is still marked deleted by the caller. A stray object is a storage
            // cost; a metadata row pointing at something the user believes is gone is a privacy
            // problem, so the row's state takes precedence over the object's.
            log.warn("Could not remove {}/{} from the bucket", bucket, objectKey, e);
        }
    }

    private static String buildObjectKey(String keyPrefix, String contentType) {
        String extension = switch (contentType) {
            case "image/jpeg" -> ".jpg";
            case "image/png" -> ".png";
            case "image/webp" -> ".webp";
            default -> "";
        };
        String prefix = (keyPrefix == null || keyPrefix.isBlank()) ? "" : requireSafe(keyPrefix) + "/";
        return prefix + UUID.randomUUID() + extension;
    }

    /**
     * Refuses a prefix that could steer the object outside its intended namespace.
     *
     * <p>Every caller today builds this from typed values — a {@code UUID}, an enum name — so
     * nothing user-supplied reaches it. That is a property of the current callers, not of this
     * method, and the filename is the only part this class guarantees: a prefix of
     * {@code ../../merchant-kyc} still lands in the bucket the purpose chose, but under a path the
     * purpose did not intend, which is exactly the confusion {@link FilePurpose} exists to prevent.
     * Checking here means the guarantee holds for the next caller too.
     */
    private static String requireSafe(String keyPrefix) {
        if (keyPrefix.contains("..") || keyPrefix.startsWith("/") || keyPrefix.contains("//")) {
            throw new StorageException("Unsafe object key prefix: " + keyPrefix);
        }
        return keyPrefix;
    }
}
