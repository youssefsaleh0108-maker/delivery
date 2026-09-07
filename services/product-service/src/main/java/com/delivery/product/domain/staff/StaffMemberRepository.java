package com.delivery.product.domain.staff;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

/**
 * Top-level on purpose: Spring Data only detects repository interfaces declared at package level.
 * Nesting these inside a holder class compiled and passed every unit test, then failed context
 * startup on the first real deploy with "no qualifying bean" — nothing here may be nested again.
 */
public interface StaffMemberRepository extends JpaRepository<StaffMember, UUID> {

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
