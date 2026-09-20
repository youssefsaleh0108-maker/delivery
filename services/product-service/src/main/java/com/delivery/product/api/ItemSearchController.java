package com.delivery.product.api;

import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.delivery.platform.security.CurrentUser;
import com.delivery.product.api.dto.ItemSearchDtos.ItemSearchPageResponse;
import com.delivery.product.api.dto.ItemSearchDtos.ItemSearchRequest;
import com.delivery.product.domain.GeoPoint;
import com.delivery.product.service.CatalogService;
import com.delivery.product.service.ItemSearchService;
import com.delivery.product.service.ItemSearchService.ItemQuery;
import com.delivery.product.service.ItemSearchService.ItemSearchResult;
import com.delivery.product.service.ItemSearchThrottle;
import com.delivery.product.service.ProductImageService;
import com.delivery.product.service.StoreService;

/**
 * The customer item search: the shops that sell what the customer typed, grouped by shop
 * ({@link ItemSearchService}).
 *
 * <p>Under {@code /api/products/search} beside the product API. {@code search} is a literal segment,
 * which Spring prefers to {@code ProductController}'s {@code /{id}}, as {@code CatalogScanController}
 * notes for {@code scans}; and no product endpoint takes a POST at {@code /{id}/items}.
 *
 * <p>Any signed-in caller, like the storefront and "near me", and for their reason: a point is where
 * somebody is standing, so no signed-out caller gets a proximity oracle, while a customer, a merchant
 * checking their own listing and back office all read the same public cards and shelves. Nothing here
 * is scoped to the caller except the star on each card, which is the caller's own, and the limit on how
 * often one account may search ({@link ItemSearchThrottle}), which is counted per account.
 */
@RestController
@RequestMapping("/api/products/search")
public class ItemSearchController {

    /** Shops per page when the request does not say. */
    static final int DEFAULT_PAGE_SIZE = 10;

    private final ItemSearchService itemSearch;
    private final StoreService storeService;
    private final CatalogService catalog;
    private final ProductImageService images;
    private final ItemSearchThrottle throttle;

    public ItemSearchController(ItemSearchService itemSearch, StoreService storeService,
                                CatalogService catalog, ProductImageService images,
                                ItemSearchThrottle throttle) {
        this.itemSearch = itemSearch;
        this.storeService = storeService;
        this.catalog = catalog;
        this.images = images;
        this.throttle = throttle;
    }

    /**
     * {@code POST /api/products/search/items}: a page of shops, each with its best matches.
     *
     * <p>A body rather than query parameters so the point never sits in a URL. Refused with 400 and a
     * {@code code}: {@code SEARCH_TOO_SHORT} (nothing to search, or a term under 2 characters),
     * {@code SEARCH_TOO_LONG}, {@code SEARCH_TOO_MANY_TERMS}, {@code SEARCH_BAD_BARCODE}; and 400
     * "Invalid location" for half a point, one out of range, or (0, 0), as every coordinate here is.
     * Once folded, a term with no word of two characters or more is {@code SEARCH_TOO_SHORT} and one
     * with more than five is {@code SEARCH_TOO_MANY_WORDS}. 429 {@code SEARCH_RATE_LIMITED} when the
     * account has searched too often, and 503 {@code SEARCH_TIMED_OUT} when the database gave up; both
     * with Retry-After.
     *
     * <p>The request is checked before the account is counted, so a search refused as malformed costs
     * the customer nothing; the account is counted before anything is read, so a refused one costs the
     * database nothing.
     */
    @PostMapping("/items")
    @PreAuthorize("isAuthenticated()")
    public ItemSearchPageResponse items(@RequestBody ItemSearchRequest request) {
        ItemQuery query = ItemQuery.of(request.q(), request.terms(), request.barcode());
        // Built before anything is read, so half a point or (0, 0) is refused rather than searched.
        GeoPoint centre = GeoPoint.ofNullable(request.latitude(), request.longitude());
        throttle.acquire(CurrentUser.requireId());
        ItemSearchResult result = itemSearch.search(query, centre,
                request.page() == null ? 0 : request.page(),
                request.size() == null ? DEFAULT_PAGE_SIZE : request.size());
        return ItemSearchPages.of(result, storeService, catalog, images);
    }
}
