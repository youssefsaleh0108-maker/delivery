package com.delivery.product.service;

import java.util.concurrent.Semaphore;
import java.util.function.IntSupplier;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import com.delivery.product.vision.Descriptions;
import com.delivery.product.vision.VisionException;
import com.delivery.product.vision.VisionProvider;
import com.delivery.product.vision.VisionProvider.ProductDescription;
import com.delivery.product.vision.VisionProvider.ProductPhoto;

/**
 * Reads one photo on the request thread: shrinks it, counts the use, asks the provider, and lets the
 * photo go.
 *
 * <p>Photo search answers while the customer waits, so unlike Blitz's scans (queued on
 * {@code CatalogScanAnalyzer}'s own pool, and polled) this runs on the request thread. The service has
 * forty of those for everything it does ({@code server.tomcat.threads.max}), and a read can take up to
 * the provider's timeout, so at most {@code max-concurrent} (4) reads run at once: a non-blocking
 * {@link Semaphore}, whose {@code tryAcquire} fails at once when every slot is taken, and the request
 * is answered 503 {@code PHOTO_READER_BUSY} with a Retry-After. No request ever waits for a slot, so
 * at most four of the forty threads are ever held by the provider, and a slow provider slows photo
 * search and nothing else.
 *
 * <p>Under the slot, in order:
 * <ol>
 *   <li>The photo is decoded, stood upright and shrunk to {@code max-long-edge-px} (1568) as JPEG by
 *       {@link Thumbnailer#renderLongEdge}, behind a pixel budget sized to a phone camera rather than
 *       the service's 40 MP, since up to four decode at once on request threads. A photo that will not
 *       decode is 422 {@code PHOTO_UNREADABLE}, and costs the account nothing.</li>
 *   <li>The use is counted (the caller's {@code countUse}, {@link PhotoQuota#take}): its own short
 *       transaction, which may refuse with a 429.</li>
 *   <li>The provider is asked, outside any transaction: the pool has ten connections, open-in-view is
 *       off, and nothing here holds one across the call.</li>
 * </ol>
 *
 * <p><strong>The photo is dropped as soon as the call returns.</strong> The bytes live in local
 * variables of this call only: nothing here stores them, logs them, or hands them to storage — the
 * photo never touches MinIO (whose product-images bucket is public-read), the database or the disk.
 * What this class logs is the provider, the outcome and the time taken; never the photo, never what it
 * was read as, and never the account.
 */
@Component
public class PhotoReader {

    private static final Logger log = LoggerFactory.getLogger(PhotoReader.class);

    /** How long a client is told to wait when every slot is taken: about one read's worth. */
    static final long BUSY_RETRY_AFTER_SECONDS = 5;

    /**
     * What one read comes to.
     *
     * @param description the provider's answer, sanitised
     * @param left        what {@code countUse} said is left of the day after this use
     */
    public record Reading(Descriptions.Clean description, int left) {
    }

    private final Thumbnailer thumbnailer;
    private final int maxConcurrent;
    private final Semaphore slots;
    private final int maxLongEdgePx;
    private final long maxSourcePixels;

    @Autowired
    public PhotoReader(Thumbnailer thumbnailer,
                       @Value("${delivery.catalog.photo-search.max-concurrent:4}") int maxConcurrent,
                       @Value("${delivery.catalog.photo-search.claude.max-long-edge-px:1568}") int maxLongEdgePx,
                       @Value("${delivery.catalog.photo-search.max-source-pixels:16000000}") long maxSourcePixels) {
        this.thumbnailer = thumbnailer;
        // Clamped rather than trusted: zero slots would refuse every photo, and a large number would
        // hand the provider every request thread there is.
        this.maxConcurrent = Math.min(Math.max(maxConcurrent, 1), 8);
        this.slots = new Semaphore(this.maxConcurrent);
        this.maxLongEdgePx = maxLongEdgePx;
        this.maxSourcePixels = maxSourcePixels;
    }

    /**
     * Reads {@code photo} with {@code provider}.
     *
     * @param photo    the uploaded bytes, a JPEG or a PNG as the controller checked
     * @param countUse counts the use just before the provider is asked, and says what is left; throws
     *                 the 429 when a limit is reached
     * @throws PhotoSearchException {@code PHOTO_READER_BUSY} when every slot is taken,
     *                              {@code PHOTO_UNREADABLE}, a limit, {@code PHOTO_REFUSED} when the
     *                              provider declined, {@code PHOTO_READER_FAILED} when it failed, or
     *                              {@code PHOTO_SEARCH_UNAVAILABLE} when it turned out to have no key
     */
    public Reading read(byte[] photo, VisionProvider provider, IntSupplier countUse) {
        if (!slots.tryAcquire()) {
            log.info("Photo read refused: all {} reader slots are busy", maxConcurrent);
            throw PhotoSearchException.busy(BUSY_RETRY_AFTER_SECONDS);
        }
        long started = System.nanoTime();
        String outcome = "ERROR";
        try {
            byte[] jpeg;
            try {
                jpeg = thumbnailer.renderLongEdge(photo, maxLongEdgePx, maxSourcePixels);
            } catch (Thumbnailer.ThumbnailUnavailableException | OutOfMemoryError e) {
                outcome = "UNREADABLE";
                throw PhotoSearchException.unreadable();
            }

            int left;
            try {
                left = countUse.getAsInt();
            } catch (PhotoSearchException e) {
                outcome = e.getCode();
                throw e;
            }

            ProductDescription raw;
            try {
                raw = provider.describe(new ProductPhoto(jpeg));
            } catch (VisionException e) {
                outcome = e.reason().name();
                throw switch (e.reason()) {
                    case REFUSED -> PhotoSearchException.refused();
                    case NOT_CONFIGURED -> PhotoSearchException.unavailable();
                    case PROVIDER_ERROR -> PhotoSearchException.failed();
                };
            } catch (RuntimeException e) {
                outcome = "PROVIDER_ERROR";
                throw PhotoSearchException.failed();
            }

            Descriptions.Clean clean = Descriptions.sanitize(raw);
            outcome = clean.isProduct() ? "PRODUCT" : "NOT_A_PRODUCT";
            return new Reading(clean, left);
        } finally {
            slots.release();
            log.info("Photo read by {}: {} in {} ms", provider.name(), outcome,
                    (System.nanoTime() - started) / 1_000_000);
        }
    }

    /** Slots free right now; for tests. */
    int freeSlots() {
        return slots.availablePermits();
    }
}
