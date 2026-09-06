package com.delivery.product.domain.staff;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

/**
 * The staff aggregate's repositories, kept together because they are only ever used as a set: no
 * caller wants members without also resolving the store's permission band.
 */
public final class StaffRepositories {

    private StaffRepositories() {
    }

    public interface Members extends JpaRepository<StaffMember, UUID> {

        /** The staff screen's list: everyone still at this shop. */
        List<StaffMember> findByStoreIdAndRemovedAtIsNullOrderByAddedAtAsc(UUID storeId);

        /**
         * Who is this caller, at whatever shop they work in?
         *
         * <p>One row at most: {@code uq_member_active_user} enforces one active shop per person.
         */
        Optional<StaffMember> findByUserRefAndRemovedAtIsNull(String userRef);

        Optional<StaffMember> findByIdAndStoreIdAndRemovedAtIsNull(UUID id, UUID storeId);

        boolean existsByStoreIdAndEmailIgnoreCaseAndRemovedAtIsNull(UUID storeId, String email);
    }

    public interface RolePermissions extends JpaRepository<StoreRolePermission, StoreRolePermission.Key> {

        List<StoreRolePermission> findByStoreId(UUID storeId);

        List<StoreRolePermission> findByStoreIdAndRole(UUID storeId, StaffRole role);
    }

    public interface Invites extends JpaRepository<StaffInvite, String> {

        List<StaffInvite> findByStoreIdOrderByCreatedAtDesc(UUID storeId);
    }

    public interface Shifts extends JpaRepository<StaffShift, UUID> {

        Optional<StaffShift> findByMemberIdAndClockedOutAtIsNull(UUID memberId);

        List<StaffShift> findByStoreIdAndClockedOutAtIsNull(UUID storeId);
    }
}
