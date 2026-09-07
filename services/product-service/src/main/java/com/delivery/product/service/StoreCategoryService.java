package com.delivery.product.service;

import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.product.domain.Category;
import com.delivery.product.domain.CategoryRepository;
import com.delivery.product.domain.ProductRepository;
import com.delivery.product.service.CatalogService.CatalogRuleViolationException;

/**
 * A shop's own catalogue sections — the shelves a merchant authors and drags into order.
 *
 * <p>Separate from {@link CatalogService}'s platform taxonomy on purpose: these rows are owned by
 * one store, only that store sees them, and a merchant may create them freely. The platform rows
 * remain BACKOFFICE-only, because a shared taxonomy that anyone can extend stops being a taxonomy.
 */
@Service
public class StoreCategoryService {

    private static final Logger log = LoggerFactory.getLogger(StoreCategoryService.class);

    /** A shop with hundreds of sections is a mistake, not a use case. */
    private static final int MAX_SECTIONS = 200;

    private final CategoryRepository categories;
    private final ProductRepository products;

    public StoreCategoryService(CategoryRepository categories, ProductRepository products) {
        this.categories = categories;
        this.products = products;
    }

    @Transactional(readOnly = true)
    public List<Category> sectionsOf(UUID storeId) {
        return categories.findByStoreIdOrderByPositionAscNameAsc(storeId);
    }

    /** How many live products sit in each section — the "28 products" line on every row. */
    @Transactional(readOnly = true)
    public long productCount(UUID categoryId) {
        return products.countByCategoryId(categoryId);
    }

    @Transactional
    public Category create(UUID storeId, String name, UUID parentId) {
        String trimmed = requireName(name);
        if (categories.existsByStoreIdAndNameIgnoreCase(storeId, trimmed)) {
            throw new CatalogRuleViolationException(
                    "This shop already has a section called " + trimmed);
        }
        if (categories.countByStoreId(storeId) >= MAX_SECTIONS) {
            throw new CatalogRuleViolationException(
                    "A shop cannot have more than " + MAX_SECTIONS + " sections");
        }
        // A shop section may hang under a PLATFORM category (so "Breads" can sit inside the
        // platform's Bakery vertical), but never under another shop's row.
        if (parentId != null) {
            Category parent = categories.findById(parentId)
                    .orElseThrow(() -> new CatalogRuleViolationException(
                            "Parent category " + parentId + " does not exist"));
            if (!parent.isPlatformOwned()) {
                throw new CatalogRuleViolationException(
                        "A section can only sit under a platform category");
            }
        }
        short position = (short) Math.min(categories.countByStoreId(storeId), Short.MAX_VALUE);
        Category section = categories.save(new Category(storeId, trimmed, position));
        log.info("Store {} created section {}", storeId, section.getId());
        return section;
    }

    @Transactional
    public Category rename(UUID storeId, UUID categoryId, String name) {
        Category section = requireSection(storeId, categoryId);
        section.rename(requireName(name));
        return section;
    }

    /**
     * Applies the order the merchant dragged the rows into.
     *
     * <p>Takes the full ordered list rather than a single moved id: a drag can move one row past
     * many others, and rewriting every position from one authoritative list is what stops the
     * sequence drifting into duplicates after a few reorders.
     */
    @Transactional
    public List<Category> reorder(UUID storeId, List<UUID> orderedIds) {
        List<Category> sections = new ArrayList<>(sectionsOf(storeId));
        if (orderedIds.size() != sections.size()) {
            throw new CatalogRuleViolationException(
                    "The new order must list every section exactly once");
        }
        short position = 0;
        for (UUID id : orderedIds) {
            Category section = sections.stream()
                    .filter(c -> c.getId().equals(id))
                    .findFirst()
                    .orElseThrow(() -> new CatalogRuleViolationException(
                            "Section " + id + " does not belong to this shop"));
            section.moveTo(position++);
        }
        return sectionsOf(storeId);
    }

    @Transactional
    public void delete(UUID storeId, UUID categoryId) {
        Category section = requireSection(storeId, categoryId);
        long inUse = products.countByCategoryId(categoryId);
        if (inUse > 0) {
            // Refuse rather than orphan: silently nulling categoryId on live products would move
            // goods off the shelf a customer is browsing with no way to tell what happened.
            throw new CatalogRuleViolationException(
                    "Category still has " + inUse + " product" + (inUse == 1 ? "" : "s"));
        }
        categories.delete(section);
        log.info("Store {} deleted section {}", storeId, categoryId);
    }

    private Category requireSection(UUID storeId, UUID categoryId) {
        Category section = categories.findById(categoryId)
                .orElseThrow(() -> new CatalogRuleViolationException("No such section"));
        if (!section.isOwnedByStore(storeId)) {
            // Covers both "belongs to another shop" and "is platform taxonomy": a merchant may not
            // rename or delete either.
            throw new CatalogRuleViolationException("No such section");
        }
        return section;
    }

    private static String requireName(String name) {
        String trimmed = name == null ? "" : name.trim();
        if (trimmed.isEmpty()) {
            throw new CatalogRuleViolationException("A section needs a name");
        }
        if (trimmed.length() > 128) {
            throw new CatalogRuleViolationException("That name is too long");
        }
        return trimmed;
    }
}
