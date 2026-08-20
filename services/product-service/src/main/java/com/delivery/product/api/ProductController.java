package com.delivery.product.api;

import java.util.List;
import java.util.UUID;

import jakarta.validation.Valid;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;
import org.springframework.data.web.PageableDefault;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.delivery.platform.security.CurrentUser;
import com.delivery.product.api.dto.CatalogDtos.PageResponse;
import com.delivery.product.api.dto.CatalogDtos.ProductRequest;
import com.delivery.product.api.dto.CatalogDtos.ProductResponse;
import com.delivery.product.api.dto.OptionDtos.ChosenOptionResponse;
import com.delivery.product.api.dto.OptionDtos.OptionGroupRequest;
import com.delivery.product.api.dto.OptionDtos.OptionGroupResponse;
import com.delivery.product.api.dto.OptionDtos.OptionResponse;
import com.delivery.product.api.dto.OptionDtos.PriceRequest;
import com.delivery.product.api.dto.OptionDtos.PriceResponse;
import com.delivery.product.domain.ProductOptionGroup;
import com.delivery.product.service.ProductOptionService;
import com.delivery.product.service.ProductOptionService.PricedSelection;
import com.delivery.product.domain.Product;
import com.delivery.product.service.CatalogService;
import com.delivery.product.service.ProductImageService;

/**
 * The catalog API.
 *
 * <p>Two layers of authorisation, and both are needed. {@code @PreAuthorize} answers "may this kind
 * of user call this endpoint at all" from the realm role. The service layer then answers "may
 * <em>this</em> user touch <em>this</em> row" from the {@code sub} claim. Role alone would let any
 * merchant edit any merchant's catalog (Section 3).
 */
@RestController
@RequestMapping("/api/products")
public class ProductController {

    private final CatalogService catalog;
    private final ProductImageService images;
    private final ProductOptionService optionService;

    public ProductController(CatalogService catalog, ProductImageService images,
                             ProductOptionService optionService) {
        this.catalog = catalog;
        this.images = images;
        this.optionService = optionService;
    }

    /** Customer-facing browse. ACTIVE products only, from every merchant. */
    @GetMapping
    public PageResponse<ProductResponse> browse(
            @RequestParam(required = false) UUID categoryId,
            @RequestParam(required = false) String search,
            @PageableDefault(size = 20, sort = "createdAt", direction = Sort.Direction.DESC)
            Pageable pageable) {

        Page<Product> page = catalog.browseCatalog(categoryId, search, pageable);
        return PageResponse.of(page.map(this::toResponse));
    }

    /**
     * The Merchant Portal's list: everything the caller owns, in any status.
     *
     * <p>Declared before {@code /{id}} would otherwise be ambiguous — Spring resolves the literal
     * path first, but keeping them adjacent makes the intent obvious to the next reader.
     */
    @GetMapping("/mine")
    @PreAuthorize("hasRole('MERCHANT')")
    public PageResponse<ProductResponse> mine(
            @PageableDefault(size = 20, sort = "createdAt", direction = Sort.Direction.DESC)
            Pageable pageable) {

        Page<Product> page = catalog.listOwnedBy(CurrentUser.requireId(), pageable);
        return PageResponse.of(page.map(this::toResponse));
    }

    @GetMapping("/{id}")
    public ProductResponse read(@PathVariable UUID id) {
        // The viewer id is passed in so the service can decide whether a DRAFT is visible; an
        // anonymous-but-authenticated customer simply won't match the owner.
        return toResponse(catalog.read(id, CurrentUser.id().orElse(null)));
    }

    @PostMapping
    @PreAuthorize("hasRole('MERCHANT')")
    public ResponseEntity<ProductResponse> create(@Valid @RequestBody ProductRequest request) {
        Product product = catalog.create(CurrentUser.requireId(), request);
        return ResponseEntity.status(HttpStatus.CREATED).body(toResponse(product));
    }

    @PutMapping("/{id}")
    @PreAuthorize("hasRole('MERCHANT')")
    public ProductResponse update(@PathVariable UUID id, @Valid @RequestBody ProductRequest request) {
        return toResponse(catalog.update(id, CurrentUser.requireId(), request));
    }

    @PostMapping("/{id}/publish")
    @PreAuthorize("hasRole('MERCHANT')")
    public ProductResponse publish(@PathVariable UUID id) {
        return toResponse(catalog.publish(id, CurrentUser.requireId()));
    }

    /** Archive, not delete — past orders still reference this product. */
    @DeleteMapping("/{id}")
    @PreAuthorize("hasRole('MERCHANT')")
    public ProductResponse archive(@PathVariable UUID id) {
        return toResponse(catalog.archive(id, CurrentUser.requireId()));
    }

    // ---------------------------------------------------------------- options

    /** The questions to ask before this product can go in a basket. */
    @GetMapping("/{id}/options")
    public List<OptionGroupResponse> options(@PathVariable UUID id) {
        return optionService.forProduct(id).stream().map(ProductController::toGroup).toList();
    }

    /**
     * Prices a selection.
     *
     * <p>Open to any authenticated caller because the customer app needs it to show a running total
     * as options are ticked — and because it is a read that reveals nothing the menu does not.
     * Order Manager calls the same endpoint at checkout, so the price shown and the price charged
     * come from one implementation.
     */
    @PostMapping("/{id}/price")
    public PriceResponse price(@PathVariable UUID id, @RequestBody(required = false) PriceRequest request) {
        PricedSelection priced = optionService.price(
                id, request == null ? List.of() : request.optionIds());
        return new PriceResponse(
                priced.basePrice(),
                priced.unitPrice(),
                priced.options().stream()
                        .map(o -> new ChosenOptionResponse(
                                o.groupName(), o.optionName(), o.priceDelta()))
                        .toList());
    }

    /** Replaces the product's whole option structure. */
    @PutMapping("/{id}/options")
    @PreAuthorize("hasRole('MERCHANT')")
    public List<OptionGroupResponse> setOptions(
            @PathVariable UUID id,
            @Valid @RequestBody List<OptionGroupRequest> groups) {
        return optionService.replace(id, CurrentUser.requireId(), groups).stream()
                .map(ProductController::toGroup)
                .toList();
    }

    private static OptionGroupResponse toGroup(ProductOptionGroup group) {
        return new OptionGroupResponse(
                group.getId(),
                group.getName(),
                group.getMinSelect(),
                group.getMaxSelect(),
                group.isRequired(),
                group.isSingleChoice(),
                group.getOptions().stream()
                        .map(o -> new OptionResponse(o.getId(), o.getName(), o.getPriceDelta(),
                                o.isDefault(), o.isAvailable()))
                        .toList());
    }

    private ProductResponse toResponse(Product product) {
        List<String> refs = product.getImageRefs();
        return new ProductResponse(
                product.getId(),
                product.getMerchantId(),
                product.getStoreId(),
                product.getName(),
                product.getDescription(),
                product.getPrice(),
                product.getCategoryId(),
                refs,
                images.resolveUrls(refs),
                product.getStatus(),
                product.getCreatedAt(),
                product.getUpdatedAt());
    }
}
