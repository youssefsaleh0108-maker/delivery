package com.delivery.product.domain;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * One product a vision provider read off a shelf photo, and what the merchant decided about it.
 *
 * <p>Two prices live here and they must never be confused. {@code priceGuess} is the provider's
 * estimate of a typical shelf price — a guess, labelled as one on every surface — and the server
 * never promotes it. {@code price} is what the merchant says they sell at, and a product is only
 * ever created from that.
 */
@Entity
@Table(name = "catalog_scan_items")
public class CatalogScanItem {

    public enum Status {
        /** Waiting for the merchant. */
        PENDING,
        /** Became a DRAFT product — see {@link #getProductId()}. */
        ACCEPTED,
        /** The merchant does not sell it, or the provider was wrong. */
        REJECTED
    }

    /** Where on its photo the item sits, as fractions of the photo's width and height. */
    public record Box(BigDecimal left, BigDecimal top, BigDecimal width, BigDecimal height) {
    }

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "scan_id", nullable = false, updatable = false)
    private UUID scanId;

    @Column(name = "photo_id", nullable = false, updatable = false)
    private UUID photoId;

    @Column(name = "position", nullable = false, updatable = false)
    private short position;

    @Column(name = "name", nullable = false, length = 200)
    private String name;

    @Column(name = "brand", length = 120, updatable = false)
    private String brand;

    @Column(name = "size_label", length = 60, updatable = false)
    private String sizeLabel;

    @Column(name = "category_id")
    private UUID categoryId;

    @Column(name = "confidence", nullable = false, precision = 4, scale = 3, updatable = false)
    private BigDecimal confidence;

    @Column(name = "price_guess", precision = 12, scale = 2, updatable = false)
    private BigDecimal priceGuess;

    @Column(name = "price", precision = 12, scale = 2)
    private BigDecimal price;

    @Column(name = "box_left", precision = 5, scale = 4, updatable = false)
    private BigDecimal boxLeft;

    @Column(name = "box_top", precision = 5, scale = 4, updatable = false)
    private BigDecimal boxTop;

    @Column(name = "box_width", precision = 5, scale = 4, updatable = false)
    private BigDecimal boxWidth;

    @Column(name = "box_height", precision = 5, scale = 4, updatable = false)
    private BigDecimal boxHeight;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false, length = 16)
    private Status status = Status.PENDING;

    @Column(name = "product_id")
    private UUID productId;

    @Column(name = "decided_at")
    private Instant decidedAt;

    protected CatalogScanItem() {
        // for JPA
    }

    public CatalogScanItem(UUID scanId, UUID photoId, int position, String name, String brand,
                           String sizeLabel, UUID categoryId, BigDecimal confidence,
                           BigDecimal priceGuess, Box box) {
        this.id = UUID.randomUUID();
        this.scanId = scanId;
        this.photoId = photoId;
        this.position = (short) position;
        this.name = name;
        this.brand = brand;
        this.sizeLabel = sizeLabel;
        this.categoryId = categoryId;
        this.confidence = confidence;
        this.priceGuess = priceGuess;
        if (box != null) {
            this.boxLeft = box.left();
            this.boxTop = box.top();
            this.boxWidth = box.width();
            this.boxHeight = box.height();
        }
        this.status = Status.PENDING;
    }

    /**
     * The merchant's corrections, saved without deciding yet.
     *
     * @throws IllegalStateException once the line is decided: an accepted line is a product now and
     *                               is edited as one, and a rejected line has nothing to edit
     */
    public void edit(String name, BigDecimal price, UUID categoryId) {
        requirePending();
        this.name = name;
        this.price = price;
        this.categoryId = categoryId;
    }

    public void accept(UUID productId, String name, BigDecimal price, UUID categoryId, Instant now) {
        requirePending();
        this.productId = productId;
        this.name = name;
        this.price = price;
        this.categoryId = categoryId;
        this.status = Status.ACCEPTED;
        this.decidedAt = now;
    }

    public void reject(Instant now) {
        requirePending();
        this.status = Status.REJECTED;
        this.decidedAt = now;
    }

    private void requirePending() {
        if (status != Status.PENDING) {
            throw new IllegalStateException(
                    "This line was already " + status.name().toLowerCase(java.util.Locale.ROOT));
        }
    }

    public Box getBox() {
        return boxLeft == null ? null : new Box(boxLeft, boxTop, boxWidth, boxHeight);
    }

    public UUID getId() {
        return id;
    }

    public UUID getScanId() {
        return scanId;
    }

    public UUID getPhotoId() {
        return photoId;
    }

    public int getPosition() {
        return position;
    }

    public String getName() {
        return name;
    }

    public String getBrand() {
        return brand;
    }

    public String getSizeLabel() {
        return sizeLabel;
    }

    public UUID getCategoryId() {
        return categoryId;
    }

    public BigDecimal getConfidence() {
        return confidence;
    }

    public BigDecimal getPriceGuess() {
        return priceGuess;
    }

    public BigDecimal getPrice() {
        return price;
    }

    public Status getStatus() {
        return status;
    }

    public UUID getProductId() {
        return productId;
    }

    public Instant getDecidedAt() {
        return decidedAt;
    }
}
