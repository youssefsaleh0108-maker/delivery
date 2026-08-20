package com.delivery.product.service;

import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.platform.outbox.OutboxRecorder;
import com.delivery.product.api.dto.CatalogDtos.ProductRequest;
import com.delivery.product.domain.Category;
import com.delivery.product.domain.CategoryRepository;
import com.delivery.product.domain.Product;
import com.delivery.product.domain.ProductRepository;
import com.delivery.product.event.CatalogEvents;

/**
 * Catalog reads and writes.
 *
 * <p>Every mutating method takes the caller's id explicitly rather than reaching into the
 * SecurityContext. That makes the ownership rule a visible parameter of the operation instead of
 * ambient state, and it means the rule is testable without a mocked security context.
 */
@Service
public class CatalogService {

    private static final Logger log = LoggerFactory.getLogger(CatalogService.class);

    private final ProductRepository products;
    private final CategoryRepository categories;
    private final StoreService storeService;
    private final OutboxRecorder outbox;

    public CatalogService(ProductRepository products, CategoryRepository categories,
                          StoreService storeService, OutboxRecorder outbox) {
        this.products = products;
        this.categories = categories;
        this.storeService = storeService;
        this.outbox = outbox;
    }

    // ---------------------------------------------------------------- reads

    @Transactional(readOnly = true)
    public Page<Product> browseCatalog(UUID categoryId, String search, Pageable pageable) {
        return products.findActiveCatalog(categoryId, SearchPatterns.like(search), pageable);
    }

    /** A store's shelf. The store landing page's main query. */
    @Transactional(readOnly = true)
    public Page<Product> browseStore(UUID storeId, UUID categoryId, String search,
                                     Pageable pageable) {
        return products.findActiveInStore(storeId, categoryId, SearchPatterns.like(search), pageable);
    }

    /**
     * A page of specific products from one store.
     *
     * <p>Backs Buy Again: it knows the ids it wants from order history, and needs them re-read from
     * the live catalog so the price and description are today's. Store-scoped as well as id-scoped,
     * so a caller cannot use it to read another shop's rows.
     */
    @Transactional(readOnly = true)
    public Page<Product> browseStoreByIds(UUID storeId, java.util.List<UUID> ids,
                                          Pageable pageable) {
        return products.findActiveInStoreByIds(storeId, ids, pageable);
    }

    /**
     * Re-reads a set of products by id, for "Buy Again".
     *
     * <p>Order history stores what was bought at the time; this resolves those ids back to live
     * catalog rows so a repeat order is priced and described as it is today, not as it was. Products
     * that have since been archived simply do not come back, which is the correct outcome — the
     * alternative is offering a customer something the shop no longer sells.
     */
    @Transactional(readOnly = true)
    public java.util.List<Product> readAllActive(java.util.Collection<UUID> ids) {
        if (ids == null || ids.isEmpty()) {
            return java.util.List.of();
        }
        return products.findByIdIn(ids).stream()
                .filter(p -> p.getStatus() == Product.Status.ACTIVE)
                .toList();
    }

    @Transactional(readOnly = true)
    public Page<Product> listOwnedBy(String merchantId, Pageable pageable) {
        return products.findByMerchantId(merchantId, pageable);
    }

    /**
     * Reads one product for a viewer.
     *
     * <p>A DRAFT or ARCHIVED product is visible only to the merchant that owns it — otherwise a
     * customer could enumerate ids and read unpublished pricing.
     */
    @Transactional(readOnly = true)
    public Product read(UUID id, String viewerId) {
        Product product = products.findById(id)
                .orElseThrow(() -> new ProductNotFoundException(id));

        if (product.getStatus() != Product.Status.ACTIVE && !product.isOwnedBy(viewerId)) {
            // Deliberately "not found" rather than "forbidden": a 403 would confirm the id exists.
            throw new ProductNotFoundException(id);
        }
        return product;
    }

    // ---------------------------------------------------------------- writes

    @Transactional
    public Product create(String merchantId, ProductRequest request) {
        validateCategory(request.categoryId());

        // Every product lives in a store. A merchant who has not set one up yet gets one created
        // here rather than a not-null violation, so "add your first product" never needs "but first
        // go and create a store" wired into the client.
        UUID storeId = request.storeId() != null
                ? requireOwnedStore(merchantId, request.storeId())
                : storeService.requireStoreFor(merchantId).getId();

        Product product = new Product(
                merchantId,
                storeId,
                request.name(),
                request.description(),
                request.price(),
                request.categoryId());
        products.save(product);

        // Same transaction as the insert above: the event and the row commit together or not at
        // all, which is the whole point of the outbox (Section 7).
        outbox.record(CatalogEvents.AGGREGATE_TYPE, product.getId().toString(),
                CatalogEvents.PRODUCT_CREATED, CatalogEvents.ProductSnapshot.of(product));

        log.info("Merchant {} created product {}", merchantId, product.getId());
        return product;
    }

    @Transactional
    public Product update(UUID id, String merchantId, ProductRequest request) {
        Product product = requireOwned(id, merchantId);
        validateCategory(request.categoryId());

        product.update(request.name(), request.description(), request.price(), request.categoryId());

        outbox.record(CatalogEvents.AGGREGATE_TYPE, product.getId().toString(),
                CatalogEvents.PRODUCT_UPDATED, CatalogEvents.ProductSnapshot.of(product));
        return product;
    }

    @Transactional
    public Product publish(UUID id, String merchantId) {
        Product product = requireOwned(id, merchantId);
        try {
            product.publish();
        } catch (IllegalStateException e) {
            throw new CatalogRuleViolationException(e.getMessage());
        }

        outbox.record(CatalogEvents.AGGREGATE_TYPE, product.getId().toString(),
                CatalogEvents.PRODUCT_PUBLISHED, CatalogEvents.ProductSnapshot.of(product));
        return product;
    }

    /**
     * Withdraws a product from sale.
     *
     * <p>There is no hard delete. Past orders reference products, and an order history that cannot
     * name what was bought is useless for support or for the accounting reconciliation in Phase 4.
     */
    @Transactional
    public Product archive(UUID id, String merchantId) {
        Product product = requireOwned(id, merchantId);
        product.archive();

        outbox.record(CatalogEvents.AGGREGATE_TYPE, product.getId().toString(),
                CatalogEvents.PRODUCT_ARCHIVED, CatalogEvents.ProductSnapshot.of(product));
        return product;
    }

    // ---------------------------------------------------------------- categories

    @Transactional(readOnly = true)
    public java.util.List<Category> rootCategories() {
        return categories.findByParentIdIsNullOrderByName();
    }

    @Transactional(readOnly = true)
    public java.util.List<Category> childrenOf(UUID parentId) {
        return categories.findByParentIdOrderByName(parentId);
    }

    @Transactional(readOnly = true)
    public java.util.List<Category> allCategories() {
        return categories.findAll();
    }

    @Transactional
    public Category createCategory(String name, UUID parentId) {
        if (parentId != null && !categories.existsById(parentId)) {
            throw new CatalogRuleViolationException("Parent category " + parentId + " does not exist");
        }
        return categories.save(new Category(name, parentId));
    }

    // ---------------------------------------------------------------- internals

    /**
     * The one place the ownership rule is applied to a write.
     *
     * <p>Loads by id AND merchant id in a single query, so a merchant asking for someone else's
     * product gets an empty result rather than a row this code then has to remember to check.
     */
    private Product requireOwned(UUID id, String merchantId) {
        return products.findByIdAndMerchantId(id, merchantId)
                .orElseThrow(() -> {
                    // Distinguish the two cases in the log (useful for support) while returning the
                    // same 404 to the caller either way.
                    if (products.existsById(id)) {
                        log.warn("Merchant {} attempted to modify product {} they do not own",
                                merchantId, id);
                    }
                    return new ProductNotFoundException(id);
                });
    }

    /**
     * Checks the merchant owns the store they are filing a product under.
     *
     * <p>Without this a merchant could put products into a competitor's storefront by passing their
     * store id — the same class of hole that keeping {@code merchantId} out of the request body
     * closes for products themselves.
     */
    private UUID requireOwnedStore(String merchantId, UUID storeId) {
        boolean owned = storeService.ownedBy(merchantId).stream()
                .anyMatch(s -> s.getId().equals(storeId));
        if (!owned) {
            throw new CatalogRuleViolationException("Store " + storeId + " is not yours");
        }
        return storeId;
    }

    private void validateCategory(UUID categoryId) {
        if (categoryId != null && !categories.existsById(categoryId)) {
            throw new CatalogRuleViolationException("Category " + categoryId + " does not exist");
        }
    }

    // ---------------------------------------------------------------- exceptions

    public static class ProductNotFoundException extends RuntimeException {
        public ProductNotFoundException(UUID id) {
            super("Product " + id + " was not found");
        }
    }

    public static class CatalogRuleViolationException extends RuntimeException {
        public CatalogRuleViolationException(String message) {
            super(message);
        }
    }
}
