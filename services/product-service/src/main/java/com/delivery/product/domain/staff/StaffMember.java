package com.delivery.product.domain.staff;

import java.time.Instant;
import java.util.EnumSet;
import java.util.HashMap;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

/**
 * One person who works at one shop.
 *
 * <p>Never the owner — see {@link StaffRole}. A member is removed by stamping {@code removedAt}
 * rather than deleting the row, because shifts and audit entries point at it and a rota that cannot
 * name who worked a till is worthless.
 */
@Entity
@Table(name = "staff_members")
public class StaffMember {

    public enum Status { ACTIVE, INACTIVE }

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "store_id", nullable = false, updatable = false)
    private UUID storeId;

    /** The member's own Keycloak {@code sub}, bound when they redeem their invite. */
    @Column(name = "user_ref", nullable = false, length = 64, updatable = false)
    private String userRef;

    @Enumerated(EnumType.STRING)
    @Column(name = "role", nullable = false, length = 16)
    private StaffRole role;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false, length = 16)
    private Status status = Status.ACTIVE;

    @Column(name = "display_name", nullable = false, length = 120)
    private String displayName;

    @Column(name = "email", length = 200)
    private String email;

    @Column(name = "phone", length = 32)
    private String phone;

    /**
     * Per-person deviations from the store's role band, keyed by {@link Permission} name.
     *
     * <p>An empty map means "exactly what the role grants", which is the common case and costs
     * nothing to store.
     */
    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "permission_overrides", nullable = false, columnDefinition = "jsonb")
    private Map<String, Boolean> permissionOverrides = new HashMap<>();

    @Column(name = "pin_hash", length = 100)
    private String pinHash;

    @Column(name = "last_seen_at")
    private Instant lastSeenAt;

    @Column(name = "added_by", nullable = false, length = 64, updatable = false)
    private String addedBy;

    @Column(name = "added_at", nullable = false, insertable = false, updatable = false)
    private Instant addedAt;

    @Column(name = "updated_at", nullable = false, insertable = false, updatable = false)
    private Instant updatedAt;

    @Column(name = "removed_at")
    private Instant removedAt;

    @Column(name = "removed_by", length = 64)
    private String removedBy;

    /** Bumped on every change and carried on the event, so projections can ignore a stale replay. */
    @Column(name = "version", nullable = false)
    private long version = 1L;

    protected StaffMember() {
        // for JPA
    }

    public StaffMember(UUID storeId, String userRef, StaffRole role, String displayName,
                       String email, String phone, String addedBy) {
        this.id = UUID.randomUUID();
        this.storeId = storeId;
        this.userRef = userRef;
        this.role = role;
        this.displayName = displayName;
        this.email = email;
        this.phone = phone;
        this.addedBy = addedBy;
        this.status = Status.ACTIVE;
    }

    /**
     * The permissions this member actually holds.
     *
     * <p>Resolution order: the platform defaults for the role, overlaid by the store's own band,
     * overlaid by this person's overrides. A member who is inactive or removed holds nothing at
     * all, which is what makes "suspend someone" a single field change.
     */
    public Set<Permission> effectivePermissions(Map<Permission, Boolean> storeBand) {
        if (removedAt != null || status != Status.ACTIVE) {
            return EnumSet.noneOf(Permission.class);
        }
        Set<Permission> resolved = EnumSet.copyOf(Permission.defaultsFor(role));
        if (storeBand != null) {
            storeBand.forEach((permission, granted) -> {
                if (Boolean.TRUE.equals(granted)) {
                    resolved.add(permission);
                } else {
                    resolved.remove(permission);
                }
            });
        }
        permissionOverrides.forEach((name, granted) -> {
            Permission permission = parse(name);
            if (permission == null) {
                return; // a value retired since the row was written; ignore rather than fail a login
            }
            if (Boolean.TRUE.equals(granted)) {
                resolved.add(permission);
            } else {
                resolved.remove(permission);
            }
        });
        return resolved;
    }

    private static Permission parse(String name) {
        try {
            return Permission.valueOf(name);
        } catch (IllegalArgumentException e) {
            return null;
        }
    }

    public void changeRole(StaffRole role) {
        this.role = role;
        this.version++;
    }

    public void setStatus(Status status) {
        this.status = status;
        this.version++;
    }

    public void updateProfile(String displayName, String email, String phone) {
        this.displayName = displayName;
        this.email = email;
        this.phone = phone;
        this.version++;
    }

    public void overridePermission(Permission permission, Boolean granted) {
        if (granted == null) {
            permissionOverrides.remove(permission.name());
        } else {
            permissionOverrides.put(permission.name(), granted);
        }
        this.version++;
    }

    public void remove(String removedBy) {
        this.removedAt = Instant.now();
        this.removedBy = removedBy;
        this.version++;
    }

    public boolean isRemoved() {
        return removedAt != null;
    }

    public void touchLastSeen() {
        this.lastSeenAt = Instant.now();
    }

    public UUID getId() {
        return id;
    }

    public UUID getStoreId() {
        return storeId;
    }

    public String getUserRef() {
        return userRef;
    }

    public StaffRole getRole() {
        return role;
    }

    public Status getStatus() {
        return status;
    }

    public String getDisplayName() {
        return displayName;
    }

    public String getEmail() {
        return email;
    }

    public String getPhone() {
        return phone;
    }

    public Map<String, Boolean> getPermissionOverrides() {
        return Map.copyOf(permissionOverrides);
    }

    public String getPinHash() {
        return pinHash;
    }

    public void setPinHash(String pinHash) {
        this.pinHash = pinHash;
    }

    public Instant getLastSeenAt() {
        return lastSeenAt;
    }

    public Instant getAddedAt() {
        return addedAt;
    }

    public Instant getUpdatedAt() {
        return updatedAt;
    }

    public Instant getRemovedAt() {
        return removedAt;
    }

    public long getVersion() {
        return version;
    }
}
