package com.delivery.product.domain.staff;

import java.util.List;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

/** See {@link StaffMemberRepository} for why this is a top-level interface. */
public interface StaffInviteRepository extends JpaRepository<StaffInvite, String> {

    List<StaffInvite> findByStoreIdOrderByCreatedAtDesc(UUID storeId);
}
