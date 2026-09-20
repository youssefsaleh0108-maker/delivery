package com.delivery.tracking.service;

import java.util.List;
import java.util.Optional;

import com.delivery.tracking.service.RiderSighting.State;
import com.delivery.tracking.service.TrackingService.Position;

/**
 * What one caller may know of where one rider is, across the orders of that rider they are asking
 * about together — the answers {@link TrackingService#sightingFor} gives for each order, folded
 * into one.
 *
 * <p>A rider holding several of a customer's orders is one person in one place, so a customer's
 * map shows one marker, and the single-order estimate measures the run from one fix. Both must
 * still show nothing the gate would withhold from the same caller about any one of those orders:
 * <ul>
 *   <li>If the gate says {@link State#ON_ANOTHER_DELIVERY} for any of them, the whole run says so,
 *       with no position and no basis — the rider is at or on the way to somebody else's door.</li>
 *   <li>Otherwise the position shown is the latest the gate showed for any of them (the same fix,
 *       for a customer; each order's own, for the back office), and the basis is the latest it
 *       would measure from.</li>
 * </ul>
 *
 * <p>Internal, like {@link RiderSighting#measuredFrom()}: {@link #measuredFrom()} must never be put
 * in a response.
 *
 * @param state        {@link State#VISIBLE} exactly when {@code shown} is present; otherwise why not
 * @param shown        the point the caller may see, if any
 * @param measuredFrom the fix an estimate may be measured from, if any. Never for a response
 */
record RunSighting(State state, Optional<Position> shown, Optional<Position> measuredFrom) {

    RunSighting {
        if ((state == State.VISIBLE) != shown.isPresent()) {
            throw new IllegalArgumentException("A position is shown exactly when it is visible");
        }
    }

    /** Nothing is known of this rider: no order asked about, or none with a fix. */
    static final RunSighting NOTHING =
            new RunSighting(State.NO_FIX, Optional.empty(), Optional.empty());

    /**
     * Folds the gate's answers for one rider's orders, each asked for the same caller.
     *
     * <p>When nothing is shown, the state is the most telling of the answers: heading to a shop
     * (an estimate without a position), then after pickup (the shop's view), then no fix, then
     * closed.
     */
    static RunSighting of(List<RiderSighting> sightings) {
        Optional<Position> shown = Optional.empty();
        Optional<Position> basis = Optional.empty();
        State hidden = null;
        for (RiderSighting sighting : sightings) {
            if (sighting.state() == State.ON_ANOTHER_DELIVERY) {
                return new RunSighting(State.ON_ANOTHER_DELIVERY, Optional.empty(),
                        Optional.empty());
            }
            shown = RunPlan.later(shown, sighting.shown());
            basis = RunPlan.later(basis, sighting.measuredFrom());
            if (sighting.state() != State.VISIBLE && rank(sighting.state()) < rank(hidden)) {
                hidden = sighting.state();
            }
        }
        if (shown.isPresent()) {
            return new RunSighting(State.VISIBLE, shown, basis);
        }
        return new RunSighting(hidden == null ? State.NO_FIX : hidden, Optional.empty(), basis);
    }

    /** Lower is more telling, for a rider nobody may be shown. */
    private static int rank(State state) {
        if (state == null) {
            return Integer.MAX_VALUE;
        }
        return switch (state) {
            case HEADING_TO_SHOP -> 0;
            case AFTER_PICKUP -> 1;
            case NO_FIX -> 2;
            case CLOSED -> 3;
            case VISIBLE, ON_ANOTHER_DELIVERY -> Integer.MAX_VALUE;
        };
    }

    /** True while the rider is on another customer's delivery or at their door. */
    boolean elsewhere() {
        return state == State.ON_ANOTHER_DELIVERY;
    }
}
