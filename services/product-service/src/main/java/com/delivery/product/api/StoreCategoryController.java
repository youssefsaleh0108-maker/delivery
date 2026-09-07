package com.delivery.product.api;

import java.util.List;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.Size;

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
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import com.delivery.platform.security.CurrentUser;
import com.delivery.product.domain.Category;
import com.delivery.product.domain.staff.Permission;
import com.delivery.product.service.StaffService;
import com.delivery.product.service.StoreAccess;
import com.delivery.product.service.StoreCategoryService;

/**
 * A shop's own catalogue sections.
 *
 * <p>Deliberately not part of {@link CategoryController}, which serves the platform taxonomy and is
 * BACKOFFICE-only. These rows belong to one store, and the permission that gates them is the same
 * one that gates prices and stock — a stockkeeper arranging shelves is doing their job.
 */
@RestController
@RequestMapping("/api/stores/{storeId}/categories")
public class StoreCategoryController {

    private final StoreCategoryService sections;
    private final StaffService staff;

    public StoreCategoryController(StoreCategoryService sections, StaffService staff) {
        this.sections = sections;
        this.staff = staff;
    }

    @GetMapping
    @PreAuthorize("isAuthenticated()")
    public List<StoreCategoryResponse> list(@PathVariable UUID storeId) {
        require(storeId, null);
        return sections.sectionsOf(storeId).stream().map(this::toResponse).toList();
    }

    @PostMapping
    @PreAuthorize("isAuthenticated()")
    public ResponseEntity<StoreCategoryResponse> create(@PathVariable UUID storeId,
                                                        @Valid @RequestBody SectionRequest request) {
        require(storeId, Permission.MODIFY_INVENTORY_PRICING);
        Category created = sections.create(storeId, request.name(), request.parentId());
        return ResponseEntity.status(HttpStatus.CREATED).body(toResponse(created));
    }

    @PutMapping("/{categoryId}")
    @PreAuthorize("isAuthenticated()")
    public StoreCategoryResponse rename(@PathVariable UUID storeId, @PathVariable UUID categoryId,
                                        @Valid @RequestBody SectionRequest request) {
        require(storeId, Permission.MODIFY_INVENTORY_PRICING);
        return toResponse(sections.rename(storeId, categoryId, request.name()));
    }

    /** The drag-to-reorder result: the full ordered list of this shop's section ids. */
    @PutMapping("/order")
    @PreAuthorize("isAuthenticated()")
    public List<StoreCategoryResponse> reorder(@PathVariable UUID storeId,
                                               @Valid @RequestBody ReorderRequest request) {
        require(storeId, Permission.MODIFY_INVENTORY_PRICING);
        return sections.reorder(storeId, request.categoryIds()).stream()
                .map(this::toResponse)
                .toList();
    }

    @DeleteMapping("/{categoryId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    @PreAuthorize("isAuthenticated()")
    public void delete(@PathVariable UUID storeId, @PathVariable UUID categoryId) {
        require(storeId, Permission.MODIFY_INVENTORY_PRICING);
        sections.delete(storeId, categoryId);
    }

    /**
     * Resolve the caller's access, and optionally assert a permission.
     *
     * <p>A caller with no relationship to the store gets 404 rather than 403, so probing store ids
     * cannot map out which shops exist.
     */
    private StoreAccess require(UUID storeId, Permission permission) {
        StoreAccess access = staff.accessFor(storeId, CurrentUser.requireId());
        if (!access.isAnything()) {
            throw new StoreStaffController.StoreNotVisibleException(storeId);
        }
        if (permission != null) {
            access.require(permission);
        }
        return access;
    }

    private StoreCategoryResponse toResponse(Category category) {
        return new StoreCategoryResponse(
                category.getId(),
                category.getName(),
                category.getParentId(),
                category.getPosition(),
                sections.productCount(category.getId()));
    }

    public record StoreCategoryResponse(UUID id, String name, UUID parentId, short position,
                                        long productCount) {
    }

    public record SectionRequest(@NotBlank @Size(max = 128) String name, UUID parentId) {
    }

    public record ReorderRequest(@NotEmpty List<UUID> categoryIds) {
    }
}
