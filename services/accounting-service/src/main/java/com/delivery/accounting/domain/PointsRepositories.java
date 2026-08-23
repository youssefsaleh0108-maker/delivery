package com.delivery.accounting.domain;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import com.delivery.accounting.domain.PointsEntry.OwnerKind;

/**
 * The two points repositories, in one file because neither is big enough to find on its own.
 */
public final class PointsRepositories {

    private PointsRepositories() {
    }

    public interface PointsEntryRepository extends JpaRepository<PointsEntry, UUID> {

        /**
         * The balance: the sum of every movement.
         *
         * <p>{@code COALESCE} so an owner who has never earned anything reads 0 rather than null.
         * Every caller would otherwise need the same null check, and one of them would forget.
         */
        @Query("""
                SELECT COALESCE(SUM(p.points), 0) FROM PointsEntry p
                 WHERE p.ownerKind = :kind AND p.ownerRef = :ref
                """)
        long balanceOf(@Param("kind") OwnerKind kind, @Param("ref") String ref);

        List<PointsEntry> findByOwnerKindAndOwnerRefOrderByCreatedAtDesc(
                OwnerKind kind, String ref, Pageable pageable);

        /**
         * What each of a carrier's riders earned, so the carrier can pay them.
         *
         * <p>Only {@code ORDER_EARNED} rows: a redemption is the carrier's, not any rider's, and
         * including it would show a rider's total falling because the company took money out.
         */
        @Query("""
                SELECT p.earnedByRiderRef, SUM(p.points) FROM PointsEntry p
                 WHERE p.ownerKind = :kind AND p.ownerRef = :ref
                   AND p.reason = com.delivery.accounting.domain.PointsEntry$Reason.ORDER_EARNED
                   AND p.earnedByRiderRef IS NOT NULL
                 GROUP BY p.earnedByRiderRef
                 ORDER BY SUM(p.points) DESC
                """)
        List<Object[]> earnedPerRider(@Param("kind") OwnerKind kind, @Param("ref") String ref);
    }

    public interface PointsRedemptionRepository extends JpaRepository<PointsRedemption, UUID> {

        List<PointsRedemption> findByOwnerKindAndOwnerRefOrderByRequestedAtDesc(
                OwnerKind kind, String ref);

        /**
         * The open request for an owner, if there is one.
         *
         * <p>At most one can exist — a partial unique index enforces it. That is what makes the
         * hold arithmetic safe under concurrency: two requests cannot both pass a balance check,
         * because the second cannot be written at all.
         */
        @Query("""
                SELECT r FROM PointsRedemption r
                 WHERE r.ownerKind = :kind AND r.ownerRef = :ref
                   AND r.status IN (com.delivery.accounting.domain.PointsRedemption$Status.PENDING,
                                    com.delivery.accounting.domain.PointsRedemption$Status.APPROVED)
                """)
        Optional<PointsRedemption> findOpenFor(@Param("kind") OwnerKind kind,
                                               @Param("ref") String ref);

        /** The Backoffice queue: oldest first, because that is who has waited longest. */
        List<PointsRedemption> findByStatusInOrderByRequestedAtAsc(
                List<PointsRedemption.Status> statuses);
    }
}
