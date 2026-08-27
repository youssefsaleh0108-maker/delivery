package com.delivery.tracking.domain;

import java.util.List;
import java.util.UUID;

import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;

public interface RiderDutyEventRepository extends JpaRepository<RiderDutyEvent, UUID> {

    /** A rider's recent shift boundaries — what a support agent reads when a delivery went cold. */
    List<RiderDutyEvent> findByRiderIdOrderByOccurredAtDesc(String riderId, Pageable pageable);
}
