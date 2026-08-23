package com.delivery.accounting.domain;

import java.util.List;
import java.util.UUID;

import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import com.delivery.accounting.domain.PointsEntry.OwnerKind;

/**
 * Points movements.
 *
 * <p>A TOP-LEVEL interface, not a nested one. Spring Data scans for repository interfaces by
 * classpath scanning, and an interface nested inside a final utility class is not picked up — the
 * service asking for it fails with 'required a bean of type PointsEntryRepository that could not
 * be found', which reads like a missing @EnableJpaRepositories rather than a nesting problem.
 */
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
