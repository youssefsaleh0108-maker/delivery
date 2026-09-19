package com.delivery.tracking.domain;

import java.time.Instant;
import java.util.List;
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
     * This rider's orders for customers other than {@code customerId} that end at a known door and
     * are either still in the rider's hands or finished at or after {@code finishedSince}.
     *
     * <p>These are the doors near which the rider is not shown to {@code customerId}'s side of an
     * order: a rider standing at another customer's door is handing over that customer's delivery,
     * and a dot or a trail point there says where that customer lives. See
     * {@code TrackingService#sightingFor}.
     */
    @Query("""
            SELECT o FROM OrderParticipants o
             WHERE o.riderId = :riderId
               AND o.customerId <> :customerId
               AND o.dropoffLat IS NOT NULL
               AND o.dropoffLng IS NOT NULL
               AND (o.status IN :live OR o.completedAt >= :finishedSince)
            """)
    List<OrderParticipants> findOtherCustomersDoors(@Param("riderId") String riderId,
                                                    @Param("customerId") String customerId,
                                                    @Param("live") Set<String> live,
                                                    @Param("finishedSince") Instant finishedSince);

    /** {@link #findOtherCustomersDoors} with the live statuses already applied. */
    default List<OrderParticipants> otherCustomersDoors(String riderId, String customerId,
                                                        Instant finishedSince) {
        return findOtherCustomersDoors(riderId, customerId, OrderParticipants.trackableStatuses(),
                finishedSince);
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
