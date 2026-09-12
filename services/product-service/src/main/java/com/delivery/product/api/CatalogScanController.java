package com.delivery.product.api;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.delivery.platform.security.CurrentUser;
import com.delivery.platform.storage.PresignedUpload;
import com.delivery.product.api.dto.CatalogDtos.PresignUploadRequest;
import com.delivery.product.api.dto.CatalogDtos.PresignUploadResponse;
import com.delivery.product.api.dto.CatalogScanDtos.BoxResponse;
import com.delivery.product.api.dto.CatalogScanDtos.CommitRequest;
import com.delivery.product.api.dto.CatalogScanDtos.CreateScanRequest;
import com.delivery.product.api.dto.CatalogScanDtos.ItemEditRequest;
import com.delivery.product.api.dto.CatalogScanDtos.ItemResponse;
import com.delivery.product.api.dto.CatalogScanDtos.PhotoResponse;
import com.delivery.product.api.dto.CatalogScanDtos.ScanResponse;
import com.delivery.product.domain.CatalogScanItem;
import com.delivery.product.domain.CatalogScanPhoto;
import com.delivery.product.service.CatalogScanAnalyzer;
import com.delivery.product.service.CatalogScanService;
import com.delivery.product.service.CatalogScanService.Acceptance;
import com.delivery.product.service.CatalogScanService.ScanDetails;
import com.delivery.product.service.CatalogScanService.Started;
import com.delivery.product.service.ProductImageService;
import com.delivery.product.service.ProductImageService.ImageUrl;
import com.delivery.product.vision.FakeVisionProvider;

/**
 * Merchant Blitz: shelf photos in, a draft catalogue out.
 *
 * <p><strong>Who may call it: MERCHANT, and only about their own scans.</strong> The role gate is
 * here, on the class, and covers every method — employees (MERCHANT_STAFF), customers, riders and
 * the back office are all refused before the service is reached. The service then resolves every
 * scan by id AND the caller's {@code sub}, so one merchant naming another's scan id gets the same
 * 404 as an id that was never issued. A pending applicant carries MERCHANT and may scan: every
 * line it accepts is a DRAFT, and publishing stays gated on approval where it always was.
 *
 * <p>Under {@code /api/products} rather than a prefix of its own because that prefix is already
 * routed to this service by every ingress — a new one would be three template edits and a
 * re-render for no gain. Spring prefers the literal {@code scans} segment over
 * {@code ProductController}'s {@code /{id}}, and a scan id is never a product id.
 */
@RestController
@RequestMapping("/api/products/scans")
@PreAuthorize("hasRole('MERCHANT')")
public class CatalogScanController {

    private final CatalogScanService scans;
    private final CatalogScanAnalyzer analyzer;
    private final ProductImageService images;

    public CatalogScanController(CatalogScanService scans, CatalogScanAnalyzer analyzer,
                                 ProductImageService images) {
        this.scans = scans;
        this.analyzer = analyzer;
        this.images = images;
    }

    /** Starts a scan. 429 once the day's scans are spent. */
    @PostMapping
    public ResponseEntity<ScanResponse> create(@RequestBody(required = false) CreateScanRequest request) {
        ScanDetails details = scans.create(CurrentUser.requireId(),
                request == null ? null : request.storeId());
        return ResponseEntity.status(HttpStatus.CREATED).body(toResponse(details));
    }

    /** Step 1 of a shelf-photo upload: a one-shot URL to PUT the bytes to. */
    @PostMapping("/{scanId}/photos")
    public ResponseEntity<PresignUploadResponse> presignPhoto(
            @PathVariable UUID scanId, @Valid @RequestBody PresignUploadRequest request) {
        PresignedUpload upload = scans.presignPhoto(scanId, CurrentUser.requireId(),
                request.contentType());
        return ResponseEntity.status(HttpStatus.CREATED).body(new PresignUploadResponse(
                upload.fileId(), upload.uploadUrl(), upload.objectKey(), upload.contentType(),
                upload.expiresAt(), upload.maxSizeBytes()));
    }

    /** Step 3: the bytes landed. (Step 2 is the client's own PUT straight to storage.) */
    @PostMapping("/{scanId}/photos/{fileId}/confirm")
    public ScanResponse confirmPhoto(@PathVariable UUID scanId, @PathVariable UUID fileId) {
        return toResponse(scans.confirmPhoto(scanId, CurrentUser.requireId(), fileId));
    }

    /**
     * Reads the photos. 202: the analysis runs off the request thread, and the client polls
     * {@code GET /{scanId}} until the status leaves ANALYZING.
     */
    @PostMapping("/{scanId}/analyze")
    public ResponseEntity<ScanResponse> analyze(@PathVariable UUID scanId) {
        Started started = scans.startAnalysis(scanId, CurrentUser.requireId());
        // After the transaction above has committed, so the job never reads a scan that still
        // says UPLOADING.
        analyzer.submit(scanId, started.attempt());
        return ResponseEntity.status(HttpStatus.ACCEPTED).body(toResponse(started.details()));
    }

    @GetMapping("/{scanId}")
    public ScanResponse read(@PathVariable UUID scanId) {
        return toResponse(scans.read(scanId, CurrentUser.requireId()));
    }

    /** Saves a line's corrections without deciding it. */
    @PutMapping("/{scanId}/items/{itemId}")
    public ScanResponse updateItem(@PathVariable UUID scanId, @PathVariable UUID itemId,
                                   @Valid @RequestBody ItemEditRequest request) {
        return toResponse(scans.updateItem(scanId, CurrentUser.requireId(), itemId,
                request.name(), request.price(), request.categoryId()));
    }

    @PostMapping("/{scanId}/items/{itemId}/reject")
    public ScanResponse rejectItem(@PathVariable UUID scanId, @PathVariable UUID itemId) {
        return toResponse(scans.rejectItem(scanId, CurrentUser.requireId(), itemId));
    }

    /**
     * The review, in one request: accepted lines become DRAFT products in the scan's store,
     * rejected lines are closed. All or nothing. Nothing is published.
     */
    @PostMapping("/{scanId}/commit")
    public ScanResponse commit(@PathVariable UUID scanId, @Valid @RequestBody CommitRequest request) {
        List<Acceptance> accept = request.accept() == null ? List.of() : request.accept().stream()
                .map(a -> new Acceptance(a.itemId(), a.name(), a.price(), a.categoryId()))
                .toList();
        return toResponse(scans.commit(scanId, CurrentUser.requireId(), accept, request.reject()));
    }

    // ---------------------------------------------------------------- mapping

    private ScanResponse toResponse(ScanDetails details) {
        List<CatalogScanPhoto> photos = details.photos();

        // Resolved one key at a time, not batched: resolveImages DROPS a key whose metadata is not
        // confirmed, so its answer cannot be lined up against the keys by position. Six photos at
        // most, so this is six lookups at worst.
        Map<String, String> urlByKey = new HashMap<>();
        for (CatalogScanPhoto photo : photos) {
            if (photo.isUploaded()) {
                String url = ImageUrl.fullOf(images.resolveImage(photo.getObjectKey()));
                if (url != null) {
                    urlByKey.put(photo.getObjectKey(), url);
                }
            }
        }
        Map<UUID, UUID> fileByPhoto = new HashMap<>();
        photos.forEach(p -> fileByPhoto.put(p.getId(), p.getFileId()));

        String provider = details.scan().getProvider();
        return new ScanResponse(
                details.scan().getId(),
                details.scan().getStoreId(),
                details.status(),
                provider,
                FakeVisionProvider.NAME.equals(provider),
                details.failure(),
                details.maxPhotos(),
                details.attemptsLeft(),
                details.scansLeftToday(),
                photos.stream()
                        .map(p -> new PhotoResponse(p.getFileId(), p.getPosition(), p.getStatus(),
                                p.isUploaded() ? urlByKey.get(p.getObjectKey()) : null))
                        .toList(),
                details.items().stream().map(item -> toItem(item, fileByPhoto)).toList(),
                details.scan().getCreatedAt(),
                details.scan().getCompletedAt());
    }

    private static ItemResponse toItem(CatalogScanItem item, Map<UUID, UUID> fileByPhoto) {
        CatalogScanItem.Box box = item.getBox();
        return new ItemResponse(
                item.getId(),
                fileByPhoto.get(item.getPhotoId()),
                item.getName(),
                item.getBrand(),
                item.getSizeLabel(),
                item.getCategoryId(),
                item.getConfidence(),
                item.getPriceGuess(),
                item.getPrice(),
                box == null ? null : new BoxResponse(box.left(), box.top(), box.width(), box.height()),
                item.getStatus(),
                item.getProductId());
    }
}
