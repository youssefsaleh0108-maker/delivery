package com.delivery.tracking.domain;

import java.util.List;
import java.util.Set;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface OrderParticipantsRepository extends JpaRepository<OrderParticipants, UUID> {

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

    /** Every order of one checkout, whoever placed it — the back office's read. */
    List<OrderParticipants> findByCheckoutId(UUID checkoutId);

    /**
     * Every order of one checkout that this customer placed — the customer's read.
     *
     * <p>Scoped in the query rather than filtered afterwards, so "not yours" and "no such checkout"
     * are the same empty answer by construction and the endpoint cannot tell them apart.
     */
    List<OrderParticipants> findByCheckoutIdAndCustomerId(UUID checkoutId, String customerId);

    /**
     * Whether this rider is carrying a live order that is not part of this checkout.
     *
     * <p>A yes/no and nothing more: the customer is told their rider has other deliveries, so that
     * a longer wait is not a mystery, and never whose, where, or how many. Orders placed alone
     * have no checkout, hence the explicit null test — {@code <>} alone is never true against null.
     */
    @Query("""
            SELECT COUNT(o) > 0 FROM OrderParticipants o
             WHERE o.riderId = :riderId
               AND o.status IN :statuses
               AND (o.checkoutId IS NULL OR o.checkoutId <> :checkoutId)
            """)
    boolean riderHasOrdersOutside(@Param("riderId") String riderId,
                                  @Param("checkoutId") UUID checkoutId,
                                  @Param("statuses") Set<String> statuses);

    /** {@link #riderHasOrdersOutside} with the live statuses already applied. */
    default boolean riderHasOtherLiveOrders(String riderId, UUID checkoutId) {
        return riderHasOrdersOutside(riderId, checkoutId, OrderParticipants.trackableStatuses());
    }
}
