package com.delivery.tracking.service;

import java.time.Instant;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

import com.delivery.tracking.domain.OrderParticipants;
import com.delivery.tracking.route.GeoPoint;
import com.delivery.tracking.route.HaversineRouteProvider;
import com.delivery.tracking.service.TrackingService.Position;

/**
 * The order in which one rider visits the shops of one checkout, as far as the platform can back
 * it up.
 *
 * <p>Nothing plans this upstream. Dispatch offers each shop's order on its own and a rider claims
 * orders one at a time, so a rider holding two of a customer's orders is a coincidence the map has
 * to describe, not a plan it can read. Two kinds of fact go into the description:
 * <ul>
 *   <li><b>Collected</b> stops are real and are ordered by when the rider actually collected them
 *       ({@link OrderParticipants#getPickedUpAt()}).</li>
 *   <li><b>Stops still ahead</b> are a guess, and are marked as one: nearest-next from where the
 *       rider was last known to be — their latest fix, or the shop they last collected from if
 *       that is more recent — by straight-line distance. Only a stop with a shop pin can be
 *       placed; one without is left unnumbered at the end rather than put anywhere.</li>
 * </ul>
 *
 * <p>Stop numbers exist only for a <em>run</em>: two or more live orders of the checkout with the
 * same rider. One rider per order needs no numbers, and numbering it would suggest a sequence
 * nobody chose.
 *
 * <p>Built for the ETA and the checkout map alike, so the single-order panel and the map always
 * send the rider the same way and agree on the number.
 */
public final class RunPlan {

    /** Collected before ahead; collected by collection time; the rest in expected order. */
    private final List<OrderParticipants> visitOrder;
    private final List<OrderParticipants> ahead;
    private final Map<UUID, Integer> stopNumbers;
    private final Set<UUID> expected;
    private final boolean aheadPinned;

    private RunPlan(List<OrderParticipants> visitOrder, List<OrderParticipants> ahead,
                    Map<UUID, Integer> stopNumbers, Set<UUID> expected, boolean aheadPinned) {
        this.visitOrder = visitOrder;
        this.ahead = ahead;
        this.stopNumbers = stopNumbers;
        this.expected = expected;
        this.aheadPinned = aheadPinned;
    }

    /**
     * Plans one rider's live orders of one checkout.
     *
     * @param riderOrders the rider's live (non-terminal) orders of the checkout — one or more
     * @param latestFix   the rider's latest fix across those orders, of any age; empty if none
     */
    public static RunPlan of(List<OrderParticipants> riderOrders, Optional<Position> latestFix) {
        List<OrderParticipants> collected = new ArrayList<>();
        List<OrderParticipants> notYet = new ArrayList<>();
        for (OrderParticipants order : riderOrders) {
            (order.isCarrying() ? collected : notYet).add(order);
        }
        // By the real collection time; an order collected before this projection learned the time
        // (V17 backfills nothing) goes after the timed ones, by id, and is never numbered.
        collected.sort(Comparator
                .comparing(OrderParticipants::getPickedUpAt,
                        Comparator.nullsLast(Comparator.naturalOrder()))
                .thenComparing(OrderParticipants::getOrderId));

        Optional<GeoPoint> anchor = lastKnownPlace(collected, latestFix);

        List<OrderParticipants> pinned = new ArrayList<>();
        List<OrderParticipants> pinless = new ArrayList<>();
        for (OrderParticipants order : notYet) {
            (order.pickup().isPresent() ? pinned : pinless).add(order);
        }
        pinned.sort(Comparator.comparing(OrderParticipants::getOrderId));
        pinless.sort(Comparator.comparing(OrderParticipants::getOrderId));
        List<OrderParticipants> ahead = new ArrayList<>(anchor
                .map(from -> nearestNext(from, pinned))
                .orElse(pinned));
        ahead.addAll(pinless);

        Map<UUID, Integer> numbers = new LinkedHashMap<>();
        Set<UUID> expected = new HashSet<>();
        if (riderOrders.size() >= 2) {
            int next = 1;
            for (OrderParticipants order : collected) {
                if (order.getPickedUpAt() != null) {
                    numbers.put(order.getOrderId(), next++);
                }
            }
            // With nowhere to measure from there is no expectation to back, so no numbers.
            if (anchor.isPresent()) {
                for (OrderParticipants order : ahead) {
                    if (order.pickup().isPresent()) {
                        numbers.put(order.getOrderId(), next++);
                        expected.add(order.getOrderId());
                    }
                }
            }
        }

        List<OrderParticipants> visitOrder = new ArrayList<>(collected);
        visitOrder.addAll(ahead);
        return new RunPlan(Collections.unmodifiableList(visitOrder),
                Collections.unmodifiableList(ahead), Collections.unmodifiableMap(numbers),
                Collections.unmodifiableSet(expected), pinless.isEmpty());
    }

    /**
     * Where the rider was most recently known to be: the latest fix, or the shop they last
     * collected from when that collection is more recent than the fix.
     */
    private static Optional<GeoPoint> lastKnownPlace(List<OrderParticipants> collected,
                                                     Optional<Position> fix) {
        OrderParticipants lastCollected = null;
        for (OrderParticipants order : collected) {
            if (order.getPickedUpAt() != null && order.pickup().isPresent()) {
                lastCollected = order;
            }
        }
        if (fix.isPresent()) {
            Instant fixAt = fix.get().recordedAt();
            if (lastCollected == null || fixAt == null
                    || !fixAt.isBefore(lastCollected.getPickedUpAt())) {
                return Optional.of(new GeoPoint(fix.get().lat(), fix.get().lng()));
            }
        }
        return lastCollected == null ? Optional.empty() : lastCollected.pickup();
    }

    /** Greedy nearest-next by straight-line distance; ties go to the lower order id. */
    private static List<OrderParticipants> nearestNext(GeoPoint from,
                                                       List<OrderParticipants> pinned) {
        List<OrderParticipants> left = new ArrayList<>(pinned);
        List<OrderParticipants> ordered = new ArrayList<>();
        GeoPoint here = from;
        while (!left.isEmpty()) {
            OrderParticipants nearest = null;
            double best = Double.MAX_VALUE;
            for (OrderParticipants candidate : left) {
                double metres = HaversineRouteProvider.distanceMetres(here,
                        candidate.pickup().orElseThrow());
                if (metres < best) {
                    best = metres;
                    nearest = candidate;
                }
            }
            ordered.add(nearest);
            left.remove(nearest);
            here = nearest.pickup().orElseThrow();
        }
        return ordered;
    }

    /**
     * The more recent of two fixes. A rider's position is one fact however many of a checkout's
     * orders they hold; each order only keeps the fixes pinged against it.
     */
    public static Optional<Position> later(Optional<Position> a, Optional<Position> b) {
        if (a.isEmpty() || a.get().recordedAt() == null) {
            return b.isPresent() ? b : a;
        }
        if (b.isEmpty() || b.get().recordedAt() == null) {
            return a;
        }
        return b.get().recordedAt().isAfter(a.get().recordedAt()) ? b : a;
    }

    /** Every order of the plan in the order the rider is taken to visit them. */
    public List<OrderParticipants> visitOrder() {
        return visitOrder;
    }

    /** The stops still to collect from, in expected order; pinless ones last. */
    public List<OrderParticipants> ahead() {
        return ahead;
    }

    /** The shop pins still to visit, in order. Complete only when {@link #aheadPinned()}. */
    public List<GeoPoint> aheadPins() {
        List<GeoPoint> pins = new ArrayList<>();
        for (OrderParticipants order : ahead) {
            order.pickup().ifPresent(pins::add);
        }
        return pins;
    }

    /** Whether every stop still ahead has a pin — the condition for measuring or drawing it. */
    public boolean aheadPinned() {
        return aheadPinned;
    }

    /** Stop numbers, for a run only: collected stops first, then expected ones. */
    public Map<UUID, Integer> stopNumbers() {
        return stopNumbers;
    }

    /** The numbered stops whose place is a guess rather than a fact. */
    public Set<UUID> expected() {
        return expected;
    }
}
