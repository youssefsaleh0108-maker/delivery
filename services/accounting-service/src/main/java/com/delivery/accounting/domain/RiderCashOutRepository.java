package com.delivery.accounting.domain;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;

/** Rider cash-out requests. */
public interface RiderCashOutRepository extends JpaRepository<RiderCashOut, UUID> {

    /**
     * The rider's open request, if they have one.
     *
     * <p>Read for DISPLAY — the Earnings screen shows "£20.00 on its way" — and deliberately not
     * relied on to prevent a second request. That guarantee belongs to the unique partial index on
     * {@code (rider_ref) WHERE status = 'REQUESTED'}: a check here followed by an insert is a
     * check-then-act, and two concurrent requests would both pass it.
     */
    Optional<RiderCashOut> findFirstByRiderRefAndStatus(String riderRef, RiderCashOut.Status status);

    List<RiderCashOut> findByRiderRefOrderByRequestedAtDesc(String riderRef, Pageable pageable);

    /** The operator's queue: everything still waiting on somebody, oldest first. */
    List<RiderCashOut> findByStatusOrderByRequestedAtAsc(RiderCashOut.Status status,
                                                         Pageable pageable);
}
