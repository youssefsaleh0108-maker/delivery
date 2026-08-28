package com.delivery.onboarding.domain;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

public interface PartnerStatusChangeRepository extends JpaRepository<PartnerStatusChange, UUID> {

    /** The current standing: the newest change. Empty means never touched, which means active. */
    Optional<PartnerStatusChange> findFirstByApplicationIdOrderByCreatedAtDesc(UUID applicationId);

    /** The full history, newest first. Empty for a partner nobody ever suspended. */
    List<PartnerStatusChange> findByApplicationIdOrderByCreatedAtDesc(UUID applicationId);
}
