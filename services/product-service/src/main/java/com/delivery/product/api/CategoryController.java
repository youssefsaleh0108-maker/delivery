package com.delivery.product.api;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.stream.Collectors;

import jakarta.validation.Valid;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.delivery.product.api.dto.CatalogDtos.CategoryRequest;
import com.delivery.product.api.dto.CatalogDtos.CategoryResponse;
import com.delivery.product.domain.Category;
import com.delivery.product.service.CatalogService;
import com.delivery.product.service.ProductImageService;

@RestController
@RequestMapping("/api/categories")
public class CategoryController {

    private final CatalogService catalog;
    private final ProductImageService images;

    public CategoryController(CatalogService catalog, ProductImageService images) {
        this.catalog = catalog;
        this.images = images;
    }

    /**
     * The whole category tree in one call.
     *
     * <p>Assembled in memory from a single {@code findAll} rather than recursing with a query per
     * level: the tree is small, changes rarely, and every client needs all of it to render a
     * category picker.
     */
    @GetMapping
    public List<CategoryResponse> tree() {
        List<Category> all = catalog.allCategories();

        Map<UUID, List<Category>> byParent = all.stream()
                .filter(category -> category.getParentId() != null)
                .collect(Collectors.groupingBy(Category::getParentId,
                        LinkedHashMap::new, Collectors.toList()));

        return all.stream()
                .filter(category -> category.getParentId() == null)
                .sorted(java.util.Comparator.comparing(Category::getName))
                .map(root -> toResponse(root, byParent))
                .toList();
    }

    /**
     * Categories are platform-wide taxonomy, not per-merchant, so a merchant cannot invent one —
     * otherwise the catalog fragments into near-duplicate categories within a month.
     */
    @PostMapping
    @PreAuthorize("hasRole('BACKOFFICE')")
    public ResponseEntity<CategoryResponse> create(@Valid @RequestBody CategoryRequest request) {
        Category created = catalog.createCategory(request.name(), request.parentId());
        return ResponseEntity.status(HttpStatus.CREATED)
                .body(new CategoryResponse(created.getId(), created.getName(),
                        created.getParentId(), null, null, List.of()));
    }

    private CategoryResponse toResponse(Category category, Map<UUID, List<Category>> byParent) {
        List<CategoryResponse> children = byParent.getOrDefault(category.getId(), List.of()).stream()
                .sorted(java.util.Comparator.comparing(Category::getName))
                .map(child -> toResponse(child, byParent))
                .toList();

        return new CategoryResponse(category.getId(), category.getName(),
                category.getParentId(), images.resolveUrl(category.getImageRef()),
                category.getVertical(), children);
    }
}
