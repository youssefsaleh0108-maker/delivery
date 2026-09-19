package com.delivery.product.api;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import org.springframework.data.domain.Page;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.delivery.platform.security.CurrentUser;
import com.delivery.product.api.dto.CatalogDtos.ProductResponse;
import com.delivery.product.api.dto.ItemSearchDtos.ItemSearchPageResponse;
import com.delivery.product.api.dto.ItemSearchDtos.ItemSearchRequest;
import com.delivery.product.api.dto.ItemSearchDtos.ShopItemsResponse;
import com.delivery.product.domain.GeoPoint;
import com.delivery.product.domain.Product;
import com.delivery.product.domain.StoreOffer;
import com.delivery.product.service.CatalogService;
import com.delivery.product.service.CatalogService.ProductView;
import com.delivery.product.service.ItemSearchService;
import com.delivery.product.service.ItemSearchService.ItemQuery;
import com.delivery.product.service.ItemSearchService.ItemSearchResult;
import com.delivery.product.service.ItemSearchService.ShopMatch;
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
 * is scoped to the caller except the star on each card, which is the caller's own.
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

    public ItemSearchController(ItemSearchService itemSearch, StoreService storeService,
                                CatalogService catalog, ProductImageService images) {
        this.itemSearch = itemSearch;
        this.storeService = storeService;
        this.catalog = catalog;
        this.images = images;
    }

    /**
     * {@code POST /api/products/search/items}: a page of shops, each with its best matches.
     *
     * <p>A body rather than query parameters so the point never sits in a URL. Refused with 400 and a
     * {@code code}: {@code SEARCH_TOO_SHORT} (nothing to search, or a term under 2 characters),
     * {@code SEARCH_TOO_LONG}, {@code SEARCH_TOO_MANY_TERMS}, {@code SEARCH_BAD_BARCODE}; and 400
     * "Invalid location" for half a point, one out of range, or (0, 0), as every coordinate here is.
     */
    @PostMapping("/items")
    @PreAuthorize("isAuthenticated()")
    public ItemSearchPageResponse items(@RequestBody ItemSearchRequest request) {
        ItemQuery query = ItemQuery.of(request.q(), request.terms(), request.barcode());
        // Built before anything is read, so half a point or (0, 0) is refused rather than searched.
        GeoPoint centre = GeoPoint.ofNullable(request.latitude(), request.longitude());
        ItemSearchResult result = itemSearch.search(query, centre,
                request.page() == null ? 0 : request.page(),
                request.size() == null ? DEFAULT_PAGE_SIZE : request.size());

        Page<ShopMatch> page = result.page();
        Set<UUID> starred = storeService.favoriteIdsOf(CurrentUser.id().orElse(null));
        Map<UUID, List<StoreOffer>> offersByStore = storeService.liveOffersByStore();

        // One read of terms for every product on the page, however many shops it spans.
        List<Product> shown = page.getContent().stream()
                .flatMap(match -> match.items().stream())
                .toList();
        Map<UUID, ProductResponse> responses = new HashMap<>();
        for (ProductView view : catalog.views(shown)) {
            responses.put(view.product().getId(), ProductResponses.of(view, images));
        }

        List<ShopItemsResponse> content = page.getContent().stream()
                .map(match -> new ShopItemsResponse(
                        StoreCards.of(match.store(), starred, offersByStore, images),
                        match.store().store().getLatitude(),
                        match.store().store().getLongitude(),
                        // Whole metres, as "near me" gives them: the pin was dropped by hand.
                        match.distanceMetres() == null ? null : Math.round(match.distanceMetres()),
                        match.items().stream().map(p -> responses.get(p.getId())).toList(),
                        match.matchedInStore()))
                .toList();
        return new ItemSearchPageResponse(content, page.getNumber(), page.getSize(),
                page.getTotalElements(), page.getTotalPages(), result.truncated(),
                result.candidateLimit(), result.nearby());
    }
}
