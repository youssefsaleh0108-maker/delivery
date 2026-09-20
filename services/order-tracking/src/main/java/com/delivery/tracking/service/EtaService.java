package com.delivery.tracking.service;

import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.tracking.domain.OrderParticipants;
import com.delivery.tracking.domain.OrderParticipantsRepository;
import com.delivery.tracking.route.GeoPoint;
import com.delivery.tracking.route.RouteEstimate;
import com.delivery.tracking.route.RouteProvider;
import com.delivery.tracking.route.RouteProviderRegistry;
import com.delivery.tracking.service.TrackingService.Position;
import com.delivery.tracking.service.TrackingService.TrackingNotFoundException;

/**
 * How far the rider still has to go, and roughly when they will arrive.
 *
 * <p>The whole design of this class is about refusing to answer. An ETA is the single most trusted
 * number on a delivery screen — customers plan around it and complain against it — and every input
 * it depends on can legitimately be missing: the rider may not have pinged yet, their phone may
 * have gone quiet, the order may carry no coordinates because the publisher does not send them yet,
 * and the routing provider may be unreachable. In every one of those cases this returns an
 * unavailable result carrying the reason, and never a number.
 *
 * <p>There is no fallback chain. If the configured provider cannot answer a request, the answer is
 * "unavailable", not a straight line computed quietly in its place: a routed ETA and a
 * great-circle-over-an-assumed-speed ETA differ by tens of minutes in a city, and a screen that
 * switched between them mid-delivery would show a jump nobody could explain. The one place a
 * substitution happens is at startup, when a provider is selected but unconfigured, and that is
 * logged loudly by {@code RouteProviderRegistry} and visible in {@link EtaResult#provider()} on
 * every single response.
 *
 * <p>The lines a map draws do fall back to straight segments ({@code RoutePaths}), and the
 * difference is what each one can say about itself: a straight path carries no road geometry, so
 * it is drawn dashed and labelled approximate. A number cannot say that — it would just be a
 * different number.
 */
@Service
public class EtaService {

    private final TrackingService tracking;
    private final OrderParticipantsRepository participants;
    private final RouteProviderRegistry providers;
    private final Duration maxFixAge;

    public EtaService(TrackingService tracking,
                      OrderParticipantsRepository participants,
                      RouteProviderRegistry providers,
                      // Older than this and the rider could be anywhere. Generous compared with the
                      // few seconds between pings, because a customer would rather see a slightly
                      // aged ETA than have it blink out every time a rider goes under a bridge.
                      @Value("${delivery.tracking.eta.max-fix-age:5m}") Duration maxFixAge) {
        this.tracking = tracking;
        this.participants = participants;
        this.providers = providers;
        this.maxFixAge = maxFixAge;
    }

    /**
     * The remaining journey for an order.
     *
     * <p>Authorisation is the same as for the live position — customer, merchant or assigned rider,
     * or backoffice — and is applied here as well as inside {@link TrackingService}, so the reasons
     * below cannot become an oracle: a stranger gets "not found" before learning whether an order
     * has a fix, a destination or a rider at all.
     *
     * <p>What the estimate is measured from follows {@link TrackingService#sightingFor}: while the
     * rider is on another customer's delivery, or at another customer's door, there is no estimate
     * at all ({@link Reason#RIDER_ON_ANOTHER_DELIVERY}) — a distance from there points at that
     * stop. A rider still far from the shop, or a shop's order already collected, gets an estimate
     * without the position it was measured from.
     */
    @Transactional(readOnly = true)
    public EtaResult estimateFor(UUID orderId, String userId, boolean isBackoffice) {
        OrderParticipants order = participants.findById(orderId)
                .orElseThrow(() -> new TrackingNotFoundException(orderId));

        if (!isBackoffice && !order.isVisibleTo(userId)) {
            throw new TrackingNotFoundException(orderId);
        }

        Instant now = Instant.now();
        String provider = providers.active().name();

        if (order.isComplete()) {
            return EtaResult.unavailable(orderId, Reason.ORDER_COMPLETE, provider, null, now);
        }

        // When this order's rider also holds siblings of it from the same checkout, the rider's
        // latest fix is the latest across all of them, and the journey runs through the siblings'
        // shops still ahead (see RunPlan) — the same answer the checkout map gives. Only for a
        // caller the whole run is: for anyone else the order is estimated as if it were alone.
        List<OrderParticipants> riderOrders = seesTheRun(order, userId, isBackoffice)
                ? riderOrdersOf(order)
                : List.of(order);
        List<RiderSighting> sightings = new ArrayList<>();
        for (OrderParticipants each : riderOrders) {
            sightings.add(tracking.sightingFor(each, userId, isBackoffice));
        }
        return estimate(order, riderOrders, RunSighting.of(sightings), now);
    }

    /**
     * Whether this caller's estimate may run through the rider's other orders of the checkout: the
     * customer, whose orders they all are, the rider carrying them, and the back office.
     *
     * <p>Never a shop. The other orders are the customer's other shops, and an estimate that goes
     * through them tells a merchant that their customer is buying elsewhere, roughly where that
     * shop is — it is the difference between two estimates — and that it is still to be collected.
     * A shop's own order is estimated as if it were the only one: straight to the door once
     * collected, never "still picking up" because somebody else's goods are not aboard yet.
     */
    private static boolean seesTheRun(OrderParticipants order, String userId,
                                      boolean isBackoffice) {
        return isBackoffice
                || order.getCustomerId().equals(userId)
                || (order.getRiderId() != null && order.getRiderId().equals(userId));
    }

    /**
     * The estimate for one order, from everything it depends on: the rider's other live orders of
     * the same checkout (just the order itself when it has none) and what the gate lets this caller
     * know of the rider across them.
     *
     * <p>For the checkout map, which computes every order of a checkout at once and must give each
     * the number this endpoint would. Authorisation is the caller's job: the sighting must be the
     * gate's answer for the same caller.
     *
     * @param riderOrders the rider's live orders of this checkout, this one included
     * @param sighting    {@link TrackingService#sightingFor} for this caller across
     *                    {@code riderOrders}, folded
     */
    /**
     * Every order of one rider's run, estimated together.
     *
     * <p>A run is one journey: the same rider, the same stops ahead, the same door, so it is
     * measured once and each order is handed the same answer under its own id. Measuring it per
     * order meant a three-shop checkout asking the routing provider for the same legs three times
     * over, on every refresh, of every watcher.
     *
     * <p>An order whose door is not the rest of the run's is measured on its own. A checkout is
     * one basket to one address by construction, but this projection is fed by messages, and the
     * one thing that must not happen is an order quietly carrying another order's estimate.
     *
     * @return one estimate per order, in the order given
     */
    Map<UUID, EtaResult> estimateRun(List<OrderParticipants> riderOrders, RunSighting sighting,
                                     Instant now) {
        Map<Optional<GeoPoint>, EtaResult> byDoor = new HashMap<>();
        Map<UUID, EtaResult> estimates = new LinkedHashMap<>();
        for (OrderParticipants order : riderOrders) {
            EtaResult shared = byDoor.computeIfAbsent(order.dropoff(),
                    door -> estimate(order, riderOrders, sighting, now));
            estimates.put(order.getOrderId(), shared.forOrder(order.getOrderId()));
        }
        return estimates;
    }

    EtaResult estimate(OrderParticipants order, List<OrderParticipants> riderOrders,
                       RunSighting sighting, Instant now) {
        if (!order.isComplete() && sighting.elsewhere()) {
            // Not even the fix's time: nothing about where the rider is now.
            return EtaResult.unavailable(order.getOrderId(), Reason.RIDER_ON_ANOTHER_DELIVERY,
                    providers.active().name(), null, now);
        }
        return estimate(order, riderOrders, sighting.measuredFrom(), now);
    }

    /**
     * The estimate from a fix already judged: the gate's basis for this caller, or the latest of
     * them across the run.
     *
     * @param fix the fix to measure from, empty if none
     */
    private EtaResult estimate(OrderParticipants order, List<OrderParticipants> riderOrders,
                               Optional<Position> fix, Instant now) {
        UUID orderId = order.getOrderId();
        String provider = providers.active().name();

        if (order.isComplete()) {
            return EtaResult.unavailable(orderId, Reason.ORDER_COMPLETE, provider, null, now);
        }

        if (fix.isEmpty()) {
            // The rule this endpoint exists to keep. With no fix there is no distance, and a
            // distance guessed from the pickup point would be a number the screen would render as
            // a promise. Absent is honest.
            return EtaResult.unavailable(orderId, Reason.NO_FIX, provider, null, now);
        }

        Position position = fix.get();
        if (position.recordedAt().isBefore(now.minus(maxFixAge))) {
            // Same rule, one step subtler: a fix from twenty minutes ago is not a fix, it is a
            // memory, and an ETA measured from it would be confidently wrong rather than absent.
            return EtaResult.unavailable(orderId, Reason.STALE_FIX, provider,
                    position.recordedAt(), now);
        }

        Optional<GeoPoint> dropoff = order.dropoff();
        if (dropoff.isEmpty()) {
            // No coordinates on the order. Today this is the normal case: the order events this
            // service projects carry a postal address and no lat/lng, so there is nothing to
            // measure against until that contract lands. See V12 and the service report.
            return EtaResult.unavailable(orderId, Reason.NO_DESTINATION, provider,
                    position.recordedAt(), now);
        }

        // Alone, the stops ahead are this order's shop until it is collected, then nothing. In a
        // run they are every sibling's shop not yet collected from, in the order RunPlan expects.
        boolean inRiderOrders = riderOrders.stream()
                .anyMatch(o -> o.getOrderId().equals(orderId));
        RunPlan plan = RunPlan.of(inRiderOrders ? riderOrders : List.of(order), fix);
        // Still collecting — this order's goods or, in a run, a sibling's — or on the way to the
        // door with everything aboard.
        Leg leg = plan.ahead().isEmpty() ? Leg.TO_DROPOFF : Leg.TO_PICKUP;

        if (!plan.aheadPinned()) {
            // A shop still to be visited has no pin. The journey through it cannot be measured,
            // and measuring around it would promise a time for a route the rider will not take.
            return EtaResult.unavailable(orderId, Reason.NO_DESTINATION, provider,
                    position.recordedAt(), now);
        }

        List<GeoPoint> stops = new ArrayList<>();
        stops.add(new GeoPoint(position.lat(), position.lng()));
        stops.addAll(plan.aheadPins());
        stops.add(dropoff.get());
        Optional<RouteEstimate> estimate = alongStops(stops);

        if (estimate.isEmpty()) {
            // The provider could not answer. Reported rather than papered over.
            return EtaResult.unavailable(orderId, Reason.PROVIDER_UNAVAILABLE, provider,
                    position.recordedAt(), now);
        }

        RouteEstimate route = estimate.get();

        // Anchored to when the fix was taken, not to now: the distance was measured from where the
        // rider was at that moment, and the seconds since have been spent covering some of it.
        // Clamped forward to now because an arrival instant in the past is not a prediction — a
        // screen would render it as "arrived" for a rider who is visibly still on the road.
        Instant arrival = position.recordedAt().plus(route.travelTime());
        if (arrival.isBefore(now)) {
            arrival = now;
        }

        return new EtaResult(orderId, true, null, leg,
                route.distanceMetres(), route.travelTime().toSeconds(), arrival,
                route.provider(), position.recordedAt(), now);
    }

    /**
     * Rider → every shop still ahead → customer, leg by leg, summed.
     *
     * <p>Every stop, rather than measuring straight to the customer. A rider four streets the wrong
     * side of the restaurant is not four streets from the customer, and the shortcut would produce
     * an ETA that improves as the rider drives away from the food; in a run, a rider with a second
     * shop to visit is further from the door than the crow flies by that whole detour.
     *
     * <p>Every leg comes from the same provider, taken once, so a summed estimate can never be
     * half-routed and half-guessed. One leg the provider cannot answer leaves no estimate at all.
     */
    private Optional<RouteEstimate> alongStops(List<GeoPoint> stops) {
        RouteProvider provider = providers.active();
        Optional<RouteEstimate> total = provider.estimate(stops.get(0), stops.get(1));
        for (int i = 2; i < stops.size() && total.isPresent(); i++) {
            RouteEstimate soFar = total.get();
            total = provider.estimate(stops.get(i - 1), stops.get(i)).map(soFar::plus);
        }
        return total;
    }

    /**
     * This order and the other live orders of its checkout that its rider holds — the run it is
     * part of. Just the order itself when it was placed alone or has no rider yet.
     *
     * <p>Only siblings of the same customer, which a checkout's orders always are: a checkout id is
     * a server-generated link, but this projection is fed by messages, and a mislabelled one must
     * not route one customer's rider through another customer's shop.
     */
    private List<OrderParticipants> riderOrdersOf(OrderParticipants order) {
        List<OrderParticipants> orders = new ArrayList<>();
        orders.add(order);
        if (order.getCheckoutId() == null || order.getRiderId() == null) {
            return orders;
        }
        for (OrderParticipants sibling : participants.findByCheckoutId(order.getCheckoutId())) {
            if (!sibling.getOrderId().equals(order.getOrderId())
                    && order.getRiderId().equals(sibling.getRiderId())
                    && order.getCustomerId().equals(sibling.getCustomerId())
                    && !sibling.isComplete()) {
                orders.add(sibling);
            }
        }
        return orders;
    }

    /** Which part of the journey the estimate covers. */
    public enum Leg {
        /**
         * The rider still has a shop to collect from before the customer — this order's, or in a
         * run a sibling's — so the estimate spans rider → shop(s) → customer.
         */
        TO_PICKUP,
        /** The rider has everything aboard; the estimate is the run to the customer. */
        TO_DROPOFF
    }

    /** Why there is no number. Present exactly when {@link EtaResult#available()} is false. */
    public enum Reason {
        /** No fix of the rider's is on this order: none yet, or their latest went on no order. */
        NO_FIX,
        /** The last ping is older than the acceptable fix age. The rider could be anywhere. */
        STALE_FIX,
        /** The order carries no coordinates to measure against. */
        NO_DESTINATION,
        /** The routing provider could not answer. Transient for a real provider. */
        PROVIDER_UNAVAILABLE,
        /** Delivered or cancelled. Nothing is on its way. */
        ORDER_COMPLETE,
        /**
         * The rider is on another customer's delivery right now, or still at that customer's door.
         * No distance and no time are given, since either would point at the other stop.
         */
        RIDER_ON_ANOTHER_DELIVERY
    }

    /**
     * @param available        false whenever anything is missing; the numeric fields are then null
     * @param reason           why not, or null when available
     * @param provider         who computed it — or who would have. Always present, so a caller can
     *                         tell a routed answer from a straight-line one without asking
     * @param fixRecordedAt    when the position the estimate was measured from was taken
     */
    public record EtaResult(
            UUID orderId,
            boolean available,
            Reason reason,
            Leg leg,
            Double remainingMetres,
            Long remainingSeconds,
            Instant estimatedArrival,
            String provider,
            Instant fixRecordedAt,
            Instant computedAt) {

        static EtaResult unavailable(UUID orderId, Reason reason, String provider,
                                     Instant fixRecordedAt, Instant now) {
            return new EtaResult(orderId, false, reason, null, null, null, null,
                    provider, fixRecordedAt, now);
        }

        /** The same estimate, under another order's id: a run's journey is one journey. */
        EtaResult forOrder(UUID id) {
            return id.equals(orderId) ? this
                    : new EtaResult(id, available, reason, leg, remainingMetres, remainingSeconds,
                            estimatedArrival, provider, fixRecordedAt, computedAt);
        }

        /**
         * The same estimate with no distance: for a reader who may not see the position it was
         * measured from, to whom metres from the rider are a ring around the shop that says where
         * the rider is. The time stays, as the gate allows.
         */
        EtaResult withoutDistance() {
            return remainingMetres == null ? this
                    : new EtaResult(orderId, available, reason, leg, null, remainingSeconds,
                            estimatedArrival, provider, fixRecordedAt, computedAt);
        }
    }
}
