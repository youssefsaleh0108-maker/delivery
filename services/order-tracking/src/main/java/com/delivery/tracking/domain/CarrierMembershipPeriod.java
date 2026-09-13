package com.delivery.tracking.domain;

import java.time.Instant;
import java.util.Optional;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * One spell of a rider on one delivery company's fleet, as Order Manager announced it: from
 * {@code joinedAt}, until {@code leftAt} (null while it lasts).
 *
 * <p>Written only from {@code carrier.member_joined} / {@code carrier.member_left} events — see
 * {@code MembershipPeriodRecorder} — and read to clip a company's view of a rider's history to the
 * time the rider was actually its rider. Mapped column for column as V16 declares it, because the
 * schema is validated at start-up.
 */
@Entity
@Table(name = "carrier_membership_periods")
public class CarrierMembershipPeriod {

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "rider_id", nullable = false, updatable = false, length = 64)
    private String riderId;

    @Column(name = "carrier_id", nullable = false, updatable = false)
    private UUID carrierId;

    @Column(name = "joined_at", nullable = false, updatable = false)
    private Instant joinedAt;

    @Column(name = "left_at")
    private Instant leftAt;

    protected CarrierMembershipPeriod() {
        // for JPA
    }

    private CarrierMembershipPeriod(String riderId, UUID carrierId, Instant joinedAt, Instant leftAt) {
        this.id = UUID.randomUUID();
        this.riderId = riderId;
        this.carrierId = carrierId;
        this.joinedAt = joinedAt;
        this.leftAt = leftAt;
    }

    /** A rider joining a fleet at {@code at}, for as long as that lasts. */
    public static CarrierMembershipPeriod open(String riderId, UUID carrierId, Instant at) {
        return new CarrierMembershipPeriod(riderId, carrierId, at, null);
    }

    /**
     * A leave with no join on record, kept as a zero-length period.
     *
     * <p>Contributes no window, and exists so a join that turns up afterwards, dated before this
     * leave, is recognised as already over rather than opening a period that would never close.
     */
    public static CarrierMembershipPeriod leftWithoutJoin(String riderId, UUID carrierId, Instant at) {
        return new CarrierMembershipPeriod(riderId, carrierId, at, at);
    }

    /** Ends the period at {@code at} — never before it began. Also shortens one ended later. */
    public void endAt(Instant at) {
        this.leftAt = at.isBefore(joinedAt) ? joinedAt : at;
    }

    public boolean isOpen() {
        return leftAt == null;
    }

    /** Whether the rider was on this fleet at that instant. */
    public boolean covers(Instant at) {
        return !at.isBefore(joinedAt) && (leftAt == null || at.isBefore(leftAt));
    }

    /** The latest instant this period says anything about. */
    public Instant lastBoundary() {
        return leftAt == null ? joinedAt : leftAt;
    }

    /** This period's part of {@code [from, to)}, if it has one. An open period runs to {@code to}. */
    public Optional<MembershipWindow> within(Instant from, Instant to) {
        Instant start = joinedAt.isAfter(from) ? joinedAt : from;
        Instant end = leftAt == null || leftAt.isAfter(to) ? to : leftAt;
        return start.isBefore(end) ? Optional.of(new MembershipWindow(start, end)) : Optional.empty();
    }

    public UUID getId() {
        return id;
    }

    public String getRiderId() {
        return riderId;
    }

    public UUID getCarrierId() {
        return carrierId;
    }

    public Instant getJoinedAt() {
        return joinedAt;
    }

    public Instant getLeftAt() {
        return leftAt;
    }
}
