package com.delivery.onboarding.domain;

import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface PartnerStatusChangeRepository extends JpaRepository<PartnerStatusChange, UUID> {

    /** The current standing: the newest change. Empty means never touched, which means active. */
    Optional<PartnerStatusChange> findFirstByApplicationIdOrderByCreatedAtDesc(UUID applicationId);

    /**
     * The current standing of many applications at once — each one's newest change, in one query.
     *
     * <p>For a company's applications listing, which the carrier's Riders HR directory used to
     * follow with one standing request per rider. An application nobody ever suspended has no row,
     * which means active. Two changes stamped at the same instant both come back; the caller
     * resolves that tie towards suspended, the side that cannot hide a suspension.
     */
    @Query("""
            SELECT c FROM PartnerStatusChange c
             WHERE c.applicationId IN :applicationIds
               AND c.createdAt = (SELECT MAX(n.createdAt) FROM PartnerStatusChange n
                                   WHERE n.applicationId = c.applicationId)
            """)
    List<PartnerStatusChange> findCurrentForApplications(
            @Param("applicationIds") Collection<UUID> applicationIds);

    /** The full history, newest first. Empty for a partner nobody ever suspended. */
    List<PartnerStatusChange> findByApplicationIdOrderByCreatedAtDesc(UUID applicationId);
}
