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

    @Column(name = "created_at", nullable = false, insertable = false, updatable = false)
    private Instant createdAt;

    protected Category() {
        // for JPA
    }

    public Category(String name, UUID parentId) {
        this.id = UUID.randomUUID();
        this.name = name;
        this.parentId = parentId;
    }

    public void rename(String name) {
        this.name = name;
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

    public Instant getCreatedAt() {
        return createdAt;
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
