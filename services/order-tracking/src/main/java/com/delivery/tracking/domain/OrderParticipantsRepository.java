package com.delivery.tracking.domain;

import java.util.Set;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface OrderParticipantsRepository extends JpaRepository<OrderParticipants, UUID> {

    /** Whether this rider holds any order in one of these statuses. */
    boolean existsByRiderIdAndStatusIn(String riderId, Set<String> statuses);

    /**
     * Whether this rider is carrying a live delivery right now — the second way, besides declared
     * duty, that a rider earns the right to report an off-order position.
     *
     * <p>"Live" is {@link OrderParticipants#isTrackable()}'s definition, bound rather than
     * restated. A rider is only ever put on an order when it is READY (a claim, or an errand
     * created already claimed), so assigned-and-not-finished and trackable are the same set, and
     * using the one definition keeps "who may report" and "who may be watched" from drifting.
     */
    default boolean riderHasLiveOrder(String riderId) {
        return existsByRiderIdAndStatusIn(riderId, OrderParticipants.trackableStatuses());
    }

    /**
     * Whether this customer has a live delivery in this rider's hands right now.
     *
     * <p>The narrowest reason a customer may read a rider-scoped location. It is deliberately not
     * "has ever ordered from them": once the food is handed over the customer's interest ends, and
     * a rider whose whereabouts stay visible to every past customer is being followed home.
     *
     * <p>Bound parameters, not string building — {@code riderId} arrives in the request path and is
     * untrusted like any other user-supplied value. The status list is bound too rather than
     * inlined, so it cannot drift from {@link OrderParticipants#isTrackable()} and leave the two
     * definitions of "live" disagreeing about who may look.
     */
    @Query("""
            SELECT COUNT(o) > 0 FROM OrderParticipants o
             WHERE o.riderId = :riderId
               AND o.customerId = :customerId
               AND o.status IN :statuses
            """)
    boolean customerHasOrderWith(@Param("customerId") String customerId,
                                 @Param("riderId") String riderId,
                                 @Param("statuses") Set<String> statuses);

    /** {@link #customerHasOrderWith} with the live statuses already applied. */
    default boolean customerHasLiveOrderWith(String customerId, String riderId) {
        return customerHasOrderWith(customerId, riderId, OrderParticipants.trackableStatuses());
    }
}
