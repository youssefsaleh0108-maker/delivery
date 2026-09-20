package com.delivery.product.api;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.util.unit.DataSize;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RequestPart;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

import com.delivery.platform.security.CurrentUser;
import com.delivery.product.api.dto.CatalogDtos.ProductResponse;
import com.delivery.product.api.dto.PhotoFindDtos.PhotoFindMatchResponse;
import com.delivery.product.api.dto.PhotoFindDtos.PhotoFindResponse;
import com.delivery.product.api.dto.PhotoFindDtos.PhotoFindSuggestionResponse;
import com.delivery.product.api.dto.PhotoSearchDtos.UnderstoodResponse;
import com.delivery.product.domain.Product;
import com.delivery.product.service.CatalogService;
import com.delivery.product.service.CatalogService.ProductView;
import com.delivery.product.service.PhotoFindService;
import com.delivery.product.service.PhotoFindService.FindResult;
import com.delivery.product.service.PhotoFindService.Match;
import com.delivery.product.service.PhotoFindService.Suggestion;
import com.delivery.product.service.ProductImageService;
import com.delivery.product.vision.Descriptions;

/**
 * "Do I already have this?": a merchant photographs a pack and sees it in their own catalogue
 * ({@link PhotoFindService}).
 *
 * <p><strong>MERCHANT only</strong>, like Merchant Blitz's scans and for the same reasons: every read
 * is a paid call against the merchant's own daily allowance, and the answer is their private
 * catalogue, in every status. An employee (MERCHANT_STAFF), a customer, a rider and the back office
 * are all refused before the service is reached; the service then resolves every shop by the caller's
 * own {@code sub}, so another merchant's shop id is a 404.
 *
 * <p>Under {@code /api/products/mine} beside the merchant's own product list. The photo comes straight
 * here as a multipart part and is never stored — see {@link PhotoSearchController} for why.
 */
@RestController
@RequestMapping("/api/products/mine")
@PreAuthorize("hasRole('MERCHANT')")
public class PhotoFindController {

    private final PhotoFindService find;
    private final CatalogService catalog;
    private final ProductImageService images;
    private final long maxPhotoBytes;

    public PhotoFindController(PhotoFindService find, CatalogService catalog, ProductImageService images,
                               @Value("${spring.servlet.multipart.max-file-size:2MB}") DataSize maxPhotoSize) {
        this.find = find;
        this.catalog = catalog;
        this.images = images;
        this.maxPhotoBytes = maxPhotoSize.toBytes();
    }

    /**
     * {@code POST /api/products/mine/find-by-photo}: the merchant's own products that match the photo,
     * and what to prefill a new one with when none does.
     *
     * <p>Multipart: {@code photo}, a JPEG or a PNG of at most 2 MB, and optionally {@code storeId} —
     * one of the caller's shops, or none to search every goods shop they own. A shop that is not
     * theirs is 404; a service shop is 422, as a Blitz scan of one is.
     *
     * <p>Unlike a customer's search, this answers with the reader Blitz uses, so until real
     * recognition is on it answers with sample lines and says so ({@code sample}). Refusals are photo
     * search's, with 429 {@code PHOTO_FIND_LIMIT} for the merchant's own daily and per-minute limits.
     */
    @PostMapping("/find-by-photo")
    public PhotoFindResponse findByPhoto(
            @RequestPart(name = "photo", required = false) MultipartFile photo,
            @RequestParam(name = "storeId", required = false) UUID storeId) {
        String merchantId = CurrentUser.requireId();
        byte[] bytes = PhotoUploads.bytesOf(photo, maxPhotoBytes);

        FindResult found = find.find(merchantId, bytes, storeId);
        Descriptions.Clean understood = found.understood();

        // One read of terms for every product on the answer, as the item search builds its page.
        List<Product> matched = found.matches().stream().map(Match::product).toList();
        Map<UUID, ProductResponse> responses = new HashMap<>();
        for (ProductView view : catalog.views(matched)) {
            responses.put(view.product().getId(), ProductResponses.of(view, images));
        }
        List<PhotoFindMatchResponse> matches = new ArrayList<>();
        for (Match match : found.matches()) {
            ProductResponse response = responses.get(match.product().getId());
            if (response != null) {
                matches.add(new PhotoFindMatchResponse(response, match.matchedBy()));
            }
        }

        Suggestion suggestion = found.suggestion();
        return new PhotoFindResponse(
                found.provider(),
                found.sample(),
                new UnderstoodResponse(understood.name(), understood.nameAr(), understood.brand(),
                        understood.size(), understood.barcode(), understood.isProduct()),
                matches,
                suggestion == null ? null
                        : new PhotoFindSuggestionResponse(suggestion.name(), suggestion.barcode(),
                                suggestion.categoryId()),
                found.left());
    }
}
