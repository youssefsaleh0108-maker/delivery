package com.delivery.product.domain.staff;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

/** See {@link StaffMemberRepository} for why this is a top-level interface. */
public interface StaffShiftRepository extends JpaRepository<StaffShift, UUID> {

    Optional<StaffShift> findByMemberIdAndClockedOutAtIsNull(UUID memberId);

    List<StaffShift> findByStoreIdAndClockedOutAtIsNull(UUID storeId);
}
