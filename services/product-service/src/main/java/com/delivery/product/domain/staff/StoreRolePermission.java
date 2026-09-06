package com.delivery.product.domain.staff;

import java.io.Serializable;
import java.time.Instant;
import java.util.Objects;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.IdClass;
import jakarta.persistence.Table;

/**
 * One store's deviation from the platform default for a role.
 *
 * <p>Rows record deviations only: a shop that never opens the permissions panel stores nothing and
 * simply inherits {@link Permission#defaultsFor}. That keeps "what does a cashier get here" a
 * question with one answer rather than a table that must be seeded per store.
 */
@Entity
@Table(name = "store_role_permissions")
@IdClass(StoreRolePermission.Key.class)
public class StoreRolePermission {

    @Id
    @Column(name = "store_id", nullable = false, updatable = false)
    private UUID storeId;

    @Id
    @Enumerated(EnumType.STRING)
    @Column(name = "role", nullable = false, length = 16, updatable = false)
    private StaffRole role;

    @Id
    @Enumerated(EnumType.STRING)
    @Column(name = "permission", nullable = false, length = 32, updatable = false)
    private Permission permission;

    @Column(name = "granted", nullable = false)
    private boolean granted;

    @Column(name = "updated_by", nullable = false, length = 64)
    private String updatedBy;

    @Column(name = "updated_at", nullable = false, insertable = false, updatable = false)
    private Instant updatedAt;

    protected StoreRolePermission() {
        // for JPA
    }

    public StoreRolePermission(UUID storeId, StaffRole role, Permission permission,
                               boolean granted, String updatedBy) {
        this.storeId = storeId;
        this.role = role;
        this.permission = permission;
        this.granted = granted;
        this.updatedBy = updatedBy;
    }

    public void set(boolean granted, String updatedBy) {
        this.granted = granted;
        this.updatedBy = updatedBy;
    }

    public UUID getStoreId() {
        return storeId;
    }

    public StaffRole getRole() {
        return role;
    }

    public Permission getPermission() {
        return permission;
    }

    public boolean isGranted() {
        return granted;
    }

    public Instant getUpdatedAt() {
        return updatedAt;
    }

    /** Composite key: one row per (store, role, permission). */
    public static class Key implements Serializable {

        private UUID storeId;
        private StaffRole role;
        private Permission permission;

        public Key() {
        }

        public Key(UUID storeId, StaffRole role, Permission permission) {
            this.storeId = storeId;
            this.role = role;
            this.permission = permission;
        }

        @Override
        public boolean equals(Object o) {
            if (this == o) {
                return true;
            }
            if (!(o instanceof Key other)) {
                return false;
            }
            return Objects.equals(storeId, other.storeId)
                    && role == other.role
                    && permission == other.permission;
        }

        @Override
        public int hashCode() {
            return Objects.hash(storeId, role, permission);
        }
    }
}
