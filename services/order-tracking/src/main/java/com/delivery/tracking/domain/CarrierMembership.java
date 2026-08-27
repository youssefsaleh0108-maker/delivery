package com.delivery.tracking.domain;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * Who works for which delivery company, as far as this service can tell.
 *
 * <p>Exists so "may this caller see that rider's location?" is a local row lookup rather than a
 * synchronous call to Order Manager — the same argument that produced {@link OrderParticipants} in
 * V10, applied to a read the carrier console polls continuously.
 *
 * <p>{@link Source} is on the row because the two ways this service learns a membership are not
 * equally trustworthy, and pretending otherwise would quietly grant access on a guess. See the
 * enum.
 */
@Entity
@Table(name = "carrier_membership")
public class CarrierMembership {

    public enum Kind {
        /** Carries deliveries. Can be pinged for and appears on the roster. */
        RIDER,
        /** Dispatchers and office staff: may read their fleet's roster, never appear on it. */
        STAFF
    }

    public enum Source {
        /**
         * Inferred from an order that named both a rider and a delivery provider.
         *
         * <p>All this service can derive on its own, and weak in two specific ways: it only learns
         * about a rider once they have already carried something, and it never learns that someone
         * has left. Good enough to grant a fleet sight of a rider who is demonstrably carrying that
         * fleet's work; not good enough to be the long-term answer.
         */
        ORDER_EVENT,

        /**
         * Told to us directly by a {@code carrier.member_*} event.
         *
         * <p>Authoritative, including departures. This event does not exist yet — the contract is
         * requested of Order Manager, which owns delivery-company membership. Until it lands, no
         * row in this table has this source and carrier office staff can see nothing.
         */
        MEMBERSHIP
    }

    @Id
    @Column(name = "user_id", nullable = false, updatable = false, length = 64)
    private String userId;

    @Column(name = "carrier_id", nullable = false)
    private UUID carrierId;

    @Enumerated(EnumType.STRING)
    @Column(name = "member_kind", nullable = false, length = 16)
    private Kind memberKind;

    @Enumerated(EnumType.STRING)
    @Column(name = "source", nullable = false, length = 16)
    private Source source;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    protected CarrierMembership() {
        // for JPA
    }

    public CarrierMembership(String userId, UUID carrierId, Kind memberKind, Source source) {
        this.userId = userId;
        this.carrierId = carrierId;
        this.memberKind = memberKind;
        this.source = source;
        this.updatedAt = Instant.now();
    }

    /**
     * Applies a newly learned membership, refusing to let a guess overwrite a fact.
     *
     * <p>Without the source check, one stale order event replayed off the bus could demote an
     * authoritative membership row back to an inference — and, once the real event exists, undo a
     * departure that had already been processed. Access would then outlive employment, which is the
     * one failure mode this table must not have.
     *
     * @return true if the row changed
     */
    public boolean apply(UUID carrierId, Kind kind, Source source) {
        if (this.source == Source.MEMBERSHIP && source == Source.ORDER_EVENT) {
            return false;
        }
        if (carrierId.equals(this.carrierId) && kind == this.memberKind && source == this.source) {
            return false;
        }
        this.carrierId = carrierId;
        this.memberKind = kind;
        this.source = source;
        this.updatedAt = Instant.now();
        return true;
    }

    public String getUserId() {
        return userId;
    }

    public UUID getCarrierId() {
        return carrierId;
    }

    public Kind getMemberKind() {
        return memberKind;
    }

    public Source getSource() {
        return source;
    }

    public Instant getUpdatedAt() {
        return updatedAt;
    }
}
