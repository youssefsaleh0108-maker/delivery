package com.delivery.product.service;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.platform.storage.FilePurpose;
import com.delivery.platform.storage.PresignedUpload;
import com.delivery.platform.storage.StorageService;
import com.delivery.product.api.dto.CatalogDtos.ProductRequest;
import com.delivery.product.domain.CatalogScan;
import com.delivery.product.domain.CatalogScan.FailureCode;
import com.delivery.product.domain.CatalogScanItem;
import com.delivery.product.domain.CatalogScanItemRepository;
import com.delivery.product.domain.CatalogScanPhoto;
import com.delivery.product.domain.CatalogScanPhotoRepository;
import com.delivery.product.domain.CatalogScanRepository;
import com.delivery.product.domain.Category;
import com.delivery.product.domain.CategoryRepository;
import com.delivery.product.domain.Product;
import com.delivery.product.domain.Store;
import com.delivery.product.service.CatalogService.CatalogRuleViolationException;
import com.delivery.product.service.CatalogService.CategoryNotFoundException;
import com.delivery.product.vision.Detections;
import com.delivery.product.vision.VisionProvider.Detection;

/**
 * Merchant Blitz: shelf photos in, a draft catalogue out.
 *
 * <p>The flow, each step its own endpoint:
 * <ol>
 *   <li>{@link #create} — a scan in one of the caller's own stores, within the daily quota.</li>
 *   <li>{@link #presignPhoto} / {@link #confirmPhoto} — the platform's three-step upload, the same
 *       as a product photo's: the bytes go straight to storage and are trusted only once
 *       confirmed.</li>
 *   <li>{@link #startAnalysis} — counts a paid attempt and hands the scan to
 *       {@link CatalogScanAnalyzer}, which reads the photos off the request thread.</li>
 *   <li>{@link #read} — the client polls this while the scan line runs.</li>
 *   <li>{@link #updateItem} / {@link #rejectItem} / {@link #commit} — the merchant decides each
 *       line. An accepted line becomes a product through {@link CatalogService#create}, the same
 *       path the product form takes, so every catalogue rule — store ownership, section ownership,
 *       the outbox event — applies without a second copy of it here.</li>
 * </ol>
 *
 * <p><strong>Nothing here publishes.</strong> Accepted lines are DRAFT products. Publishing is the
 * merchant's own act on the product screen, where the image rule and the not-yet-approved rule
 * already live — a vision model's reading of a shelf is not something that goes in front of
 * customers without a person looking at it.
 *
 * <p>Every method takes the caller's id and resolves the scan by id AND owner, so another
 * merchant's scan id is indistinguishable from one that was never issued.
 */
@Service
public class CatalogScanService {

    private static final Logger log = LoggerFactory.getLogger(CatalogScanService.class);

    /** The quota's window. Rolling, so a burst cannot straddle midnight to double it. */
    static final Duration QUOTA_WINDOW = Duration.ofHours(24);

    /** Where shelf photos are filed in the product-images bucket, beside {@code products/}. */
    static final String PHOTO_PREFIX = "scans/";

    public record Limits(int maxPhotosPerScan, int maxScansPerDay, int maxAnalysisAttempts,
                         int maxItemsPerScan, Duration staleAfter) {
    }

    /**
     * A scan as its merchant sees it.
     *
     * @param status         the status to report — a stale ANALYZING reads as FAILED
     * @param failure        why it failed, when it did
     * @param scansLeftToday how many more scans the quota allows right now
     * @param attemptsLeft   how many more analyses this scan may have
     */
    public record ScanDetails(CatalogScan scan, CatalogScan.Status status, FailureCode failure,
                              List<CatalogScanPhoto> photos, List<CatalogScanItem> items,
                              int maxPhotos, int attemptsLeft, int scansLeftToday) {
    }

    /** The result of {@link #startAnalysis}: what to show, and the attempt the job must carry. */
    public record Started(ScanDetails details, int attempt) {
    }

    /** One line to accept, with the name, price and section the merchant settled on. */
    public record Acceptance(UUID itemId, String name, BigDecimal price, UUID categoryId) {
    }

    /** One photo to read: where its bytes are, and which row the lines will hang off. */
    public record PhotoRef(UUID photoId, String bucket, String objectKey) {
    }

    /** A section a line may be filed under — the store's own, or the platform's. */
    public record CategoryChoice(UUID id, String name, boolean storeOwned) {
    }

    /**
     * Everything the analyser needs, read in one short transaction so nothing is held open across
     * a provider call that can take a minute.
     */
    public record AnalysisJob(UUID scanId, int attempt, List<PhotoRef> photos,
                              List<CategoryChoice> categories) {

        /** Store sections first, so the model sees the shop's own vocabulary before the platform's. */
        public List<String> categoryNames() {
            Set<String> names = new LinkedHashSet<>();
            categories.forEach(choice -> names.add(choice.name()));
            return List.copyOf(names);
        }
    }

    private final CatalogScanRepository scans;
    private final CatalogScanPhotoRepository photos;
    private final CatalogScanItemRepository items;
    private final CategoryRepository categories;
    private final StoreService stores;
    private final StorageService storage;
    private final CatalogService catalog;
    private final Clock clock;
    private final Limits limits;

    @Autowired
    public CatalogScanService(
            CatalogScanRepository scans,
            CatalogScanPhotoRepository photos,
            CatalogScanItemRepository items,
            CategoryRepository categories,
            StoreService stores,
            StorageService storage,
            CatalogService catalog,
            Clock clock,
            @Value("${delivery.catalog.scan.max-photos-per-scan:6}") int maxPhotosPerScan,
            @Value("${delivery.catalog.scan.max-scans-per-day:5}") int maxScansPerDay,
            @Value("${delivery.catalog.scan.max-analysis-attempts:2}") int maxAnalysisAttempts,
            @Value("${delivery.catalog.scan.max-items-per-scan:120}") int maxItemsPerScan,
            @Value("${delivery.catalog.scan.stale-after:10m}") Duration staleAfter) {
        this(scans, photos, items, categories, stores, storage, catalog, clock,
                new Limits(maxPhotosPerScan, maxScansPerDay, maxAnalysisAttempts, maxItemsPerScan,
                        staleAfter));
    }

    CatalogScanService(CatalogScanRepository scans, CatalogScanPhotoRepository photos,
                       CatalogScanItemRepository items, CategoryRepository categories,
                       StoreService stores, StorageService storage, CatalogService catalog,
                       Clock clock, Limits limits) {
        this.scans = scans;
        this.photos = photos;
        this.items = items;
        this.categories = categories;
        this.stores = stores;
        this.storage = storage;
        this.catalog = catalog;
        this.clock = clock;
        this.limits = limits;
    }

    // ---------------------------------------------------------------- starting

    /**
     * Starts a scan in one of the caller's stores.
     *
     * <p>With no store named, the caller's own is used — and created if they have none yet, exactly
     * as adding a first product does: a merchant building their catalogue from a photo is the very
     * merchant who has not set a shop up. A named store must be one the caller owns; anybody else's
     * is "not found", the same answer every store-scoped write gives.
     *
     * @throws ScanQuotaExceededException past the daily limit
     */
    @Transactional
    public ScanDetails create(String merchantId, UUID requestedStoreId) {
        // The merchant's lock before anything is counted, and before the store is resolved, so two
        // first scans from a merchant with no shop yet queue here too. The quota counts every store
        // the merchant owns, so a store's lock would not do — see CatalogScanRepository#lockMerchant.
        scans.lockMerchant(merchantId);
        Store store = requestedStoreId == null
                ? stores.requireStoreFor(merchantId)
                : requireOwnedStore(merchantId, requestedStoreId);

        long recent = recentScans(merchantId);
        if (recent >= limits.maxScansPerDay()) {
            throw new ScanQuotaExceededException(limits.maxScansPerDay());
        }

        CatalogScan scan = scans.save(new CatalogScan(merchantId, store.getId()));
        log.info("Merchant {} started catalog scan {} ({} of {} in 24h)",
                merchantId, scan.getId(), recent + 1, limits.maxScansPerDay());
        return details(scan, recent + 1);
    }

    /**
     * Step 1 of a photo upload: a one-shot URL to PUT one shelf photo to.
     *
     * <p>The photo row exists from this moment, PENDING, and counts against the per-scan cap — so
     * the cap bounds presigned URLs, not just confirmed photos, and cannot be walked around by
     * presigning a hundred and confirming six.
     */
    @Transactional
    public PresignedUpload presignPhoto(UUID scanId, String merchantId, String contentType) {
        CatalogScan scan = lockOwned(scanId, merchantId);
        requireUploading(scan);

        long count = photos.countByScanId(scanId);
        if (count >= limits.maxPhotosPerScan()) {
            throw new CatalogRuleViolationException(
                    "A scan may have at most " + limits.maxPhotosPerScan() + " photos");
        }
        Thumbnailer.requireRenderable(contentType);

        PresignedUpload upload = storage.presignUpload(
                merchantId, FilePurpose.PRODUCT_IMAGE, contentType, PHOTO_PREFIX + scanId);
        photos.save(new CatalogScanPhoto(scanId, upload.fileId(), upload.objectKey(), (int) count));
        return upload;
    }

    /**
     * Step 3: the bytes landed.
     *
     * <p>Two ownership checks, both needed: the scan is resolved by owner above, and
     * {@code confirmUpload} verifies the FILE belongs to the caller. Together they stop a merchant
     * confirming somebody else's upload onto their own scan. The file id must also be one this scan
     * issued — a file id from another scan, even the caller's own, is not found.
     */
    @Transactional
    public ScanDetails confirmPhoto(UUID scanId, String merchantId, UUID fileId) {
        CatalogScan scan = requireOwned(scanId, merchantId);
        requireUploading(scan);

        CatalogScanPhoto photo = photos.findByScanIdAndFileId(scanId, fileId)
                .orElseThrow(() -> new CatalogScanNotFoundException(
                        "Photo " + fileId + " is not part of scan " + scanId));
        storage.confirmUpload(fileId, merchantId);
        photo.markUploaded();
        return details(scan);
    }

    /**
     * Counts an attempt and marks the scan ANALYZING. The caller hands the returned attempt to
     * {@link CatalogScanAnalyzer#submit} after this transaction commits.
     */
    @Transactional
    public Started startAnalysis(UUID scanId, String merchantId) {
        // The merchant's lock, then the scan's: the one order any path taking both uses, so two
        // requests can never each hold one and wait for the other.
        scans.lockMerchant(merchantId);
        CatalogScan scan = lockOwned(scanId, merchantId);

        boolean anyUploaded = photos.findByScanIdOrderByPositionAsc(scanId).stream()
                .anyMatch(CatalogScanPhoto::isUploaded);
        if (!anyUploaded) {
            throw new ScanStateException("Add at least one shelf photo before scanning");
        }

        // One reading at a time per merchant. The analyser's two threads and short queue are shared
        // by every shop on the platform, so without this a few accounts firing scans side by side
        // could fill it and turn everybody else's scan into BUSY. Checked under the merchant's lock,
        // so two scans started together cannot each see the other still idle.
        Instant now = clock.instant();
        if (scans.countOtherLiveAnalyses(merchantId, scanId, CatalogScan.Status.ANALYZING,
                now.minus(limits.staleAfter())) > 0) {
            throw new ScanStateException(
                    "Another of your scans is still being read; start this one when it has finished");
        }

        int attempt;
        try {
            attempt = scan.startAnalysis(now, limits.maxAnalysisAttempts(), limits.staleAfter());
        } catch (IllegalStateException e) {
            throw new ScanStateException(e.getMessage());
        }
        return new Started(details(scan), attempt);
    }

    // ---------------------------------------------------------------- the analyser's side

    /** Empty when the scan has moved on — a newer attempt started, or it is no longer analysing. */
    @Transactional(readOnly = true)
    public Optional<AnalysisJob> loadForAnalysis(UUID scanId, int attempt) {
        return scans.findById(scanId)
                .filter(scan -> scan.awaits(attempt))
                .map(scan -> new AnalysisJob(
                        scanId,
                        attempt,
                        photos.findByScanIdOrderByPositionAsc(scanId).stream()
                                .filter(CatalogScanPhoto::isUploaded)
                                .map(p -> new PhotoRef(p.getId(), FilePurpose.PRODUCT_IMAGE.bucket(),
                                        p.getObjectKey()))
                                .toList(),
                        categoryChoices(scan.getStoreId())));
    }

    /**
     * Stores what the provider found and completes the scan.
     *
     * <p>Discards the result, rather than failing, when the scan has moved on: a job presumed lost
     * that finishes after its successor started must not overwrite the successor's answer.
     */
    @Transactional
    public void recordDetections(AnalysisJob job, String providerName, List<Detection> detections) {
        CatalogScan scan = scans.findById(job.scanId()).orElse(null);
        if (scan == null || !scan.awaits(job.attempt())) {
            log.info("Discarding a late result for scan {} attempt {}", job.scanId(), job.attempt());
            return;
        }

        List<Detections.Clean> kept =
                Detections.sanitize(detections, job.photos().size(), limits.maxItemsPerScan());
        int position = 0;
        for (Detections.Clean line : kept) {
            items.save(new CatalogScanItem(
                    scan.getId(),
                    job.photos().get(line.photoIndex()).photoId(),
                    position++,
                    line.name(),
                    line.brand(),
                    line.size(),
                    resolveCategory(line.category(), job.categories()),
                    line.confidence(),
                    line.priceGuess(),
                    toBox(line.box())));
        }
        scan.complete(providerName, clock.instant());
        log.info("Scan {} complete: {} lines from {}", scan.getId(), kept.size(), providerName);
    }

    @Transactional
    public void recordFailure(UUID scanId, int attempt, FailureCode code) {
        scans.findById(scanId)
                .filter(scan -> scan.awaits(attempt))
                .ifPresent(scan -> scan.fail(code, clock.instant()));
    }

    /**
     * The analyser could not even queue this attempt: its pool was full. Nothing was sent to the
     * provider and nothing billed, so the attempt is handed back — a pool filled by other shops must
     * not use up this merchant's retries. The scan still fails as BUSY, which the client words as
     * "try again shortly" and offers the retry for.
     */
    @Transactional
    public void recordBusy(UUID scanId, int attempt) {
        scans.findById(scanId)
                .filter(scan -> scan.awaits(attempt))
                .ifPresent(scan -> scan.refuseAsBusy(clock.instant()));
    }

    // ---------------------------------------------------------------- reading and deciding

    @Transactional(readOnly = true)
    public ScanDetails read(UUID scanId, String merchantId) {
        return details(requireOwned(scanId, merchantId));
    }

    /**
     * The merchant's newest scan from the last day that is still waiting on them, if any.
     *
     * <p>A scan lives here, not on the screen that started it. An Android process killed while the
     * camera was open, a merchant who left while the photos were being read, a portal tab reloaded:
     * each of those used to strand the scan — its photos, a share of the day's allowance and, with a
     * real provider on, a paid reading — because nothing could find it again. This is what the
     * screen asks on opening, so it carries on where the merchant left off.
     *
     * <p>"Still waiting" means there is something the merchant can still do with it: photos can be
     * added; a reading is under way, or was lost with its pod and may be restarted; a failed reading
     * has an attempt left; or a complete scan has a line not yet kept or skipped. A scan with none of
     * those is finished, and offering it again would only stand between the merchant and a new one.
     * The newest such scan wins — the one the merchant was last busy with.
     *
     * <p>The quota's own window, so the answer is always one of the scans counted against today.
     * Keyed on the caller like every read here; a store id only narrows it, and a store the caller
     * does not own simply matches none of their scans.
     */
    @Transactional(readOnly = true)
    public Optional<ScanDetails> current(String merchantId, UUID storeId) {
        List<CatalogScan> recent = scans.findByMerchantIdAndCreatedAtAfterOrderByCreatedAtDesc(
                merchantId, clock.instant().minus(QUOTA_WINDOW));
        for (CatalogScan scan : recent) {
            if ((storeId == null || storeId.equals(scan.getStoreId())) && stillWaiting(scan)) {
                return Optional.of(details(scan, recent.size()));
            }
        }
        return Optional.empty();
    }

    private boolean stillWaiting(CatalogScan scan) {
        return switch (scan.effectiveStatus(clock.instant(), limits.staleAfter())) {
            case UPLOADING, ANALYZING -> true;
            case FAILED -> scan.getAnalysisAttempts() < limits.maxAnalysisAttempts();
            case COMPLETE -> items.existsByScanIdAndStatus(scan.getId(), CatalogScanItem.Status.PENDING);
        };
    }

    /** Saves a line's corrections without deciding it. */
    @Transactional
    public ScanDetails updateItem(UUID scanId, String merchantId, UUID itemId, String name,
                                  BigDecimal price, UUID categoryId) {
        CatalogScan scan = lockOwned(scanId, merchantId);
        requireComplete(scan);
        CatalogScanItem item = requireItem(scanId, itemId);
        requireValidPrice(price, true);
        validateCategory(categoryId, scan.getStoreId());
        try {
            item.edit(name.trim(), price, categoryId);
        } catch (IllegalStateException e) {
            throw new ScanStateException(e.getMessage());
        }
        return details(scan);
    }

    @Transactional
    public ScanDetails rejectItem(UUID scanId, String merchantId, UUID itemId) {
        CatalogScan scan = lockOwned(scanId, merchantId);
        requireComplete(scan);
        CatalogScanItem item = requireItem(scanId, itemId);
        try {
            item.reject(clock.instant());
        } catch (IllegalStateException e) {
            throw new ScanStateException(e.getMessage());
        }
        return details(scan);
    }

    /**
     * Accepts and rejects lines in one go — all of them, or none.
     *
     * <p>One request for the whole review, because the alternative is one create per line and the
     * shared gateway rate limit (average 20, burst 40 per token) is sized for people, not for a
     * screen firing thirty creates at once. All-or-nothing, because a half-applied review leaves
     * the merchant unable to tell which of their lines became products.
     *
     * <p>Every accepted line becomes a DRAFT through {@link CatalogService#create}, filed under the
     * scan's store. Never published — see the class comment.
     */
    @Transactional
    public ScanDetails commit(UUID scanId, String merchantId, List<Acceptance> accept,
                              List<UUID> reject) {
        CatalogScan scan = lockOwned(scanId, merchantId);
        requireComplete(scan);

        List<Acceptance> accepting = accept == null ? List.of() : accept;
        List<UUID> rejecting = reject == null ? List.of() : reject;
        Set<UUID> seen = new HashSet<>();
        for (Acceptance a : accepting) {
            if (!seen.add(a.itemId())) {
                throw new CatalogRuleViolationException("Line " + a.itemId() + " appears twice");
            }
        }
        for (UUID id : rejecting) {
            if (!seen.add(id)) {
                throw new CatalogRuleViolationException("Line " + id + " appears twice");
            }
        }

        Instant now = clock.instant();
        for (Acceptance a : accepting) {
            CatalogScanItem item = requireItem(scanId, a.itemId());
            if (item.getStatus() != CatalogScanItem.Status.PENDING) {
                throw new ScanStateException("Line " + a.itemId() + " was already decided");
            }
            requireValidPrice(a.price(), false);
            String name = a.name() == null ? "" : a.name().trim();
            if (name.isEmpty()) {
                throw new CatalogRuleViolationException("Line " + a.itemId() + " needs a name");
            }

            Product product = catalog.create(merchantId, new ProductRequest(
                    name, null, a.price(), a.categoryId(), scan.getStoreId(), null, null));
            item.accept(product.getId(), name, a.price(), a.categoryId(), now);
        }
        for (UUID id : rejecting) {
            CatalogScanItem item = requireItem(scanId, id);
            try {
                item.reject(now);
            } catch (IllegalStateException e) {
                throw new ScanStateException(e.getMessage());
            }
        }

        log.info("Scan {}: merchant {} accepted {} and rejected {} lines as drafts",
                scanId, merchantId, accepting.size(), rejecting.size());
        return details(scan);
    }

    /**
     * Deletes a scan's shelf photos once no line on it is waiting any more.
     *
     * <p>Shelf photos are a picture of the merchant's stock room, kept in the public-read
     * product-images bucket, and nothing needs them once every line is kept or skipped: the drafts
     * carry no photo from them. So they go, through the same {@code softDelete} a product photo's
     * removal uses — the object, and its metadata marked deleted, so nothing resolves a URL to it.
     *
     * <p>Called by the controller after the save has committed, never inside it: an object delete
     * cannot be rolled back, and a save that failed after its photos were gone would leave lines
     * waiting on pictures that no longer exist. Not {@code @Transactional} for the same reason —
     * each delete is its own, so one that fails cannot take the others, or the save's answer, down
     * with it. Best effort per photo: the bucket's expiry rule for {@code scans/} (MinIO bootstrap)
     * takes whatever this misses, along with every scan abandoned before it was finished.
     *
     * @return the scan as it now stands
     */
    public ScanDetails discardPhotosOnceDecided(UUID scanId, String merchantId) {
        CatalogScan scan = requireOwned(scanId, merchantId);
        if (scan.getStatus() == CatalogScan.Status.COMPLETE
                && !items.existsByScanIdAndStatus(scanId, CatalogScanItem.Status.PENDING)) {
            for (CatalogScanPhoto photo : photos.findByScanIdOrderByPositionAsc(scanId)) {
                try {
                    storage.softDelete(photo.getFileId(), merchantId);
                } catch (RuntimeException e) {
                    log.warn("Scan {}: shelf photo {} was not deleted after the save; the scans/ "
                            + "expiry rule will take it: {}", scanId, photo.getFileId(), e.toString());
                }
            }
        }
        return details(scan);
    }

    // ---------------------------------------------------------------- internals

    private ScanDetails details(CatalogScan scan) {
        return details(scan, recentScans(scan.getMerchantId()));
    }

    private ScanDetails details(CatalogScan scan, long recent) {
        Instant now = clock.instant();
        return new ScanDetails(
                scan,
                scan.effectiveStatus(now, limits.staleAfter()),
                scan.effectiveFailure(now, limits.staleAfter()),
                photos.findByScanIdOrderByPositionAsc(scan.getId()),
                items.findByScanIdOrderByPositionAsc(scan.getId()),
                limits.maxPhotosPerScan(),
                Math.max(0, limits.maxAnalysisAttempts() - scan.getAnalysisAttempts()),
                (int) Math.max(0, limits.maxScansPerDay() - recent));
    }

    private long recentScans(String merchantId) {
        return scans.countByMerchantIdAndCreatedAtAfter(merchantId, clock.instant().minus(QUOTA_WINDOW));
    }

    private CatalogScan requireOwned(UUID scanId, String merchantId) {
        return scans.findByIdAndMerchantId(scanId, merchantId)
                .orElseThrow(() -> new CatalogScanNotFoundException("Scan " + scanId + " was not found"));
    }

    private CatalogScan lockOwned(UUID scanId, String merchantId) {
        return scans.lockOwned(scanId, merchantId)
                .orElseThrow(() -> new CatalogScanNotFoundException("Scan " + scanId + " was not found"));
    }

    private CatalogScanItem requireItem(UUID scanId, UUID itemId) {
        return items.findByIdAndScanId(itemId, scanId)
                .orElseThrow(() -> new CatalogScanNotFoundException(
                        "Line " + itemId + " is not part of scan " + scanId));
    }

    private static void requireUploading(CatalogScan scan) {
        if (scan.getStatus() != CatalogScan.Status.UPLOADING) {
            throw new ScanStateException("Photos can only be added before the scan is analysed");
        }
    }

    private static void requireComplete(CatalogScan scan) {
        if (scan.getStatus() != CatalogScan.Status.COMPLETE) {
            throw new ScanStateException("This scan has no lines to decide yet");
        }
    }

    /**
     * The product form's own price rule, applied here too.
     *
     * <p>The controller's bean validation says the same thing, and that is not redundant: this
     * service is also reachable from code that never passed through a controller, and a product
     * created with a zero price is a free item on a customer's screen.
     */
    private static void requireValidPrice(BigDecimal price, boolean optional) {
        if (price == null) {
            if (optional) {
                return;
            }
            throw new CatalogRuleViolationException("A price is needed before a line becomes a product");
        }
        if (price.signum() <= 0 || price.stripTrailingZeros().scale() > 2) {
            throw new CatalogRuleViolationException(
                    "A price must be greater than zero, with at most two decimals");
        }
    }

    private Store requireOwnedStore(String merchantId, UUID storeId) {
        return stores.ownedBy(merchantId).stream()
                .filter(store -> store.getId().equals(storeId))
                .findFirst()
                .orElseThrow(() -> new StoreService.StoreNotFoundException(storeId.toString()));
    }

    /** The same rule as {@code CatalogService}: a platform category, or a section of this store. */
    private void validateCategory(UUID categoryId, UUID storeId) {
        if (categoryId == null) {
            return;
        }
        Category category = categories.findById(categoryId)
                .orElseThrow(() -> new CategoryNotFoundException(categoryId));
        if (!category.isPlatformOwned() && !category.isOwnedByStore(storeId)) {
            throw new CategoryNotFoundException(categoryId);
        }
    }

    private List<CategoryChoice> categoryChoices(UUID storeId) {
        List<CategoryChoice> choices = new ArrayList<>();
        categories.findByStoreIdOrderByPositionAscNameAsc(storeId)
                .forEach(c -> choices.add(new CategoryChoice(c.getId(), c.getName(), true)));
        categories.findByStoreIdIsNull()
                .forEach(c -> choices.add(new CategoryChoice(c.getId(), c.getName(), false)));
        return choices;
    }

    /**
     * A suggested section name back to an id — only ever one that was offered.
     *
     * <p>Exact match, ignoring case and surrounding space, store sections first. No fuzzy matching:
     * a near miss filed under the wrong shelf is worse than no suggestion, which the merchant sees
     * as an empty picker and fills in.
     */
    static UUID resolveCategory(String suggested, List<CategoryChoice> choices) {
        if (suggested == null || suggested.isBlank()) {
            return null;
        }
        String wanted = suggested.trim().toLowerCase(Locale.ROOT);
        for (CategoryChoice choice : choices) {
            if (choice.name() != null && choice.name().trim().toLowerCase(Locale.ROOT).equals(wanted)) {
                return choice.id();
            }
        }
        return null;
    }

    /**
     * To the column's four decimals, and still inside the photo afterwards.
     *
     * <p>Rounding each edge up independently can push a box that ended exactly on the photo's edge
     * a hair past it, and the table refuses a box that leaves its photo — which would fail the
     * whole scan over a tag's last pixel. So the far edges are clamped after rounding.
     */
    static CatalogScanItem.Box toBox(com.delivery.product.vision.VisionProvider.Box box) {
        if (box == null) {
            return null;
        }
        BigDecimal one = BigDecimal.ONE;
        BigDecimal left = clamp(BigDecimal.valueOf(box.left()).setScale(4, RoundingMode.HALF_UP));
        BigDecimal top = clamp(BigDecimal.valueOf(box.top()).setScale(4, RoundingMode.HALF_UP));
        BigDecimal width = BigDecimal.valueOf(box.width()).setScale(4, RoundingMode.HALF_UP)
                .min(one.subtract(left));
        BigDecimal height = BigDecimal.valueOf(box.height()).setScale(4, RoundingMode.HALF_UP)
                .min(one.subtract(top));
        if (width.signum() <= 0 || height.signum() <= 0) {
            return null;
        }
        return new CatalogScanItem.Box(left, top, width, height);
    }

    private static BigDecimal clamp(BigDecimal value) {
        return value.max(BigDecimal.ZERO).min(BigDecimal.ONE);
    }

    // ---------------------------------------------------------------- exceptions

    /** A scan, photo or line the caller does not own or that does not exist. Mapped to 404. */
    public static class CatalogScanNotFoundException extends RuntimeException {
        public CatalogScanNotFoundException(String message) {
            super(message);
        }
    }

    /** The daily limit is spent. Mapped to 429, with the limit in the body. */
    public static class ScanQuotaExceededException extends RuntimeException {

        private final int limit;

        public ScanQuotaExceededException(int limit) {
            super("You can start " + limit + " scans a day; try again tomorrow");
            this.limit = limit;
        }

        public int getLimit() {
            return limit;
        }
    }

    /** The scan is not in a state for that — already analysing, complete, out of attempts. 409. */
    public static class ScanStateException extends RuntimeException {
        public ScanStateException(String message) {
            super(message);
        }
    }
}
