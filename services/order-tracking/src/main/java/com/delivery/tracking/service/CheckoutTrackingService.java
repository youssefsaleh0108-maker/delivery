package com.delivery.tracking.service;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.tracking.domain.OrderParticipants;
import com.delivery.tracking.domain.OrderParticipantsRepository;
import com.delivery.tracking.route.GeoPoint;
import com.delivery.tracking.route.RoutePath;
import com.delivery.tracking.route.RoutePaths;
import com.delivery.tracking.service.CheckoutView.OrderView;
import com.delivery.tracking.service.CheckoutView.PathKind;
import com.delivery.tracking.service.CheckoutView.PathView;
import com.delivery.tracking.service.CheckoutView.Pin;
import com.delivery.tracking.service.CheckoutView.RiderFix;
import com.delivery.tracking.service.CheckoutView.RiderView;
import com.delivery.tracking.service.EtaService.EtaResult;
import com.delivery.tracking.service.TrackingService.Position;

/**
 * A multi-shop checkout as one map, for the customer who placed it.
 *
 * <p>Built entirely from this service's own projection and positions — the checkout's orders, their
 * snapshotted pins, and each rider's recorded fixes — and never from anything guessed. The rules
 * that decide what is drawn:
 * <ul>
 *   <li>Every rider position is read through {@link TrackingService#sightingFor}, the one rule for
 *       who may see a rider, for this caller and each of the rider's orders here. What it withholds
 *       on the single-order endpoints is withheld here: no marker, no line from it, no distance
 *       measured from it, and no stop order worked out from it.</li>
 *   <li>A shop or the door with no pin is not drawn, and no line passes through it.</li>
 *   <li>No rider yet: a PLANNED path shop → door. A rider with a fresh fix the caller may see: a
 *       RIDER_LEG from the fix through the stops still ahead to the door — through every sibling
 *       shop when the rider holds several of the checkout's orders (a run; see {@link RunPlan}).
 *       A rider without one: no line at all, because where the rider is is exactly what is
 *       unknown, or not the caller's to know.</li>
 *   <li>Once an order is delivered or cancelled it has no path and no rider, as tracking has
 *       closed.</li>
 *   <li>Every estimate is the one {@link EtaService} gives the single-order panel — without its
 *       distance while the rider's position is withheld from the caller.</li>
 * </ul>
 *
 * <p><strong>Computed at most once every few seconds per checkout.</strong> The screen polls, the
 * customer may have it open on two devices, and every recomputation is a round of position reads
 * and — with a routing engine — routing requests; Mapbox's are billed and may not be cached. The
 * answer is the same for everyone allowed to see it, so it is shared: the caller is checked on
 * every request, and only then handed the answer computed within the window.
 */
@Service
public class CheckoutTrackingService {

    /** Past this many remembered checkouts, expired answers are swept on the next write. */
    private static final int MEMO_SWEEP_THRESHOLD = 500;

    private final OrderParticipantsRepository participants;
    private final TrackingService tracking;
    private final EtaService eta;
    private final RoutePaths paths;
    private final OtherDeliveriesLatch otherDeliveries;
    private final Duration maxFixAge;
    private final Duration recomputeAfter;
    private final Clock clock;
    private final Map<UUID, Memo> memo = new ConcurrentHashMap<>();

    @Autowired
    public CheckoutTrackingService(OrderParticipantsRepository participants,
                                   TrackingService tracking,
                                   EtaService eta,
                                   RoutePaths paths,
                                   OtherDeliveriesLatch otherDeliveries,
                                   // The ETA's own staleness rule, so the marker's "last seen" and
                                   // the missing estimate always agree.
                                   @Value("${delivery.tracking.eta.max-fix-age:5m}") Duration maxFixAge,
                                   @Value("${delivery.tracking.checkout-map.recompute-after:5s}")
                                   Duration recomputeAfter) {
        this(participants, tracking, eta, paths, otherDeliveries, maxFixAge, recomputeAfter,
                Clock.systemUTC());
    }

    /** With a clock a test can move past the window. */
    CheckoutTrackingService(OrderParticipantsRepository participants, TrackingService tracking,
                            EtaService eta, RoutePaths paths,
                            OtherDeliveriesLatch otherDeliveries, Duration maxFixAge,
                            Duration recomputeAfter, Clock clock) {
        this.participants = participants;
        this.tracking = tracking;
        this.eta = eta;
        this.paths = paths;
        this.otherDeliveries = otherDeliveries;
        this.maxFixAge = maxFixAge;
        this.recomputeAfter = recomputeAfter;
        this.clock = clock;
    }

    /**
     * The checkout's map, for its own customer — or for the back office, which reads any.
     *
     * <p>The customer's rows are selected by checkout <em>and</em> customer in one query, so a
     * checkout that is someone else's and one that does not exist are the same empty answer and
     * the same 404. That includes a sibling's merchant and the rider: each sees their own order
     * elsewhere, and neither may see the customer's other shops.
     *
     * @throws CheckoutNotFoundException when the caller has no order in this checkout
     */
    @Transactional(readOnly = true)
    public CheckoutView view(UUID checkoutId, String callerId, boolean isBackoffice) {
        List<OrderParticipants> orders = isBackoffice
                ? participants.findByCheckoutId(checkoutId)
                : participants.findByCheckoutIdAndCustomerId(checkoutId, callerId);
        if (orders.isEmpty()) {
            throw new CheckoutNotFoundException();
        }

        Instant now = clock.instant();
        Memo recent = memo.get(checkoutId);
        if (recent != null && now.isBefore(recent.computedAt().plus(recomputeAfter))) {
            return recent.view();
        }

        CheckoutView view = compute(checkoutId, orders, callerId, isBackoffice, now);
        remember(checkoutId, new Memo(view, now), now);
        return view;
    }

    private CheckoutView compute(UUID checkoutId, List<OrderParticipants> unsorted,
                                 String callerId, boolean isBackoffice, Instant now) {
        // Rows in a stable order, so a refresh never shuffles the list under a thumb.
        List<OrderParticipants> orders = new ArrayList<>(unsorted);
        orders.sort(Comparator
                .comparing((OrderParticipants o) -> o.getStoreName() == null
                        ? null
                        : o.getStoreName().toLowerCase(Locale.ROOT),
                        Comparator.nullsLast(Comparator.naturalOrder()))
                .thenComparing(OrderParticipants::getOrderId));

        Optional<GeoPoint> door = sharedDoor(orders);

        // Each rider's live orders of this checkout, in row order.
        Map<String, List<OrderParticipants>> byRider = new LinkedHashMap<>();
        for (OrderParticipants order : orders) {
            if (!order.isComplete() && order.getRiderId() != null) {
                byRider.computeIfAbsent(order.getRiderId(), rider -> new ArrayList<>()).add(order);
            }
        }

        Map<UUID, Integer> stops = new HashMap<>();
        Set<UUID> expected = new HashSet<>();
        Map<UUID, EtaResult> etas = new HashMap<>();
        List<RiderView> riders = new ArrayList<>();
        List<PathView> lines = new ArrayList<>();

        for (Map.Entry<String, List<OrderParticipants>> entry : byRider.entrySet()) {
            List<OrderParticipants> riderOrders = entry.getValue();

            // One rider, one position: what the gate lets this caller see of them on any of their
            // orders here — never a fix it would withhold on one of them (RunSighting).
            List<RiderSighting> sightings = new ArrayList<>();
            for (OrderParticipants order : riderOrders) {
                sightings.add(tracking.sightingFor(order, callerId, isBackoffice));
            }
            RunSighting seen = RunSighting.of(sightings);
            Optional<Position> shown = seen.shown();
            boolean fresh = shown.isPresent() && shown.get().recordedAt() != null
                    && !shown.get().recordedAt().isBefore(now.minus(maxFixAge));

            // Which shop is expected next is measured from where the rider was last seen, so it is
            // measured only from a point the caller may see: a withheld fix would be given away by
            // the order it puts the shops in.
            RunPlan plan = RunPlan.of(riderOrders, shown);
            boolean run = riderOrders.size() >= 2;
            if (run) {
                stops.putAll(plan.stopNumbers());
                expected.addAll(plan.expected());
            }
            for (OrderParticipants order : riderOrders) {
                EtaResult estimate = eta.estimate(order, riderOrders, seen, now);
                etas.put(order.getOrderId(),
                        shown.isPresent() ? estimate : estimate.withoutDistance());
            }

            List<UUID> visitOrder = plan.visitOrder().stream()
                    .map(OrderParticipants::getOrderId)
                    .toList();
            riders.add(new RiderView(visitOrder, run, seen.state(),
                    shown.map(p -> new RiderFix(p.lat(), p.lng(), p.recordedAt(), !fresh))
                            .orElse(null),
                    // Latched: a flip back to "no" happens at another customer's door.
                    otherDeliveries.hasOtherDeliveries(checkoutId, entry.getKey())));

            // The live leg: only from a fresh fix the caller may see, and only when every stop on
            // it has a pin.
            if (fresh && door.isPresent() && plan.aheadPinned()) {
                GeoPoint from = new GeoPoint(shown.get().lat(), shown.get().lng());
                List<GeoPoint> ahead = new ArrayList<>(plan.aheadPins());
                ahead.add(door.get());
                Optional<RoutePath> leg = paths.riderLeg(from, ahead);
                if (leg.isPresent()) {
                    List<GeoPoint> points = new ArrayList<>();
                    points.add(from);
                    points.addAll(ahead);
                    lines.add(pathView(visitOrder, PathKind.RIDER_LEG, points, leg.get()));
                }
            }
        }

        for (OrderParticipants order : orders) {
            if (etas.containsKey(order.getOrderId())) {
                continue;
            }
            // Riderless or finished: no fix to measure from. The estimate says which, in the
            // same words the single-order panel would.
            etas.put(order.getOrderId(),
                    eta.estimate(order, List.of(order), RunSighting.NOTHING, now));
            if (!order.isComplete() && order.getRiderId() == null
                    && order.pickup().isPresent() && door.isPresent()) {
                List<GeoPoint> points = List.of(order.pickup().get(), door.get());
                paths.planned(points).ifPresent(path -> lines.add(pathView(
                        List.of(order.getOrderId()), PathKind.PLANNED, points, path)));
            }
        }

        List<OrderView> rows = orders.stream()
                .map(order -> new OrderView(
                        order.getOrderId(),
                        order.getStoreName(),
                        order.getStatus(),
                        order.pickup().map(Pin::of).orElse(null),
                        order.getRiderId() != null,
                        stops.get(order.getOrderId()),
                        expected.contains(order.getOrderId()),
                        order.getPickedUpAt(),
                        order.getCompletedAt(),
                        etas.get(order.getOrderId())))
                .toList();

        return new CheckoutView(checkoutId, paths.providerName(), paths.geometry(),
                door.map(Pin::of).orElse(null), rows, riders, lines, now);
    }

    /**
     * The customer's pin: the dropoff every order of the checkout carries.
     *
     * <p>One basket is checked out to one address, so the orders agree by construction. Should they
     * ever not — a message is untrusted input — there is no one door the platform can back up, and
     * none is drawn rather than one picked.
     */
    private static Optional<GeoPoint> sharedDoor(List<OrderParticipants> orders) {
        GeoPoint door = null;
        for (OrderParticipants order : orders) {
            Optional<GeoPoint> dropoff = order.dropoff();
            if (dropoff.isEmpty()) {
                continue;
            }
            if (door == null) {
                door = dropoff.get();
            } else if (!door.equals(dropoff.get())) {
                return Optional.empty();
            }
        }
        return Optional.ofNullable(door);
    }

    private static PathView pathView(List<UUID> orderIds, PathKind kind, List<GeoPoint> points,
                                     RoutePath path) {
        return new PathView(orderIds, kind, points.stream().map(Pin::of).toList(), path.polyline6(),
                path.distanceMetres(), path.provider());
    }

    private void remember(UUID checkoutId, Memo entry, Instant now) {
        if (memo.size() >= MEMO_SWEEP_THRESHOLD) {
            memo.values().removeIf(old -> !now.isBefore(old.computedAt().plus(recomputeAfter)));
        }
        memo.put(checkoutId, entry);
    }

    private record Memo(CheckoutView view, Instant computedAt) {
    }

    /**
     * The caller has no order in this checkout — or it does not exist, which is deliberately the
     * same thing from outside.
     */
    public static class CheckoutNotFoundException extends RuntimeException {
        public CheckoutNotFoundException() {
            super("No checkout map for this checkout");
        }
    }
}
