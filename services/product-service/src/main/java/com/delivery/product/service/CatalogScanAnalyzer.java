package com.delivery.product.service;

import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.Executor;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.DisposableBean;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import com.delivery.product.domain.CatalogScan.FailureCode;
import com.delivery.product.service.CatalogScanService.AnalysisJob;
import com.delivery.product.service.CatalogScanService.PhotoRef;
import com.delivery.product.vision.VisionException;
import com.delivery.product.vision.VisionProvider;
import com.delivery.product.vision.VisionProvider.Detection;
import com.delivery.product.vision.VisionProvider.ShelfPhoto;
import com.delivery.product.vision.VisionProviders;

/**
 * Reads a scan's photos off the request thread.
 *
 * <p>A vision call takes tens of seconds, and this service has forty request threads for the whole
 * catalogue (see {@code server.tomcat.threads.max}). Holding one per scan would let a handful of
 * merchants photographing their shelves at once slow every storefront on the platform — so the
 * request only marks the scan ANALYZING and returns, the client polls, and the work happens here.
 *
 * <p><strong>Its own small pool, deliberately not a Spring {@code Executor} bean.</strong> Declaring
 * one would make Spring Boot's auto-configured application task executor back off for the whole
 * service, changing the threading of things that have nothing to do with scans. Two threads and a
 * short queue: a full queue fails the scan as BUSY straight away rather than letting a backlog of
 * paid calls pile up behind a slow provider.
 *
 * <p>In memory, on one pod. A pod that goes away mid-analysis takes the job with it; the scan then
 * reads as INTERRUPTED once {@code stale-after} passes and may be started again. Durable jobs would
 * be the fix if that ever matters; for a flow the merchant is watching live, it does not yet.
 */
@Component
public class CatalogScanAnalyzer implements DisposableBean {

    private static final Logger log = LoggerFactory.getLogger(CatalogScanAnalyzer.class);

    private static final int THREADS = 2;
    private static final int QUEUE = 20;

    private final CatalogScanService scans;
    private final VisionProviders providers;
    private final ImageObjectStore objects;
    private final Thumbnailer thumbnailer;
    private final Executor executor;
    private final int maxLongEdgePx;

    @Autowired
    public CatalogScanAnalyzer(
            CatalogScanService scans,
            VisionProviders providers,
            ImageObjectStore objects,
            Thumbnailer thumbnailer,
            @Value("${delivery.catalog.scan.claude.max-long-edge-px:1568}") int maxLongEdgePx) {
        this(scans, providers, objects, thumbnailer, newPool(), maxLongEdgePx);
    }

    /** For tests: a caller-supplied executor, usually one that runs inline. */
    CatalogScanAnalyzer(CatalogScanService scans, VisionProviders providers, ImageObjectStore objects,
                        Thumbnailer thumbnailer, Executor executor, int maxLongEdgePx) {
        this.scans = scans;
        this.providers = providers;
        this.objects = objects;
        this.thumbnailer = thumbnailer;
        this.executor = executor;
        this.maxLongEdgePx = maxLongEdgePx;
    }

    /**
     * Queues the analysis. Never throws: a full queue fails the scan as BUSY at once and gives the
     * attempt back, since nothing was sent. The pool cannot be filled by one account — a merchant
     * has one scan read at a time (CatalogScanService#startAnalysis) — so BUSY means the platform is
     * busy, not that a neighbour is flooding it.
     */
    public void submit(UUID scanId, int attempt) {
        try {
            executor.execute(() -> run(scanId, attempt));
        } catch (RejectedExecutionException e) {
            log.warn("Scan {} attempt {} refused: the analysis queue is full", scanId, attempt);
            scans.recordBusy(scanId, attempt);
        }
    }

    void run(UUID scanId, int attempt) {
        Optional<AnalysisJob> loaded = scans.loadForAnalysis(scanId, attempt);
        if (loaded.isEmpty()) {
            return;
        }
        AnalysisJob job = loaded.get();

        // Shrunk before sending: the provider reads images at about this size anyway, so sending a
        // phone's 12 MP original is paying to upload pixels it throws away. The same decoder guard
        // as thumbnails, so a decompression bomb dressed as a shelf photo stops here.
        List<ShelfPhoto> prepared = new ArrayList<>(job.photos().size());
        for (PhotoRef photo : job.photos()) {
            try {
                byte[] original = objects.read(photo.bucket(), photo.objectKey());
                prepared.add(new ShelfPhoto(thumbnailer.renderLongEdge(original, maxLongEdgePx)));
            } catch (RuntimeException | OutOfMemoryError e) {
                log.warn("Scan {}: photo {} could not be prepared: {}",
                        scanId, photo.photoId(), e.toString());
                scans.recordFailure(scanId, attempt, FailureCode.UNREADABLE_PHOTO);
                return;
            }
        }

        try {
            VisionProvider provider = providers.active();
            List<Detection> found = provider.detect(prepared, job.categoryNames());
            scans.recordDetections(job, provider.name(), found);
        } catch (VisionException e) {
            log.warn("Scan {} attempt {} failed ({}): {}", scanId, attempt, e.reason(), e.getMessage());
            scans.recordFailure(scanId, attempt, e.reason() == VisionException.Reason.REFUSED
                    ? FailureCode.REFUSED : FailureCode.PROVIDER_ERROR);
        } catch (RuntimeException e) {
            log.error("Scan {} attempt {} failed unexpectedly", scanId, attempt, e);
            scans.recordFailure(scanId, attempt, FailureCode.PROVIDER_ERROR);
        }
    }

    private static ExecutorService newPool() {
        AtomicInteger counter = new AtomicInteger();
        return new ThreadPoolExecutor(THREADS, THREADS, 60, TimeUnit.SECONDS,
                new ArrayBlockingQueue<>(QUEUE),
                runnable -> {
                    Thread thread = new Thread(runnable, "catalog-scan-" + counter.incrementAndGet());
                    thread.setDaemon(true);
                    return thread;
                },
                new ThreadPoolExecutor.AbortPolicy());
    }

    @Override
    public void destroy() {
        if (executor instanceof ExecutorService pool) {
            // Not waited on: an analysis cut off here reads as INTERRUPTED and may be restarted,
            // which is a better outcome than holding a rolling update open for a minute.
            pool.shutdownNow();
        }
    }
}
