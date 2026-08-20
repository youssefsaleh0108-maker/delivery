package com.delivery.tracking.domain;

import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

public interface OrderParticipantsRepository extends JpaRepository<OrderParticipants, UUID> {
}
