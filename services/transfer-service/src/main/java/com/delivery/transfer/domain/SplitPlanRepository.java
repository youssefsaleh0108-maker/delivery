package com.delivery.transfer.domain;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/** Split plans, looked up the three ways the API needs them: mine, addressed to me, by order. */
public interface SplitPlanRepository extends JpaRepository<SplitPlan, UUID> {

    List<SplitPlan> findByHostRefOrderByCreatedAtDesc(String hostRef, Pageable pageable);

    Optional<SplitPlan> findByOrderId(UUID orderId);

    /**
     * The invitations addressed to this username that still want an answer. Joined through the
     * shares because that is where the addressee lives; COLLECTING only, because an expired or
     * cancelled plan has no request left to answer.
     */
    @Query("""
            SELECT DISTINCT p FROM SplitPlan p JOIN p.shares s
            WHERE s.payeeUsername = :username
              AND s.status = com.delivery.transfer.domain.SplitShare$Status.PENDING
              AND p.status = com.delivery.transfer.domain.SplitPlan$Status.COLLECTING
            ORDER BY p.createdAt DESC
            """)
    List<SplitPlan> findOpenRequestsFor(@Param("username") String username);
}
