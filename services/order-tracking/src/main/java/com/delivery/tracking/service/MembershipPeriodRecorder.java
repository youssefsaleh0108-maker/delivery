package com.delivery.tracking.service;

import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.tracking.domain.CarrierMembership;
import com.delivery.tracking.domain.CarrierMembershipPeriod;
import com.delivery.tracking.domain.CarrierMembershipPeriodRepository;
import com.delivery.tracking.domain.CarrierMembershipRepository;
import com.delivery.tracking.domain.RiderPresence;
import com.delivery.tracking.domain.RiderPresenceRepository;

/**
 * Keeps {@code carrier_membership_periods} from Order Manager's {@code carrier.member_joined} and
 * {@code carrier.member_left} events — the record every carrier history read is clipped to — and
 * keeps the roster's linkage in step with it.
 *
 * <p><strong>Idempotent, and tolerant of order.</strong> Delivery is at-least-once, and a replay or
 * a requeue can put an older event behind a newer one. So:
 *
 * <ul>
 *   <li>a join or a leave already on record at the same instant changes nothing;</li>
 *   <li>a join older than anything already recorded for the rider is ignored — the record has moved
 *       past it;</li>
 *   <li>a join to a new fleet while another is open ends the old period at the join: a move is a
 *       leave and a join at one instant, and the leave may arrive second;</li>
 *   <li>a leave ends whichever of that fleet's periods covers its instant — shortening one a later
 *       join had already closed — and a leave with no period to end is kept as a zero-length one, so
 *       the join it overtook cannot open a period that never closes.</li>
 * </ul>
 *
 * <p><strong>The linkage.</strong> A join points the roster and the position check at the new fleet
 * with the event's authority ({@link CarrierMembership.Source#MEMBERSHIP}, which no order event can
 * overwrite). A leave clears it — {@code rider_presence.carrier_id} and the rider's
 * {@code carrier_membership} row — because no order event ever says a rider left, and keeping it
 * kept the rider on the former company's roster. Once the record holds anything for a rider, an
 * order may only confirm the fleet the record has them on ({@link #mayInferFromOrder}).
 */
@Service
public class MembershipPeriodRecorder {

    private static final Logger log = LoggerFactory.getLogger(MembershipPeriodRecorder.class);

    private final CarrierMembershipPeriodRepository periods;
    private final RiderPresenceRepository presence;
    private final CarrierMembershipRepository memberships;

    public MembershipPeriodRecorder(CarrierMembershipPeriodRepository periods,
                                    RiderPresenceRepository presence,
                                    CarrierMembershipRepository memberships) {
        this.periods = periods;
        this.presence = presence;
        this.memberships = memberships;
    }

    /** A rider joined {@code carrierId}'s fleet at {@code at}. */
    @Transactional
    public void joined(String riderId, UUID carrierId, Instant at) {
        if (periods.existsByRiderIdAndCarrierIdAndJoinedAt(riderId, carrierId, at)) {
            return;
        }
        List<CarrierMembershipPeriod> history = periods.findByRiderIdOrderByJoinedAtAsc(riderId);
        if (history.stream().anyMatch(period -> period.lastBoundary().isAfter(at))) {
            log.warn("Ignoring rider {} joining {} at {}: the record already holds a later change",
                    riderId, carrierId, at);
            return;
        }

        Optional<CarrierMembershipPeriod> open =
                history.stream().filter(CarrierMembershipPeriod::isOpen).findFirst();
        if (open.isPresent()) {
            if (open.get().getCarrierId().equals(carrierId)) {
                return;
            }
            open.get().endAt(at);
            // Flushed before the insert: one open period per rider is a unique index, and Hibernate
            // would otherwise write the new row ahead of the update that closes the old one.
            periods.saveAndFlush(open.get());
        }
        periods.save(CarrierMembershipPeriod.open(riderId, carrierId, at));
        link(riderId, carrierId);
    }

    /** A rider left {@code carrierId}'s fleet at {@code at}. */
    @Transactional
    public void left(String riderId, UUID carrierId, Instant at) {
        if (periods.existsByRiderIdAndCarrierIdAndLeftAt(riderId, carrierId, at)) {
            return;
        }
        Optional<CarrierMembershipPeriod> covering = periods.findByRiderIdOrderByJoinedAtAsc(riderId)
                .stream()
                .filter(period -> period.getCarrierId().equals(carrierId) && period.covers(at))
                .findFirst();
        if (covering.isPresent()) {
            covering.get().endAt(at);
            periods.save(covering.get());
        } else {
            periods.save(CarrierMembershipPeriod.leftWithoutJoin(riderId, carrierId, at));
        }

        boolean backOnThisFleet = periods.findByRiderIdAndLeftAtIsNull(riderId)
                .filter(period -> period.getCarrierId().equals(carrierId))
                .isPresent();
        if (!backOnThisFleet) {
            unlink(riderId, carrierId);
        }
    }

    /**
     * Whether an order naming this rider and this fleet may still be taken as evidence the rider
     * rides for it.
     *
     * <p>Yes while the record says nothing about the rider — the order is then the best evidence
     * there is, as it always was. Once Order Manager has said where the rider works, only that
     * fleet: a late or replayed order for a company the rider has left must not re-attach them.
     */
    @Transactional(readOnly = true)
    public boolean mayInferFromOrder(String riderId, UUID carrierId) {
        List<CarrierMembershipPeriod> history = periods.findByRiderIdOrderByJoinedAtAsc(riderId);
        return history.isEmpty()
                || history.stream().anyMatch(p -> p.isOpen() && p.getCarrierId().equals(carrierId));
    }

    /**
     * The roster and the position check follow the fleet the rider has joined. A rider this service
     * has never heard from gets an off-duty presence row, so the company's roster shows "hired, not
     * working" from the day it hires them — as an order event's inference does.
     */
    private void link(String riderId, UUID carrierId) {
        Instant now = Instant.now();
        memberships.findById(riderId).ifPresentOrElse(
                existing -> {
                    // A staff row is somebody's office account, never a rider's: left alone.
                    if (existing.getMemberKind() == CarrierMembership.Kind.RIDER) {
                        existing.apply(carrierId, CarrierMembership.Kind.RIDER,
                                CarrierMembership.Source.MEMBERSHIP);
                    }
                },
                () -> memberships.save(new CarrierMembership(riderId, carrierId,
                        CarrierMembership.Kind.RIDER, CarrierMembership.Source.MEMBERSHIP)));

        RiderPresence row = presence.findById(riderId)
                .orElseGet(() -> RiderPresence.firstSeen(riderId, now));
        row.attachCarrier(carrierId, now);
        presence.save(row);
    }

    /** Off the fleet named, and only that one: a rider already linked elsewhere keeps that link. */
    private void unlink(String riderId, UUID carrierId) {
        Instant now = Instant.now();
        presence.findById(riderId)
                .filter(row -> carrierId.equals(row.getCarrierId()))
                .ifPresent(row -> {
                    row.detachCarrier(carrierId, now);
                    presence.save(row);
                });
        memberships.findById(riderId)
                .filter(row -> row.getMemberKind() == CarrierMembership.Kind.RIDER
                        && carrierId.equals(row.getCarrierId()))
                .ifPresent(memberships::delete);
    }
}
