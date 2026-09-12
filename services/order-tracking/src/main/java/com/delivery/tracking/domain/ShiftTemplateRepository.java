package com.delivery.tracking.domain;

import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

public interface ShiftTemplateRepository extends JpaRepository<ShiftTemplate, UUID> {

    /** A fleet's shifts, oldest first, archived included — the caller filters for what it shows. */
    List<ShiftTemplate> findByCarrierIdOrderByCreatedAt(UUID carrierId);

    /**
     * One shift, only if it belongs to this fleet.
     *
     * <p>Scoped in the query rather than checked afterwards, so a competitor's shift id reads as
     * "no such shift" by construction and cannot be told apart from a typo.
     */
    Optional<ShiftTemplate> findByIdAndCarrierId(UUID id, UUID carrierId);

    List<ShiftTemplate> findByIdIn(Collection<UUID> ids);
}
