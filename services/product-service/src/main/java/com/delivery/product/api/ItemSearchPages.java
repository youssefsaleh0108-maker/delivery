package com.delivery.product.api;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import org.springframework.data.domain.Page;

import com.delivery.platform.security.CurrentUser;
import com.delivery.product.api.dto.CatalogDtos.ProductResponse;
import com.delivery.product.api.dto.ItemSearchDtos.ItemSearchPageResponse;
import com.delivery.product.api.dto.ItemSearchDtos.ShopItemsResponse;
import com.delivery.product.domain.Product;
import com.delivery.product.domain.StoreOffer;
import com.delivery.product.service.CatalogService;
import com.delivery.product.service.CatalogService.ProductView;
import com.delivery.product.service.ItemSearchService.ItemSearchResult;
import com.delivery.product.service.ItemSearchService.ShopMatch;
import com.delivery.product.service.ProductImageService;
import com.delivery.product.service.StoreService;

/**
 * One page of the item search as a response: the typed search's and the photo search's, which draw
 * the same shops the same way, so there is one copy of how.
 */
final class ItemSearchPages {

    private ItemSearchPages() {
    }

    static ItemSearchPageResponse of(ItemSearchResult result, StoreService storeService,
                                     CatalogService catalog, ProductImageService images) {
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
