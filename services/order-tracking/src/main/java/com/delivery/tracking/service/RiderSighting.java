package com.delivery.tracking.service;

import java.util.Optional;

import com.delivery.tracking.service.TrackingService.Position;

/**
 * What one caller may know of where an order's rider is, right now — the answer
 * {@link TrackingService#sightingFor} gives.
 *
 * <p>Two positions, kept apart on purpose. {@link #position()} is what the caller may be shown: a
 * point on their map. {@link #etaBasis()} is what an arrival estimate may be measured from, which
 * is sometimes allowed when the point itself is not (a rider still far from the shop: the
 * customer gets a time but not the rider's whereabouts). The basis must never be put in a response.
 *
 * @param state    what the caller is told
 * @param position the point the caller may be shown; present exactly when {@code state} is
 *                 {@link State#VISIBLE}
 * @param etaBasis the fix an estimate may be measured from, or null when no estimate may be given
 */
public record RiderSighting(State state, Position position, Position etaBasis) {

    public RiderSighting {
        if ((state == State.VISIBLE) != (position != null)) {
            throw new IllegalArgumentException("A position is shown exactly when it is visible");
        }
    }

    /** The rider is shown here, and an estimate may be measured from the same point. */
    static RiderSighting visible(Position position) {
        return new RiderSighting(State.VISIBLE, position, position);
    }

    /** Not shown, but an estimate may still be measured from {@code basis}. */
    static RiderSighting timedOnly(State state, Position basis) {
        return new RiderSighting(state, null, basis);
    }

    /** Neither shown nor measured from. */
    static RiderSighting nothing(State state) {
        return new RiderSighting(state, null, null);
    }

    /** The point the caller may be shown, if any. */
    public Optional<Position> shown() {
        return Optional.ofNullable(position);
    }

    /** The fix an estimate may be measured from, if any. Never for a response body. */
    public Optional<Position> measuredFrom() {
        return Optional.ofNullable(etaBasis);
    }

    /**
     * What a caller is told about the rider. Everything but {@link #VISIBLE} carries no
     * coordinates; which of the others also allow an estimate is said on each.
     */
    public enum State {
        /** The rider is shown: a customer or shop whose delivery the rider is on, the rider, or
         *  the back office. */
        VISIBLE,
        /** The order is READY and the rider is still more than 2 km from the shop — claims often
         *  happen at home. An estimate is given; the rider's position is not. */
        HEADING_TO_SHOP,
        /** The rider's latest fix is on another customer's delivery, or lies within 300 m of the
         *  door of another customer's order the rider holds or finished in the last 30 minutes.
         *  Nothing is given: no position, no distance, no estimate, nothing that points at the
         *  other stop. */
        ON_ANOTHER_DELIVERY,
        /** The shop, once its order is collected: the shop sees the rider only until pickup. An
         *  estimate is given; the rider's position is not. */
        AFTER_PICKUP,
        /** Nothing to show: no rider yet, or no fix of theirs is on this delivery — none yet, or
         *  the latest one went on no order at all. */
        NO_FIX,
        /** Delivered or cancelled. The rider is shown to nobody but the back office and the rider
         *  any more. */
        CLOSED
    }
}
