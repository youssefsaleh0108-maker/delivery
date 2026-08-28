package com.delivery.onboarding.domain;

import java.util.List;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

public interface PartnerEditEntryRepository extends JpaRepository<PartnerEditEntry, UUID> {

    /** One partner's edit history, newest first. Empty when nobody ever edited the record. */
    List<PartnerEditEntry> findByApplicationIdOrderByCreatedAtDesc(UUID applicationId);
}
