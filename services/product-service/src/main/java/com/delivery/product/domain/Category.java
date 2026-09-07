package com.delivery.product.domain;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

@Entity
@Table(name = "categories")
public class Category {

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "name", nullable = false, length = 128)
    private String name;

    /** Null for a top-level category. */
    @Column(name = "parent_id")
    private UUID parentId;

    /** Object key in the product-images bucket. Null falls back to an icon in the clients. */
    @Column(name = "image_ref", length = 512)
    private String imageRef;

    /**
     * The storefront vertical this category stands for, if any.
     *
     * <p>Only set on the handful of root categories that appear in the home strip. It is what lets
     * that strip be data-driven — a row with a name and an uploaded picture — while the store filter
     * itself stays an enum, because stores carry a vertical rather than a category.
     */
    @Enumerated(EnumType.STRING)
    @Column(name = "vertical", length = 24)
    private Store.Vertical vertical;

    /**
     * The shop that authored this section, or null for platform taxonomy.
     *
     * <p>This is the whole ownership distinction: a null row is the platform's own category and is
     * what the customer app's vertical picker reads; a non-null row is one shop's shelf and is
     * visible only inside that shop.
     */
    @Column(name = "store_id")
    private UUID storeId;

    /** Display order within the owning store. Meaningless (and left at 0) for platform rows. */
    @Column(name = "position", nullable = false)
    private short position;

    @Column(name = "created_at", nullable = false, insertable = false, updatable = false)
    private Instant createdAt;

    /** Maintained by a database trigger, so it cannot drift when a writer forgets to set it. */
    @Column(name = "updated_at", nullable = false, insertable = false, updatable = false)
    private Instant updatedAt;

    protected Category() {
        // for JPA
    }

    public Category(String name, UUID parentId) {
        this.id = UUID.randomUUID();
        this.name = name;
        this.parentId = parentId;
    }

    /**
     * A section owned by one shop, appended at the given display position.
     *
     * <p>{@code parentId} is a parameter and not an afterthought: the first version of this
     * constructor omitted it, so a section created under a platform category silently came back
     * with no parent and the caller's validated input was discarded.
     */
    public Category(UUID storeId, String name, UUID parentId, short position) {
        this.id = UUID.randomUUID();
        this.storeId = storeId;
        this.name = name;
        this.parentId = parentId;
        this.position = position;
    }

    public void rename(String name) {
        this.name = name;
    }

    public void moveTo(short position) {
        this.position = position;
    }

    /** True for platform taxonomy, which only BACKOFFICE may write. */
    public boolean isPlatformOwned() {
        return storeId == null;
    }

    public boolean isOwnedByStore(UUID storeId) {
        return this.storeId != null && this.storeId.equals(storeId);
    }

    public UUID getId() {
        return id;
    }

    public String getName() {
        return name;
    }

    public UUID getParentId() {
        return parentId;
    }

    public UUID getStoreId() {
        return storeId;
    }

    public short getPosition() {
        return position;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public Instant getUpdatedAt() {
        return updatedAt;
    }

    public String getImageRef() {
        return imageRef;
    }

    public void setImageRef(String imageRef) {
        this.imageRef = imageRef;
    }

    public Store.Vertical getVertical() {
        return vertical;
    }

    public void setVertical(Store.Vertical vertical) {
        this.vertical = vertical;
    }
}
