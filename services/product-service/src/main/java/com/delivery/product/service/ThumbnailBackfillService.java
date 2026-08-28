package com.delivery.product.service;

import java.util.ArrayList;
import java.util.List;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;

import com.delivery.platform.storage.FileMetadata;
import com.delivery.platform.storage.FileMetadataRepository;
import com.delivery.product.domain.Product;
import com.delivery.product.domain.ProductRepository;
import com.delivery.product.domain.Store;
import com.delivery.product.domain.StoreRepository;

/**
 * Derivatives for the images that were uploaded before derivatives existed.
 *
 * <p>Thumbnailing happens on confirm, which covers everything uploaded from now on and nothing
 * already in the database. Those images degrade correctly — the response falls back to the
 * full-size URL — but "correctly" here means a customer still waits three seconds for an 80dp
 * square, which is the whole problem. A catalogue is not migrated by a code path that only runs on
 * new writes.
 *
 * <p>Deliberately a request, not a startup hook. Reading and re-encoding every image in the
 * catalogue is minutes of CPU and a great deal of object storage traffic; doing it automatically on
 * boot would make an ordinary restart expensive and unpredictable, and would do it again on every
 * replica. An operator asks for it, once, and can watch it.
 *
 * <p>Idempotent and resumable by construction: an image that already has a derivative is skipped,
 * so running it twice costs two scans and no re-encoding, and an interrupted run is resumed by
 * running it again.
 */
@Service
public class ThumbnailBackfillService {

    private static final Logger log = LoggerFactory.getLogger(ThumbnailBackfillService.class);

    /**
     * How many rows are held in memory at once. Small on purpose: each one may pull a multi-megabyte
     * original out of object storage, and a page of a thousand would be a heap spike that fails the
     * backfill rather than the individual image.
     */
    private static final int PAGE = 50;

    private final ProductRepository products;
    private final StoreRepository stores;
    private final FileMetadataRepository files;
    private final ThumbnailService thumbnails;

    public ThumbnailBackfillService(ProductRepository products, StoreRepository stores,
                                    FileMetadataRepository files, ThumbnailService thumbnails) {
        this.products = products;
        this.stores = stores;
        this.files = files;
        this.thumbnails = thumbnails;
    }

    /** What one run did, so the caller sees progress rather than a bare 204. */
    public record Result(int scanned, int created, int alreadyHad, int failed) {
    }

    /**
     * Walks every product and store image, creating any derivative that is missing.
     *
     * <p>NOT transactional as a whole. Each image commits on its own through
     * {@link ThumbnailService#createFor}, so a failure at image nine hundred keeps the eight hundred
     * and ninety-nine already done — the opposite of what one long transaction would give, which is
     * an all-or-nothing run that gets slower and more fragile the more there is to do.
     */
    public Result run() {
        int scanned = 0;
        int created = 0;
        int had = 0;
        int failed = 0;

        for (int page = 0; ; page++) {
            Page<Product> batch = products.findAll(PageRequest.of(page, PAGE));
            for (Product product : batch) {
                for (String ref : product.getImageRefs()) {
                    scanned++;
                    switch (ensure(ref)) {
                        case CREATED -> created++;
                        case PRESENT -> had++;
                        case FAILED -> failed++;
                    }
                }
            }
            if (batch.isLast()) break;
        }

        for (int page = 0; ; page++) {
            Page<Store> batch = stores.findAll(PageRequest.of(page, PAGE));
            for (Store store : batch) {
                for (String ref : storeArtwork(store)) {
                    scanned++;
                    switch (ensure(ref)) {
                        case CREATED -> created++;
                        case PRESENT -> had++;
                        case FAILED -> failed++;
                    }
                }
            }
            if (batch.isLast()) break;
        }

        log.info("Thumbnail backfill: scanned {}, created {}, already had {}, failed {}",
                scanned, created, had, failed);
        return new Result(scanned, created, had, failed);
    }

    private static List<String> storeArtwork(Store store) {
        List<String> refs = new ArrayList<>(2);
        if (store.getLogoRef() != null && !store.getLogoRef().isBlank()) {
            refs.add(store.getLogoRef());
        }
        if (store.getCoverRef() != null && !store.getCoverRef().isBlank()) {
            refs.add(store.getCoverRef());
        }
        return refs;
    }

    private enum Outcome { CREATED, PRESENT, FAILED }

    private Outcome ensure(String objectKey) {
        if (objectKey == null || objectKey.isBlank() || Thumbnailer.isThumbKey(objectKey)) {
            return Outcome.PRESENT;
        }
        try {
            String thumbKey = Thumbnailer.thumbKeyFor(objectKey);
            // One query for both, so a catalogue that is already done costs a lookup per image and
            // no object-storage traffic at all.
            List<FileMetadata> found = files.findByObjectKeyIn(List.of(objectKey, thumbKey));

            FileMetadata original = found.stream()
                    .filter(f -> objectKey.equals(f.getObjectKey()))
                    .findFirst().orElse(null);
            boolean hasThumb = found.stream().anyMatch(f -> thumbKey.equals(f.getObjectKey()));

            if (original == null) {
                // A product referencing an object with no metadata row. Not this job's problem to
                // repair, and not a reason to stop.
                log.warn("Backfill: no file metadata for {}", objectKey);
                return Outcome.FAILED;
            }
            if (hasThumb) {
                return Outcome.PRESENT;
            }

            thumbnails.createFor(original);

            // createFor is best-effort and says nothing on failure, so the row is what is believed
            // rather than the call returning.
            boolean now = files.findByObjectKeyIn(List.of(thumbKey)).stream()
                    .anyMatch(f -> thumbKey.equals(f.getObjectKey()));
            return now ? Outcome.CREATED : Outcome.FAILED;

        } catch (RuntimeException e) {
            log.warn("Backfill: could not create a derivative for {}: {}", objectKey, e.getMessage());
            return Outcome.FAILED;
        }
    }
}
