package com.delivery.product.api;

import java.util.List;

import com.delivery.product.api.dto.CatalogDtos.ProductResponse;
import com.delivery.product.api.dto.CatalogDtos.ServiceTermsResponse;
import com.delivery.product.domain.Product;
import com.delivery.product.service.CatalogService.ProductView;
import com.delivery.product.service.ProductImageService;
import com.delivery.product.service.ProductImageService.ImageUrl;

/**
 * The one mapping from a product to its response, shared by every endpoint that returns products.
 *
 * <p>The shop's shelf and the product API used to build the response by hand, one copy each. A
 * service offer's terms and "From" price are exactly the kind of field one copy gains and the other
 * forgets, and a customer would then see "From $15.00" in search and a bare price on the provider's
 * page for the same offer.
 */
final class ProductResponses {

    private ProductResponses() {
    }

    static ProductResponse of(ProductView view, ProductImageService images) {
        Product product = view.product();
        List<String> refs = product.getImageRefs();
        // One resolve, two lists: full-size for the hero, list-sized for the rows. Splitting this
        // into two calls would double the metadata lookups on the browse path for nothing.
        List<ImageUrl> resolved = images.resolveImages(refs);
        return new ProductResponse(
                product.getId(),
                product.getMerchantId(),
                product.getStoreId(),
                product.getName(),
                product.getDescription(),
                product.getPrice(),
                product.getCategoryId(),
                refs,
                resolved.stream().map(ImageUrl::full).toList(),
                resolved.stream().map(ImageUrl::thumb).toList(),
                product.getStatus(),
                product.getSku(),
                product.getBarcode(),
                product.isInStock(),
                product.getCreatedAt(),
                product.getUpdatedAt(),
                product.isGiftFeatured(),
                ServiceTermsResponse.of(view.service()),
                view.fromPrice());
    }
}
