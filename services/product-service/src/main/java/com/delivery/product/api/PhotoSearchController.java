package com.delivery.product.api;

import java.math.BigDecimal;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.util.unit.DataSize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RequestPart;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

import com.delivery.platform.security.CurrentUser;
import com.delivery.product.api.dto.ItemSearchDtos.ItemSearchPageResponse;
import com.delivery.product.api.dto.PhotoSearchDtos.NextQueryResponse;
import com.delivery.product.api.dto.PhotoSearchDtos.PhotoCapabilitiesResponse;
import com.delivery.product.api.dto.PhotoSearchDtos.PhotoSearchResponse;
import com.delivery.product.api.dto.PhotoSearchDtos.UnderstoodResponse;
import com.delivery.product.domain.GeoPoint;
import com.delivery.product.service.CatalogService;
import com.delivery.product.service.PhotoSearchException;
import com.delivery.product.service.PhotoSearchService;
import com.delivery.product.service.PhotoSearchService.PhotoSearchResult;
import com.delivery.product.service.ProductImageService;
import com.delivery.product.service.StoreService;
import com.delivery.product.vision.Descriptions;

/**
 * Search by photo: a customer photographs a product and sees the shops near them that sell it
 * ({@link PhotoSearchService}).
 *
 * <p>Beside the typed item search under {@code /api/products/search}; {@code search} is a literal
 * segment, which Spring prefers to {@code ProductController}'s {@code /{id}}.
 *
 * <p><strong>The photo comes straight here, with no presign.</strong> A stated exception to
 * {@code ProductImageController}'s rule that image bytes go to MinIO and never through this service:
 * this photo is read once and dropped, and must not be stored anywhere — least of all in the
 * product-images bucket, which is public-read. So it is a multipart part, held in memory (the
 * container's {@code file-size-threshold} is above its size limit, so no part is ever written to disk),
 * handed to the reader, and gone when the request is. It never touches storage, the database, the disk
 * or a log.
 */
@RestController
@RequestMapping("/api/products/search")
public class PhotoSearchController {

    private final PhotoSearchService photoSearch;
    private final StoreService storeService;
    private final CatalogService catalog;
    private final ProductImageService images;
    private final long maxPhotoBytes;

    public PhotoSearchController(PhotoSearchService photoSearch, StoreService storeService,
                                 CatalogService catalog, ProductImageService images,
                                 @Value("${spring.servlet.multipart.max-file-size:2MB}") DataSize maxPhotoSize) {
        this.photoSearch = photoSearch;
        this.storeService = storeService;
        this.catalog = catalog;
        this.images = images;
        this.maxPhotoBytes = maxPhotoSize.toBytes();
    }

    /**
     * {@code POST /api/products/search/photo}: the shops that sell what the photo shows, as the typed
     * search's first page plus what the photo was read as.
     *
     * <p>CUSTOMER only: every photo read is a paid call counted against a customer's own daily
     * allowance, and a merchant finds their own products by photo at
     * {@code /api/products/mine/find-by-photo} instead. Multipart: {@code photo}, a JPEG or a PNG of at
     * most 2 MB, and optionally {@code latitude} and {@code longitude} together. The next pages come
     * from {@code POST /items} with {@code nextQuery}, so the photo is sent once.
     *
     * <p>Refused with a {@code code}: 503 {@code PHOTO_SEARCH_UNAVAILABLE} (no real reader, or switched
     * off, checked before anything is read), 413 {@code PHOTO_TOO_LARGE}, 415 {@code PHOTO_TYPE}, 400
     * "Invalid location" for half a point, 503 {@code PHOTO_READER_BUSY} with Retry-After, 422
     * {@code PHOTO_UNREADABLE}, 429 {@code PHOTO_SEARCH_LIMIT} with {@code limit}, {@code scope} and
     * {@code retryAfterSeconds}, 422 {@code PHOTO_REFUSED}, 502 {@code PHOTO_READER_FAILED}. A photo of no
     * product is 200 with no shops. Only a refusal after the photo was accepted, decoded and given a
     * reader slot counts against the allowance.
     */
    @PostMapping("/photo")
    @PreAuthorize("hasRole('CUSTOMER')")
    public PhotoSearchResponse photo(@RequestPart(name = "photo", required = false) MultipartFile photo,
                                     @RequestParam(name = "latitude", required = false) BigDecimal latitude,
                                     @RequestParam(name = "longitude", required = false) BigDecimal longitude) {
        String accountId = CurrentUser.requireId();
        // Before the photo is even read: with no real reader there is nothing it could be sent to.
        if (!photoSearch.available()) {
            throw PhotoSearchException.unavailable();
        }
        byte[] bytes = PhotoUploads.bytesOf(photo, maxPhotoBytes);
        GeoPoint centre = GeoPoint.ofNullable(latitude, longitude);

        PhotoSearchResult found = photoSearch.search(accountId, bytes, centre,
                ItemSearchController.DEFAULT_PAGE_SIZE);
        ItemSearchPageResponse page = ItemSearchPages.of(found.result(), storeService, catalog, images);
        Descriptions.Clean understood = found.understood();
        return new PhotoSearchResponse(page.content(), page.page(), page.size(), page.totalElements(),
                page.totalPages(), page.truncated(), page.candidateLimit(), page.nearby(),
                new UnderstoodResponse(understood.name(), understood.nameAr(), understood.brand(),
                        understood.size(), understood.barcode(), understood.isProduct()),
                found.similar(),
                found.nextQuery() == null ? null
                        : new NextQueryResponse(found.nextQuery().terms(), found.nextQuery().barcode()),
                found.left());
    }

    /**
     * {@code GET /api/products/search/capabilities}: whether this account may search by photo, how many
     * photos it has left today, and how large a photo may be.
     *
     * <p>Any signed-in caller, because Home asks it for everybody; {@code photoSearch} is true only for
     * a CUSTOMER, and only while customer photo search is switched on with a real reader configured.
     * The app draws the camera only when it is true, so no customer ever meets a camera that cannot
     * work, and none ever gets sample results.
     */
    @GetMapping("/capabilities")
    @PreAuthorize("isAuthenticated()")
    public PhotoCapabilitiesResponse capabilities() {
        boolean photoSearchable = CurrentUser.hasRole("CUSTOMER") && photoSearch.available();
        int left = photoSearchable ? photoSearch.left(CurrentUser.requireId()) : 0;
        return new PhotoCapabilitiesResponse(photoSearchable, left, maxPhotoBytes);
    }
}
