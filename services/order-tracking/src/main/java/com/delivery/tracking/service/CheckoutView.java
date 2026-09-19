package com.delivery.tracking.service;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

import com.delivery.tracking.route.GeoPoint;
import com.delivery.tracking.route.PathGeometry;
import com.delivery.tracking.service.EtaService.EtaResult;

/**
 * One multi-shop checkout on one map: the shops, the door, each order's progress, the riders on
 * the way, and the lines between them — everything a customer's checkout map draws, and nothing it
 * would have to guess.
 *
 * <p>Every coordinate here is one the platform holds: a shop pin or a door pin snapshotted on the
 * order, or a rider's recorded fix. A point it does not hold is null, and a line through a missing
 * point is not in {@link #paths()} at all.
 *
 * <p>Every rider position here is one {@link TrackingService#sightingFor} shows the caller for one
 * of that rider's orders — nothing the single-order endpoints would withhold. Where it withholds
 * one, there is no marker, no line starting from it, and no distance measured from it.
 *
 * @param provider   who computed every path and estimate in this answer — {@code HAVERSINE_DEV}
 *                   is straight lines at an assumed speed
 * @param geometry   how every path in this answer is drawn: ROAD (solid, as returned) or
 *                   STRAIGHT (dashed straight segments, labelled approximate). Decided here so a
 *                   routing engine switched on later changes every map with no app release
 * @param door       the customer's pin, or null when the orders carry none (or disagree)
 * @param orders     one row per order of the checkout, in a stable order
 * @param riders     one entry per rider holding a live order of the checkout — nothing about the
 *                   person beyond where their phone last was, when the caller may see it
 * @param paths      the expected routes: PLANNED (nobody on the way yet) and RIDER_LEG (from a
 *                   fresh fix the caller may see, through the stops still ahead)
 * @param computedAt when this answer was computed; answers are reused for a few seconds
 */
public record CheckoutView(
        UUID checkoutId,
        String provider,
        PathGeometry geometry,
        Pin door,
        List<OrderView> orders,
        List<RiderView> riders,
        List<PathView> paths,
        Instant computedAt) {

    /** A WGS-84 point on the wire. */
    public record Pin(double lat, double lng) {

        static Pin of(GeoPoint point) {
            return new Pin(point.lat(), point.lng());
        }
    }

    /**
     * One order of the checkout.
     *
     * @param shop          the shop's pin, or null when it has none — the row then says why
     * @param riderAssigned whether a rider has claimed it; nothing else about them is said
     * @param stop          its place in its rider's run, or null when it is not in a run (see
     *                      {@link RunPlan}): a collected stop's number is fact, an uncollected one's
     *                      is {@code expected}
     * @param expected      true when {@code stop} is the platform's expectation, not a fact
     * @param eta           what {@code /orders/{id}/eta} answers for this order — in a run, every
     *                      order carries the run's door estimate — except that no distance is
     *                      given while the rider's position is withheld from the caller: metres
     *                      from a rider nobody is shown are a ring around a shop that says where
     *                      they are
     */
    public record OrderView(
            UUID orderId,
            String storeName,
            String status,
            Pin shop,
            boolean riderAssigned,
            Integer stop,
            boolean expected,
            Instant pickedUpAt,
            Instant completedAt,
            EtaResult eta) {
    }

    /**
     * One rider with at least one live order of the checkout.
     *
     * @param orderIds           the rider's live orders of this checkout, in the order they are
     *                           taken to be visited
     * @param run                true when they hold two or more of them
     * @param sighting           what the caller may know of where they are, as the single-order
     *                           {@code GET .../rider} says it: {@code VISIBLE} with a position, or
     *                           {@code HEADING_TO_SHOP} (still far from the shop: a time, no
     *                           position), {@code ON_ANOTHER_DELIVERY} (nothing) or {@code NO_FIX}
     * @param position           the latest fix the caller may see across those orders; null when
     *                           there is none or the rider is not {@code VISIBLE}
     * @param hasOtherDeliveries whether they are also carrying orders that are not this checkout's.
     *                           A yes/no and nothing more — never whose, where or how many
     */
    public record RiderView(
            List<UUID> orderIds,
            boolean run,
            RiderSighting.State sighting,
            RiderFix position,
            boolean hasOtherDeliveries) {
    }

    /**
     * Where a rider's phone last reported them.
     *
     * @param stale true once the fix is older than the platform will measure an ETA from: the
     *              marker then says "last seen", and no estimate is given from it
     */
    public record RiderFix(double lat, double lng, Instant recordedAt, boolean stale) {
    }

    /** What a path shows. */
    public enum PathKind {
        /** Shop → door for an order nobody is on the way for yet. Drawn lighter than a live leg. */
        PLANNED,
        /** From a rider's fresh fix through the stops still ahead, ending at the door. */
        RIDER_LEG
    }

    /**
     * One expected route.
     *
     * @param orderIds  the orders it serves — several for a run
     * @param points    the stops it passes through, in order, the first being the rider's fix on a
     *                  RIDER_LEG. What a STRAIGHT path is drawn through
     * @param polyline6 the road geometry at 1e6 precision, or null for a STRAIGHT path
     * @param metres    its length, from the same provider as everything else in the answer
     */
    public record PathView(
            List<UUID> orderIds,
            PathKind kind,
            List<Pin> points,
            String polyline6,
            double metres,
            String provider) {
    }
}
