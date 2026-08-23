package com.delivery.accounting.domain;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import com.delivery.accounting.domain.PointsEntry.OwnerKind;

/**
 * Redemption requests.
 *
 * <p>Top-level for the same reason as {@link PointsEntryRepository}: Spring Data finds repositories
 * by classpath scanning, and one nested inside another class is not found.
 */
public interface PointsRedemptionRepository extends JpaRepository<PointsRedemption, UUID> {

    List<PointsRedemption> findByOwnerKindAndOwnerRefOrderByRequestedAtDesc(
            OwnerKind kind, String ref);

    /**
     * The open request for an owner, if there is one.
     *
     * <p>At most one can exist — a partial unique index enforces it. That is what makes the hold
     * arithmetic safe under concurrency: two requests cannot both pass a balance check, because the
     * second cannot be written at all.
     */
    @Query("""
            SELECT r FROM PointsRedemption r
             WHERE r.ownerKind = :kind AND r.ownerRef = :ref
               AND r.status IN (com.delivery.accounting.domain.PointsRedemption$Status.PENDING,
                                com.delivery.accounting.domain.PointsRedemption$Status.APPROVED)
            """)
    Optional<PointsRedemption> findOpenFor(@Param("kind") OwnerKind kind, @Param("ref") String ref);

    /** The Backoffice queue: oldest first, because that is who has waited longest. */
    List<PointsRedemption> findByStatusInOrderByRequestedAtAsc(
            List<PointsRedemption.Status> statuses);
}
