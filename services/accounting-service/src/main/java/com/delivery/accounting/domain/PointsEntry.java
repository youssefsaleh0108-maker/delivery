package com.delivery.accounting.domain;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * One movement on somebody's points balance.
 *
 * <p>Signed, and always a row. A balance is {@code SUM(points)} over these — there is no balance
 * column, because a number nobody can explain is worse than a query. "Why is my balance 4,300" has
 * to be answerable, and only the history answers it.
 *
 * @see PointsRedemption
 */
@Entity
@Table(name = "points_ledger")
public class PointsEntry {

    /**
     * Whose balance moves.
     *
     * <p>The distinction between {@link #CARRIER} and {@link #RIDER} is the one that matters. A
     * rider employed by a delivery company earns into the COMPANY's balance — the company redeems
     * and pays its own riders, and {@link #getEarnedByRiderRef()} is what lets it see who earned
     * what. A rider on the platform's own fleet has no company behind them, so they hold their own.
     */
    public enum OwnerKind {
        MERCHANT,
        CARRIER,
        RIDER
    }

    public enum Reason {
        /** A delivered order. */
        ORDER_EARNED,
        /** Moved out of the balance while a redemption request is open, so it cannot be spent twice. */
        REDEMPTION_HELD,
        /** A rejected or cancelled request gives them back. */
        REDEMPTION_RELEASED,
        /** Approved and paid; the hold becomes permanent. */
        REDEMPTION_PAID,
        /** An operator correction, kept separate so it can be counted apart from anything automatic. */
        ADJUSTMENT
    }

    @Id
    private UUID id;

    @Enumerated(EnumType.STRING)
    @Column(name = "owner_kind", nullable = false, length = 16)
    private OwnerKind ownerKind;

    @Column(name = "owner_ref", nullable = false, length = 64)
    private String ownerRef;

    /** The rider whose delivery earned these, when the owner is their company. Null otherwise. */
    @Column(name = "earned_by_rider_ref", length = 64)
    private String earnedByRiderRef;

    /** Null on a redemption, which is not about one order. */
    @Column(name = "order_id")
    private UUID orderId;

    @Column(name = "points", nullable = false)
    private long points;

    @Enumerated(EnumType.STRING)
    @Column(name = "reason", nullable = false, length = 32)
    private Reason reason;

    @Column(name = "redemption_id")
    private UUID redemptionId;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    protected PointsEntry() {
    }

    private PointsEntry(OwnerKind ownerKind, String ownerRef, long points, Reason reason) {
        this.id = UUID.randomUUID();
        this.ownerKind = ownerKind;
        this.ownerRef = ownerRef;
        this.points = points;
        this.reason = reason;
        this.createdAt = Instant.now();
    }

    /**
     * Points earned by delivering or selling an order.
     *
     * <p>{@code earnedByRiderRef} is set only when the owner is a carrier: it is the rider whose
     * work produced them, and the only thing that makes the company's balance attributable.
     */
    public static PointsEntry earned(OwnerKind ownerKind, String ownerRef, UUID orderId,
                                     long points, String earnedByRiderRef) {
        PointsEntry entry = new PointsEntry(ownerKind, ownerRef, points, Reason.ORDER_EARNED);
        entry.orderId = orderId;
        entry.earnedByRiderRef = earnedByRiderRef;
        return entry;
    }

    /**
     * Takes points out of the balance while a request is open.
     *
     * <p>Negative, so the balance falls the moment the request is made rather than when it is paid.
     * A balance that still showed held points would let the same points be requested again the
     * moment the first request was slow, and the platform would owe them twice.
     */
    public static PointsEntry held(OwnerKind ownerKind, String ownerRef, UUID redemptionId,
                                   long points) {
        PointsEntry entry = new PointsEntry(ownerKind, ownerRef, -Math.abs(points),
                Reason.REDEMPTION_HELD);
        entry.redemptionId = redemptionId;
        return entry;
    }

    /** Gives held points back, on a rejection or a cancellation. */
    public static PointsEntry released(OwnerKind ownerKind, String ownerRef, UUID redemptionId,
                                       long points) {
        PointsEntry entry = new PointsEntry(ownerKind, ownerRef, Math.abs(points),
                Reason.REDEMPTION_RELEASED);
        entry.redemptionId = redemptionId;
        return entry;
    }

    /**
     * Records that the hold was paid out.
     *
     * <p>Zero points on purpose. The balance already fell when the hold was written; subtracting
     * again here would charge the requester twice for one redemption. This row exists so the
     * history shows the payment, not to move a balance.
     */
    public static PointsEntry paid(OwnerKind ownerKind, String ownerRef, UUID redemptionId) {
        PointsEntry entry = new PointsEntry(ownerKind, ownerRef, 0L, Reason.REDEMPTION_PAID);
        entry.redemptionId = redemptionId;
        return entry;
    }

    public UUID getId() {
        return id;
    }

    public OwnerKind getOwnerKind() {
        return ownerKind;
    }

    public String getOwnerRef() {
        return ownerRef;
    }

    public String getEarnedByRiderRef() {
        return earnedByRiderRef;
    }

    public UUID getOrderId() {
        return orderId;
    }

    public long getPoints() {
        return points;
    }

    public Reason getReason() {
        return reason;
    }

    public UUID getRedemptionId() {
        return redemptionId;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }
}
