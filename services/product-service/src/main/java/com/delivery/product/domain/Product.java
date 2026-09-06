package com.delivery.product.domain;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

@Entity
@Table(name = "products")
public class Product {

    public enum Status {
        /** Created but not on the customer-facing catalog. Where a product starts. */
        DRAFT,
        /** Visible to customers and orderable. */
        ACTIVE,
        /**
         * Withdrawn from sale. Products are archived, never deleted, because past orders reference
         * them and an order history that cannot name what was bought is worthless.
         */
        ARCHIVED
    }

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    /** The owning merchant's Keycloak {@code sub}. Never accepted from a request body. */
    @Column(name = "merchant_id", nullable = false, length = 64, updatable = false)
    private String merchantId;

    /**
     * The store this product sits in.
     *
     * <p>Redundant with {@code merchantId} only for as long as a merchant runs a single store, and
     * that is exactly why both exist: {@code merchantId} answers "who may edit this", {@code storeId}
     * answers "where does a customer find it". Collapsing them would make a second store
     * unrepresentable.
     */
    @Column(name = "store_id", nullable = false)
    private UUID storeId;

    @Column(name = "name", nullable = false, length = 200)
    private String name;

    @Column(name = "description", columnDefinition = "text")
    private String description;

    @Column(name = "price", nullable = false, precision = 12, scale = 2)
    private BigDecimal price;

    @Column(name = "category_id")
    private UUID categoryId;

    /**
     * The merchant's own code for this item, unique within the store when set.
     *
     * <p>Optional: most catalogues arrive without one, and the till can fall back to search.
     */
    @Column(name = "sku", length = 64)
    private String sku;

    /** Scanned at the till. Not unique — the same EAN legitimately appears in two stores. */
    @Column(name = "barcode", length = 32)
    private String barcode;

    /**
     * Whether inventory-service currently believes this item can be sold.
     *
     * <p>A read-only projection of {@code inventory.level_changed}, never set from a request: the
     * stock ledger is owned by inventory-service and this column only exists so the storefront can
     * filter without a cross-service call on its hot path. Products the merchant has not opted into
     * tracking have no ledger row and stay {@code true} forever.
     */
    @Column(name = "in_stock", nullable = false)
    private boolean inStock = true;

    /** Object keys in the {@code product-images} bucket, in display order. */
    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "image_refs", nullable = false, columnDefinition = "jsonb")
    private List<String> imageRefs = new ArrayList<>();

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false, length = 16)
    private Status status = Status.DRAFT;

    @Column(name = "created_at", nullable = false, insertable = false, updatable = false)
    private Instant createdAt;

    /** Maintained by a database trigger, so it cannot drift when a writer forgets to set it. */
    @Column(name = "updated_at", nullable = false, insertable = false, updatable = false)
    private Instant updatedAt;

    protected Product() {
        // for JPA
    }

    public Product(String merchantId, UUID storeId, String name, String description,
                   BigDecimal price, UUID categoryId) {
        this.id = UUID.randomUUID();
        this.merchantId = merchantId;
        this.storeId = storeId;
        this.name = name;
        this.description = description;
        this.price = price;
        this.categoryId = categoryId;
        this.status = Status.DRAFT;
        this.imageRefs = new ArrayList<>();
    }

    /**
     * The single ownership predicate for this aggregate.
     *
     * <p>Section 3: ownership is enforced in service code against the {@code sub} claim, not by
     * Keycloak. Holding the MERCHANT role says you may edit <em>some</em> products; this says which.
     */
    public boolean isOwnedBy(String userId) {
        return this.merchantId.equals(userId);
    }

    public void update(String name, String description, BigDecimal price, UUID categoryId,
                       String sku, String barcode) {
        this.name = name;
        this.description = description;
        this.price = price;
        this.categoryId = categoryId;
        assignCodes(sku, barcode);
    }

    /**
     * Sets the merchant's own item codes.
     *
     * <p>Blank is how a form says "cleared", so it is stored as absent: the partial unique index on
     * {@code (store_id, sku)} would otherwise treat several empty strings as a collision.
     */
    public void assignCodes(String sku, String barcode) {
        this.sku = blankToNull(sku);
        this.barcode = blankToNull(barcode);
    }

    /**
     * Applies inventory-service's view of whether this item is sellable.
     *
     * <p>Separate from {@link #update} because it arrives on the event bus, not from the merchant,
     * and must never be writable through the product API.
     */
    public void applyStockProjection(boolean inStock) {
        this.inStock = inStock;
    }

    private static String blankToNull(String value) {
        return (value == null || value.isBlank()) ? null : value.trim();
    }

    public void publish() {
        if (this.imageRefs.isEmpty()) {
            throw new IllegalStateException(
                    "A product needs at least one image before it can be published");
        }
        this.status = Status.ACTIVE;
    }

    public void archive() {
        this.status = Status.ARCHIVED;
    }

    public void addImage(String objectKey) {
        if (!this.imageRefs.contains(objectKey)) {
            this.imageRefs.add(objectKey);
        }
    }

    public boolean removeImage(String objectKey) {
        boolean removed = this.imageRefs.remove(objectKey);
        // A published product with no images would render as a blank card in the catalog.
        if (removed && this.imageRefs.isEmpty() && this.status == Status.ACTIVE) {
            this.status = Status.DRAFT;
        }
        return removed;
    }

    public UUID getId() {
        return id;
    }

    public String getMerchantId() {
        return merchantId;
    }

    public UUID getStoreId() {
        return storeId;
    }

    public String getName() {
        return name;
    }

    public String getDescription() {
        return description;
    }

    public BigDecimal getPrice() {
        return price;
    }

    public UUID getCategoryId() {
        return categoryId;
    }

    public String getSku() {
        return sku;
    }

    public String getBarcode() {
        return barcode;
    }

    public boolean isInStock() {
        return inStock;
    }

    public List<String> getImageRefs() {
        return Collections.unmodifiableList(imageRefs);
    }

    public Status getStatus() {
        return status;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public Instant getUpdatedAt() {
        return updatedAt;
    }
}
