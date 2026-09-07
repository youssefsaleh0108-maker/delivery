package com.delivery.product.service;

import java.util.EnumSet;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

import com.delivery.product.domain.staff.Permission;
import com.delivery.product.domain.staff.StaffMember;

/**
 * What one caller may do at one store.
 *
 * <p>The single shape every staff-aware check goes through, so a controller never branches on role.
 * There are exactly three cases: the owner (everything, and never a {@code staff_members} row), a
 * member (whatever resolved for them), and no access at all.
 */
public final class StoreAccess {

    private final UUID storeId;
    private final String merchantId;
    private final String userRef;
    private final StaffMember member;
    private final Set<Permission> permissions;
    private final boolean owner;

    private StoreAccess(UUID storeId, String merchantId, String userRef, StaffMember member,
                        Set<Permission> permissions, boolean owner) {
        this.storeId = storeId;
        this.merchantId = merchantId;
        this.userRef = userRef;
        this.member = member;
        this.permissions = permissions;
        this.owner = owner;
    }

    public static StoreAccess owner(UUID storeId, String merchantId) {
        return new StoreAccess(storeId, merchantId, merchantId, null, Permission.all(), true);
    }

    public static StoreAccess member(UUID storeId, String merchantId, StaffMember member,
                                     Set<Permission> permissions) {
        return new StoreAccess(storeId, merchantId, member.getUserRef(), member,
                EnumSet.copyOf(permissions.isEmpty() ? EnumSet.noneOf(Permission.class)
                        : EnumSet.copyOf(permissions)),
                false);
    }

    public static StoreAccess none() {
        return new StoreAccess(null, null, null, null, EnumSet.noneOf(Permission.class), false);
    }

    public boolean holds(Permission permission) {
        return permissions.contains(permission);
    }

    /**
     * Assert a permission, or refuse with the permission named.
     *
     * <p>Naming it matters: "you cannot do that" sends a cashier to their manager with nothing to
     * act on, while "you need POS_REFUNDS_VOIDS" tells the manager exactly which toggle to flip.
     */
    public void require(Permission permission) {
        if (!holds(permission)) {
            throw new StoreAccessDeniedException(permission);
        }
    }

    public boolean isOwner() {
        return owner;
    }

    public boolean isAnything() {
        return owner || member != null;
    }

    public Optional<StaffMember> member() {
        return Optional.ofNullable(member);
    }

    public UUID storeId() {
        return storeId;
    }

    public String merchantId() {
        return merchantId;
    }

    public String userRef() {
        return userRef;
    }

    public Set<Permission> permissions() {
        return Set.copyOf(permissions);
    }

    /** Refused for want of a specific permission. Mapped to 403 with the permission in the body. */
    public static class StoreAccessDeniedException extends RuntimeException {

        private final transient Permission permission;

        public StoreAccessDeniedException(Permission permission) {
            super("This action needs the " + permission.name() + " permission");
            this.permission = permission;
        }

        public Permission getPermission() {
            return permission;
        }
    }
}
