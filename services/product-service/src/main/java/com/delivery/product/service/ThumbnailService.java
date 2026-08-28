package com.delivery.product.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.platform.storage.FileMetadata;
import com.delivery.platform.storage.FileMetadataRepository;

/**
 * Produces the list-sized derivative for a confirmed upload, and records it like any other object.
 *
 * <p>Called from the confirm step of both image flows — {@link ProductImageService#confirmImage}
 * and {@link StoreImageService#confirm} — because that is the first moment the bytes are known to
 * exist in the bucket.
 *
 * <p><strong>The thumbnail is an optimisation, never a precondition.</strong> A merchant who
 * uploads a photo ImageIO cannot decode, or one built to blow up a decoder, still gets their photo
 * attached to their product; the list surface simply loads the full-size image for it, exactly as
 * it does for every image uploaded before this existed. Everything the derivative needs — reading
 * the source, decoding it, re-encoding it, putting it back — is inside a catch, and the only thing
 * a failure produces is a log line.
 */
@Service
public class ThumbnailService {

    private static final Logger log = LoggerFactory.getLogger(ThumbnailService.class);

    private final ImageObjectStore objects;
    private final FileMetadataRepository files;
    private final Thumbnailer thumbnailer;

    public ThumbnailService(ImageObjectStore objects, FileMetadataRepository files,
                            Thumbnailer thumbnailer) {
        this.objects = objects;
        this.files = files;
        this.thumbnailer = thumbnailer;
    }

    /**
     * Best-effort. Returns quietly whether it worked or not.
     *
     * <p>Runs in the caller's transaction so the metadata row for the derivative commits with the
     * product or store it belongs to. The bytes are read, shrunk and written <em>before</em> the
     * repository is touched, which keeps every foreseeable failure — a missing object, a corrupt
     * file, a colour model ImageIO refuses, a decode that runs out of memory — outside the
     * transaction entirely. A rollback there would take the upload down with it, which is precisely
     * what must not happen.
     */
    @Transactional
    public void createFor(FileMetadata original) {
        if (original == null || Thumbnailer.isThumbKey(original.getObjectKey())) {
            return;
        }

        String bucket = original.getBucket();
        String thumbKey = Thumbnailer.thumbKeyFor(original.getObjectKey());

        // Confirm is idempotent — StorageService returns early for an already-UPLOADED file — so a
        // client that retries must not leave a second metadata row pointing at the same object.
        if (files.findByBucketAndObjectKey(bucket, thumbKey).isPresent()) {
            return;
        }

        byte[] thumbnail;
        try {
            thumbnail = thumbnailer.render(objects.read(bucket, original.getObjectKey()));
            objects.write(bucket, thumbKey, thumbnail, Thumbnailer.CONTENT_TYPE);
        } catch (RuntimeException | OutOfMemoryError e) {
            // OutOfMemoryError is caught alongside the exceptions, narrowly and on purpose. The
            // pixel budget in Thumbnailer is the real defence; this is the acknowledgement that a
            // budget is a guess, and that one merchant's unusual photo must not take the pod with
            // it. Nothing has been allocated at this point that is not about to be collected.
            log.warn("No thumbnail for {}/{} — serving the full-size image instead: {}",
                    bucket, original.getObjectKey(), e.toString());
            return;
        }

        FileMetadata metadata = new FileMetadata(
                bucket, thumbKey, original.getOwnerId(),
                Thumbnailer.CONTENT_TYPE, original.getPurpose());
        // Written by this service rather than uploaded by a client, so it is UPLOADED the moment it
        // exists — there is no pending step for it to sit in.
        metadata.markUploaded(thumbnail.length);
        files.save(metadata);

        log.debug("Thumbnail {}/{} is {} bytes", bucket, thumbKey, thumbnail.length);
    }
}
