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
         * Read from Order Manager's directory, with the caller's own token, at the moment they
         * asked.
         *
         * <p>How office staff get a row at all. They carry nothing, so no order event will ever
         * mention them, and before this source existed a delivery company could not see its own
         * fleet by any route.
         *
         * <p>Stronger than an inference — Order Manager owns the membership and answered for this
         * exact person — but weaker than an event, because a read cannot tell us about a departure
         * that happens afterwards. That is why a row from here is re-validated on a window rather
         * than trusted forever, and why the resolver deletes it when the directory stops placing
         * that caller in a company. See {@code CarrierScopeResolver}.
         */
        DIRECTORY,

        /**
         * Told to us directly by a {@code carrier.member_*} event.
         *
         * <p>Authoritative, including departures the moment they happen. This event does not exist
         * yet — the contract is requested of Order Manager, which owns delivery-company
         * membership. {@link #DIRECTORY} is what serves the console until it lands; when it does,
         * it outranks both of the others and needs no re-validation window.
         */
        MEMBERSHIP;

        /**
         * How much this source is worth against another, so a weaker one cannot overwrite a
         * stronger.
         *
         * <p>Without an ordering, one stale order event replayed off the bus could demote a fact
         * to a guess, and — once the real event exists — undo a departure that had already been
         * processed. Access would then outlive employment, which is the one failure mode this
         * table must not have.
         */
        int rank() {
            return ordinal();
        }
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
     * Applies a newly learned membership, refusing to let a weaker source overwrite a stronger one.
     *
     * <p>See {@link Source#rank()} for why the ordering exists.
     *
     * @return true if the row changed
     */
    public boolean apply(UUID carrierId, Kind kind, Source source) {
        if (source.rank() < this.source.rank()) {
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

    /**
     * Marks the row as confirmed again, without changing what it says.
     *
     * <p>Separate from {@link #apply} because {@code apply} deliberately reports "nothing changed"
     * for a re-statement of the same facts, and leaves {@code updatedAt} alone so it keeps meaning
     * "when this last changed". A {@link Source#DIRECTORY} row needs the other reading — when it
     * was last <em>checked</em> — because that is what its re-validation window is measured from,
     * and without this a row would go stale on a schedule no confirmation could reset.
     */
    public void confirmed() {
        this.updatedAt = Instant.now();
    }

    /** Whether this row was last written before {@code cutoff} and is due to be checked again. */
    public boolean staleAsOf(Instant cutoff) {
        return this.updatedAt.isBefore(cutoff);
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
