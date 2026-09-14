package com.delivery.platform.storage;

import java.io.InputStream;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.concurrent.TimeUnit;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.transaction.annotation.Transactional;

import io.minio.GetObjectArgs;
import io.minio.GetPresignedObjectUrlArgs;
import io.minio.MinioClient;
import io.minio.RemoveObjectArgs;
import io.minio.StatObjectArgs;
import io.minio.StatObjectResponse;
import io.minio.errors.ErrorResponseException;
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
 *
 * <p><strong>A presigned PUT is not used up by a confirm.</strong> It works for its whole TTL, as many
 * times as anybody holding it likes: after {@link #confirmUpload} passed a file, the same URL can put
 * something else under the same key, and after a file is deleted it can put an object back that no row
 * describes. This class cannot shorten that; what it offers a caller is the means to notice — the entity
 * tag of the bytes that were checked ({@link #confirm}), {@link #inspect} to compare it with later, and
 * {@link #removeObject} to take the key back once more after the URL has expired.
 */
public class StorageService {

    private static final Logger log = LoggerFactory.getLogger(StorageService.class);

    /** MinIO's code for a key that holds nothing, which a HEAD's 404 is reported as. */
    private static final String NO_SUCH_KEY = "NoSuchKey";

    private final MinioClient internalClient;
    private final MinioClient presignClient;
    private final FileMetadataRepository repository;
    private final StorageProperties properties;

    @SuppressWarnings("deprecation")
    public StorageService(MinioClient internalClient, MinioClient presignClient,
                          FileMetadataRepository repository, StorageProperties properties) {
        this.internalClient = internalClient;
        this.presignClient = presignClient;
        this.repository = repository;
        this.properties = properties;
        if (properties.getAllowedImageContentTypes() != null) {
            // Said out loud because the setting now does nothing. A service that WIDENED the old
            // global list (onboarding-service added PDF for applicant documents) loses nothing it
            // needs, since the purpose carries that rule now; one that NARROWED it would silently
            // accept more than it meant to. Startup is the one moment anybody reads this log.
            log.warn("delivery.storage.minio.allowed-image-content-types is no longer consulted: "
                    + "content types are per purpose since platform-storage 0.1.3. Remove it, and set "
                    + "delivery.storage.minio.allowed-content-types.<PURPOSE> for any purpose whose "
                    + "built-in list does not suit.");
        }
    }

    /**
     * The content types {@link #presignUpload} accepts for this purpose, so a caller can refuse a
     * type with a message its user can act on before asking for a URL — without keeping a second
     * list of its own that drifts from this one.
     */
    public List<String> allowedContentTypes(FilePurpose purpose) {
        return properties.allowedContentTypesFor(purpose);
    }

    /**
     * Issues a presigned PUT and records a PENDING metadata row.
     *
     * @param ownerId     the caller's Keycloak {@code sub}; ownership of the resulting object
     * @param purpose     determines the bucket, the read policy and the content types allowed
     * @param contentType validated against the purpose's allow-list before a URL is issued
     * @param keyPrefix   caller-supplied path prefix, e.g. {@code products/{productId}}
     */
    @Transactional
    public PresignedUpload presignUpload(String ownerId, FilePurpose purpose,
                                         String contentType, String keyPrefix) {
        if (contentType == null || !properties.allowedContentTypesFor(purpose).contains(contentType)) {
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
     * Confirms the client's upload actually landed, and is what it was declared to be.
     *
     * <p>A presigned URL can bind neither a size nor a type, so both are checked here, after the fact:
     * the object must be within the size limit, stored with the content type declared at presign, and
     * begin with the bytes a file of that type begins with ({@link FileSignature}) — read with a ranged
     * request of a few bytes, never the whole object. An upload failing any of them is removed from the
     * bucket, its row is marked deleted, and an {@link UploadRefusedException} says which check it
     * failed. Without this step a service would happily record an image that was never uploaded, one
     * far larger than the limit it advertised, or an HTML page named for a PDF.
     *
     * <p>That refusal <strong>commits</strong> ({@code noRollbackFor}): the object is already gone, and a
     * rolled-back row would go on calling it PENDING. Every other failure rolls back as usual.
     *
     * <p>Confirming an upload already confirmed returns it unchecked. A caller that needs to know the
     * bytes are still the ones that were checked uses {@link #confirm} and {@link #inspect}.
     */
    @Transactional(noRollbackFor = UploadRefusedException.class)
    public FileMetadata confirmUpload(UUID fileId, String callerId) {
        FileMetadata metadata = owned(fileId, callerId);
        if (metadata.getStatus() == FileMetadata.Status.UPLOADED) {
            return metadata;
        }
        return check(metadata).file();
    }

    /**
     * {@link #confirmUpload}, answering with the entity tag of exactly the bytes that passed as well —
     * for a caller that keeps the file and must notice later if the object under its key stops being
     * them ({@link ConfirmedUpload}).
     *
     * <p>Unlike {@link #confirmUpload}, an upload already confirmed is checked again rather than
     * returned as it is: a tag is only worth recording if it belongs to bytes that passed.
     */
    @Transactional(noRollbackFor = UploadRefusedException.class)
    public ConfirmedUpload confirm(UUID fileId, String callerId) {
        return check(owned(fileId, callerId));
    }

    /**
     * What the bucket holds under a file's key right now, or empty when the key holds nothing.
     *
     * <p>For a caller about to use a file it confirmed some time ago — hand it to somebody, attach it to
     * something — to compare with what it recorded then ({@link StoredObject#isStill}). The presigned PUT
     * that created the object may still work, so "confirmed once" is not "still the same file".
     *
     * @throws StorageException when storage cannot say — unreachable, or refusing the request — which is
     *                          not the same answer as the object being gone
     */
    public Optional<StoredObject> inspect(FileMetadata metadata) {
        try {
            StatObjectResponse stat = internalClient.statObject(StatObjectArgs.builder()
                    .bucket(metadata.getBucket())
                    .object(metadata.getObjectKey())
                    .build());
            return Optional.of(new StoredObject(stat.size(), unquoted(stat.etag()), stat.contentType()));
        } catch (ErrorResponseException e) {
            if (e.errorResponse() != null && NO_SUCH_KEY.equals(e.errorResponse().code())) {
                return Optional.empty();
            }
            throw new StorageException("Could not inspect " + metadata.getObjectKey(), e);
        } catch (Exception e) {
            throw new StorageException("Could not inspect " + metadata.getObjectKey(), e);
        }
    }

    /**
     * A URL the client can read the object from.
     *
     * <p>Publicly-readable buckets get a plain URL so the CDN can cache it; everything else gets a
     * short-TTL presigned GET, because those objects are private and a cacheable URL would defeat
     * the point.
     *
     * <p>A private object is also <strong>served as the content type that was checked</strong>
     * ({@code response-content-type}), not as whatever header the uploader's PUT happened to carry.
     * The presigned PUT cannot bind a Content-Type, so a file declared as a PDF at presign could be
     * stored as {@code text/html} and would then render — script and all — in the MinIO origin for
     * whoever opened it: a provider opening a customer's artwork, a reviewer opening a document.
     * Pinning the served type to the allow-listed one closes that without reading the bytes.
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
                            .extraQueryParams(Map.of("response-content-type", metadata.getContentType()))
                            .build());
        } catch (Exception e) {
            throw new StorageException("Could not presign download for " + metadata.getObjectKey(), e);
        }
    }

    @Transactional
    public void softDelete(UUID fileId, String callerId) {
        FileMetadata metadata = owned(fileId, callerId);
        delete(metadata.getBucket(), metadata.getObjectKey());
        metadata.markDeleted();
    }

    /**
     * Marks a file deleted without touching the bucket: the first half of a deletion whose object the
     * caller removes with {@link #removeObject} once its own transaction has committed. That way no
     * storage call is made while the caller holds row locks, and storage being slow or away leaves a
     * removal to retry rather than a transaction held open or rolled back.
     */
    @Transactional
    public FileMetadata markDeleted(UUID fileId, String callerId) {
        FileMetadata metadata = owned(fileId, callerId);
        metadata.markDeleted();
        return metadata;
    }

    /**
     * Removes a file's object from the bucket, and nothing else: its row is the caller's to have marked
     * deleted already. Safe to repeat — removing a key that holds nothing succeeds, as S3 answers it.
     *
     * @return true when storage confirmed the key now holds nothing; false when it could not be asked,
     *         which is logged and never thrown, so a caller removing many objects after its transaction
     *         committed cannot stop half way
     */
    public boolean removeObject(FileMetadata metadata) {
        return delete(metadata.getBucket(), metadata.getObjectKey());
    }

    private FileMetadata owned(UUID fileId, String callerId) {
        FileMetadata metadata = repository.findById(fileId)
                .orElseThrow(() -> new StorageException("No such file: " + fileId));
        if (!metadata.isOwnedBy(callerId)) {
            throw new StorageException("File " + fileId + " does not belong to the caller");
        }
        return metadata;
    }

    /** Confirm's checks, in the order that reads the least: size and type from a stat, then a few bytes. */
    private ConfirmedUpload check(FileMetadata metadata) {
        if (metadata.getStatus() == FileMetadata.Status.DELETED) {
            // Deleted is final. The key's URL may still work, and an object PUT through it afterwards
            // must not bring the row back to life.
            throw new StorageException("File " + metadata.getId() + " was deleted");
        }

        StatObjectResponse stat;
        try {
            stat = internalClient.statObject(StatObjectArgs.builder()
                    .bucket(metadata.getBucket())
                    .object(metadata.getObjectKey())
                    .build());
        } catch (Exception e) {
            throw new StorageException(
                    "Upload for " + metadata.getId() + " was not found in the bucket", e);
        }

        if (stat.size() > properties.getMaxUploadSizeBytes()) {
            throw refused(metadata, UploadRefusedException.Reason.TOO_LARGE, "Upload exceeds the maximum of "
                    + properties.getMaxUploadSizeBytes() + " bytes");
        }
        if (!FileSignature.mediaType(stat.contentType()).equals(FileSignature.mediaType(metadata.getContentType()))) {
            throw refused(metadata, UploadRefusedException.Reason.WRONG_TYPE, "Upload " + metadata.getId()
                    + " was stored as '" + stat.contentType() + "', not " + metadata.getContentType());
        }
        // An empty object begins with nothing, so it is no type at all — and a range request of an empty
        // object is refused by storage, which would read as "not found" instead.
        byte[] head = stat.size() == 0 ? new byte[0] : head(metadata, stat.etag());
        if (!FileSignature.matches(metadata.getContentType(), head)) {
            throw refused(metadata, UploadRefusedException.Reason.WRONG_TYPE, "Upload " + metadata.getId()
                    + " does not begin as a " + metadata.getContentType() + " does");
        }

        metadata.markUploaded(stat.size());
        return new ConfirmedUpload(metadata, unquoted(stat.etag()));
    }

    /**
     * The first bytes of exactly the object that was measured: a ranged read, so the rest of it never
     * crosses the network, and conditional on the entity tag the stat saw, so an object replaced between
     * the two is refused by storage rather than checked in place of the one that was measured.
     */
    private byte[] head(FileMetadata metadata, String etag) {
        try (InputStream in = internalClient.getObject(GetObjectArgs.builder()
                .bucket(metadata.getBucket())
                .object(metadata.getObjectKey())
                .offset(0L)
                .length((long) FileSignature.BYTES_NEEDED)
                .matchETag(etag)
                .build())) {
            // Bounded as well, in case storage ever answers a range with the whole object.
            return in.readNBytes(FileSignature.BYTES_NEEDED);
        } catch (Exception e) {
            throw new StorageException("Could not read the start of upload " + metadata.getId(), e);
        }
    }

    /** Removes the refused object and marks its row, then hands back the refusal for the caller to throw. */
    private UploadRefusedException refused(FileMetadata metadata, UploadRefusedException.Reason reason,
                                           String message) {
        delete(metadata.getBucket(), metadata.getObjectKey());
        metadata.markDeleted();
        return new UploadRefusedException(reason, message);
    }

    private boolean delete(String bucket, String objectKey) {
        try {
            internalClient.removeObject(RemoveObjectArgs.builder()
                    .bucket(bucket)
                    .object(objectKey)
                    .build());
            return true;
        } catch (Exception e) {
            // The metadata row is still marked deleted by the caller. A stray object is a storage
            // cost; a metadata row pointing at something the user believes is gone is a privacy
            // problem, so the row's state takes precedence over the object's.
            log.warn("Could not remove {}/{} from the bucket", bucket, objectKey, e);
            return false;
        }
    }

    /** An entity tag as S3 sends it is quoted; the quotes are not part of it. */
    private static String unquoted(String etag) {
        return etag == null ? null : etag.replace("\"", "");
    }

    private static String buildObjectKey(String keyPrefix, String contentType) {
        String extension = switch (contentType) {
            case "image/jpeg" -> ".jpg";
            case "image/png" -> ".png";
            case "image/webp" -> ".webp";
            case "application/pdf" -> ".pdf";
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
