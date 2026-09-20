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
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import com.delivery.tracking.domain.OrderParticipants;
import com.delivery.tracking.domain.OrderParticipantsRepository;
import com.delivery.tracking.route.GeoPoint;
import com.delivery.tracking.route.PathGeometry;
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
 * <p><strong>Computed at most once every few seconds per checkout and reader.</strong> The screen
 * polls, the customer may have it open on two devices, and every recomputation is a round of
 * position reads and — with a routing engine — routing requests; Mapbox's are billed and may not
 * be cached. What the answer contains depends on who asked — the gate above shows the back office
 * what it withholds from the customer — so the answer is remembered per (checkout, reader), never
 * shared between them, and the caller is checked against the rows on every request, memo or not.
 */
@Service
public class CheckoutTrackingService {

    private static final Logger log = LoggerFactory.getLogger(CheckoutTrackingService.class);

    /** Past this many remembered checkouts, expired answers are swept on the next write. */
    private static final int MEMO_SWEEP_THRESHOLD = 500;

    /**
     * How long a request waits for another request's computation of the same answer before making
     * its own. Comfortably past a full round of routing calls at their own timeouts, so it is only
     * ever reached by a computation that is stuck rather than slow.
     */
    private static final Duration WAIT_FOR_LEADER = Duration.ofSeconds(20);

    private final OrderParticipantsRepository participants;
    private final TrackingService tracking;
    private final EtaService eta;
    private final RoutePaths paths;
    private final OtherDeliveriesLatch otherDeliveries;
    private final Duration maxFixAge;
    private final Duration recomputeAfter;
    private final Clock clock;
    private final Map<ViewKey, Memo> memo = new ConcurrentHashMap<>();
    private final Map<ViewKey, CompletableFuture<CheckoutView>> inFlight = new ConcurrentHashMap<>();

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
     * The checkout's map, for the customer whose checkout it is — or for the back office, which
     * reads any.
     *
     * <p>A customer gets it only when <em>every</em> row of the checkout is theirs. The whole
     * checkout is read and then judged, rather than the rows being selected by customer as well:
     * a checkout id links orders that a message said belong together, and a mislabelled one — one
     * row of somebody else's under this id — would otherwise quietly serve this customer the rest
     * of it, and serve that other customer their own row as a checkout of their own. Neither is a
     * map the platform can stand behind, so it is the same 404 as a checkout that does not exist,
     * which is also what a sibling's merchant and the rider get.
     *
     * <p><strong>Deliberately not transactional.</strong> Computing a map calls out to a routing
     * engine, several times, and a read-only transaction around the whole method would hold a
     * connection from the service's pool for every one of those calls — the pool that every rider
     * ping needs. Each read inside takes its own short transaction instead (the repository's, and
     * {@link TrackingService#sightingFor}'s), so nothing is held while the routing host is
     * thinking. The rows are read once, at the start, and the answer is built from that reading:
     * a map is a snapshot of a moment either way.
     *
     * @throws CheckoutNotFoundException when the checkout is not the caller's, whole and entire
     */
    public CheckoutView view(UUID checkoutId, String callerId, boolean isBackoffice) {
        List<OrderParticipants> orders = participants.findByCheckoutId(checkoutId);
        if (orders.isEmpty() || (!isBackoffice && (callerId == null || orders.stream()
                .anyMatch(order -> !callerId.equals(order.getCustomerId()))))) {
            throw new CheckoutNotFoundException();
        }

        // One remembered answer per reader: the back office's carries positions the customer's
        // must not, so handing one to the other would hand over exactly what the gate withheld.
        ViewKey key = new ViewKey(checkoutId, isBackoffice ? BACKOFFICE : callerId);
        Instant now = clock.instant();
        CheckoutView remembered = remembered(key, now);
        if (remembered != null) {
            return remembered;
        }
        return computeOnce(key, checkoutId, orders, callerId, isBackoffice, now);
    }

    private CheckoutView remembered(ViewKey key, Instant now) {
        Memo recent = memo.get(key);
        return recent != null && now.isBefore(recent.computedAt().plus(recomputeAfter))
                ? recent.view()
                : null;
    }

    /**
     * Computes the answer for one key, or waits for the computation already running for it.
     *
     * <p>The screen polls, a customer may watch on two devices, and the memo window is a few
     * seconds — so the requests that miss it arrive together. Without this, each of them would
     * make its own round of position reads and routing calls for the same answer, the routing
     * engine seeing a burst per checkout rather than a request. The first one in computes; the
     * others wait for it and are handed the same answer.
     *
     * <p>A leader that is taking longer than any routing round should is given up on rather than
     * waited out, and the caller computes its own: a slow answer beats a thread parked on someone
     * else's.
     */
    private CheckoutView computeOnce(ViewKey key, UUID checkoutId,
                                     List<OrderParticipants> orders, String callerId,
                                     boolean isBackoffice, Instant now) {
        CompletableFuture<CheckoutView> mine = new CompletableFuture<>();
        CompletableFuture<CheckoutView> leader = inFlight.putIfAbsent(key, mine);
        if (leader != null) {
            try {
                return leader.get(WAIT_FOR_LEADER.toMillis(), TimeUnit.MILLISECONDS);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                throw new IllegalStateException("Interrupted waiting for a checkout map", e);
            } catch (ExecutionException e) {
                // The computation this one joined failed; fall through and make the attempt it
                // would have made on its own.
                log.debug("The checkout map computation this request joined failed", e);
            } catch (TimeoutException e) {
                log.warn("Waited {} for another request's checkout map; computing this one's own",
                        WAIT_FOR_LEADER);
            }
            return compute(checkoutId, orders, callerId, isBackoffice, clock.instant());
        }
        try {
            CheckoutView view = compute(checkoutId, orders, callerId, isBackoffice, now);
            remember(key, new Memo(view, now), now);
            mine.complete(view);
            return view;
        } catch (RuntimeException | Error e) {
            mine.completeExceptionally(e);
            throw e;
        } finally {
            inFlight.remove(key, mine);
        }
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

        // How the answer is drawn is read off what was actually returned, not off who was asked:
        // one line that fell back to straight segments (a routing engine that did not answer in
        // time) makes the whole answer say "approximate", which is the claim it can always make
        // honestly. With no lines at all it is what the live provider would have drawn.
        PathGeometry geometry = lines.stream().allMatch(line -> line.polyline6() != null)
                ? paths.geometry()
                : PathGeometry.STRAIGHT;

        return new CheckoutView(checkoutId, paths.providerName(), geometry,
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

    private void remember(ViewKey key, Memo entry, Instant now) {
        if (memo.size() >= MEMO_SWEEP_THRESHOLD) {
            memo.values().removeIf(old -> !now.isBefore(old.computedAt().plus(recomputeAfter)));
        }
        memo.put(key, entry);
    }

    /**
     * Which answer this is: one checkout, as seen by one reader.
     *
     * @param reader the caller's id, or {@link #BACKOFFICE} for the back office, whose readers
     *               all see the same thing and are few
     */
    private record ViewKey(UUID checkoutId, String reader) {
    }

    /** The reader every back-office caller shares. Not a user id: those are Keycloak subjects. */
    private static final String BACKOFFICE = "*";

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
