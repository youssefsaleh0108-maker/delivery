package com.delivery.product.domain.staff;

import java.util.List;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

/** See {@link StaffMemberRepository} for why this is a top-level interface. */
public interface StoreRolePermissionRepository
        extends JpaRepository<StoreRolePermission, StoreRolePermission.Key> {

    List<StoreRolePermission> findByStoreId(UUID storeId);

    List<StoreRolePermission> findByStoreIdAndRole(UUID storeId, StaffRole role);
}
