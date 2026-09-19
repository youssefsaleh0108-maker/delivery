package com.delivery.tracking.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyBoolean;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.spy;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.stream.Stream;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.data.domain.Pageable;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.ValueOperations;

import com.delivery.tracking.domain.OrderParticipants;
import com.delivery.tracking.domain.OrderParticipantsRepository;
import com.delivery.tracking.domain.TrackingEvent;
import com.delivery.tracking.domain.TrackingEventRepository;
import com.delivery.tracking.route.GeoPoint;
import com.delivery.tracking.route.HaversineRouteProvider;
import com.delivery.tracking.route.PathGeometry;
import com.delivery.tracking.route.RoutePaths;
import com.delivery.tracking.route.RouteProviderRegistry;
import com.delivery.tracking.service.CheckoutTrackingService.CheckoutNotFoundException;
import com.delivery.tracking.service.CheckoutView.OrderView;
import com.delivery.tracking.service.CheckoutView.PathKind;
import com.delivery.tracking.service.CheckoutView.PathView;
import com.delivery.tracking.service.CheckoutView.Pin;
import com.delivery.tracking.service.CheckoutView.RiderView;
import com.delivery.tracking.service.EtaService.EtaResult;
import com.delivery.tracking.service.EtaService.Leg;
import com.delivery.tracking.service.EtaService.Reason;
import com.delivery.tracking.service.PresenceService.LatestFix;
import com.delivery.tracking.service.RiderSighting.State;
import com.delivery.tracking.service.TrackingService.Position;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;

/**
 * What a customer's map of a multi-shop checkout shows, and — mostly — what it refuses to show.
 *
 * <p>Every coordinate on that map is one the platform holds and the caller may see, every number
 * on a pickup stop is either a fact (collected, in collection order) or marked as an expectation,
 * and every line ends at a pin. The tests are arranged around those promises.
 *
 * <p>The rider-visibility gate is the real one ({@link TrackingService#sightingFor}), over an
 * in-memory projection and presence store: where it withholds a rider on the single-order
 * endpoints, the map must withhold them too.
 */
@DisplayName("the checkout map")
class CheckoutTrackingServiceTest {

    private static final UUID CHECKOUT = UUID.fromString("c4ec0000-0000-4000-8000-000000000001");
    private static final String CUSTOMER = "customer-sub";
    private static final String SOMEONE_ELSE = "someone-else-sub";
    private static final String RIDER = "rider-1";
    private static final String OTHER_RIDER = "rider-2";

    // Beirut. The door in Mar Mikhael; shops in Hamra (A), Achrafieh (B) and Ras Beirut (C).
    // A–B 1.3 km, A–door 1.9 km, B–door 1.5 km; C is 2.1 km from A and 3.4 km from B.
    private static final GeoPoint DOOR = new GeoPoint(33.8981, 35.5214);
    private static final GeoPoint SHOP_A = new GeoPoint(33.8938, 35.5018);
    private static final GeoPoint SHOP_B = new GeoPoint(33.8869, 35.5131);
    private static final GeoPoint SHOP_C = new GeoPoint(33.9000, 35.4800);
    // Another customer's door, 1.2 km south of this customer's.
    private static final GeoPoint THEIR_DOOR = offset(DOOR, -1_200, 0);

    private static final UUID A = UUID.fromString("00000000-0000-4000-8000-00000000000a");
    private static final UUID B = UUID.fromString("00000000-0000-4000-8000-00000000000b");
    private static final UUID C = UUID.fromString("00000000-0000-4000-8000-00000000000c");
    private static final UUID X = UUID.fromString("00000000-0000-4000-8000-0000000000ff");

    // Starts at the real now: the single-order endpoint compared against below reads the real clock.
    private final MutableClock clock =
            new MutableClock(Instant.now().truncatedTo(java.time.temporal.ChronoUnit.SECONDS));
    private final List<OrderParticipants> rows = new ArrayList<>();
    private final List<OrderParticipants> others = new ArrayList<>();
    private final Map<String, LatestFix> latest = new HashMap<>();
    private final Map<UUID, TrackingEvent> orderFixes = new HashMap<>();

    private OrderParticipantsRepository participants;
    private TrackingService tracking;
    private EtaService eta;
    private CheckoutTrackingService service;

    /** A clock the memo test can move past its window. */
    static final class MutableClock extends Clock {
        private Instant now;

        MutableClock(Instant now) {
            this.now = now;
        }

        void advance(Duration by) {
            now = now.plus(by);
        }

        @Override
        public ZoneId getZone() {
            return ZoneOffset.UTC;
        }

        @Override
        public Clock withZone(ZoneId zone) {
            return this;
        }

        @Override
        public Instant instant() {
            return now;
        }
    }

    /** A point {@code north} and {@code east} metres from {@code from}. */
    private static GeoPoint offset(GeoPoint from, double north, double east) {
        double metresPerDegreeLat = 111_195.08;
        double metresPerDegreeLng = metresPerDegreeLat * Math.cos(Math.toRadians(from.lat()));
        return new GeoPoint(from.lat() + north / metresPerDegreeLat,
                from.lng() + east / metresPerDegreeLng);
    }

    @BeforeEach
    @SuppressWarnings("unchecked")
    void setUp() {
        participants = mock(OrderParticipantsRepository.class);
        when(participants.findByCheckoutIdAndCustomerId(CHECKOUT, CUSTOMER)).thenReturn(rows);
        when(participants.findByCheckoutId(CHECKOUT)).thenReturn(rows);
        when(participants.findById(any())).thenAnswer(call -> all()
                .filter(o -> o.getOrderId().equals(call.getArgument(0))).findFirst());
        // The repository's rule for the hand-over buffer, over the same rows.
        when(participants.otherCustomersDoors(anyString(), anyString(), any())).thenAnswer(call -> {
            String rider = call.getArgument(0);
            String customer = call.getArgument(1);
            Instant finishedSince = call.getArgument(2);
            return all()
                    .filter(o -> rider.equals(o.getRiderId()))
                    .filter(o -> !customer.equals(o.getCustomerId()))
                    .filter(o -> o.dropoff().isPresent())
                    .filter(o -> o.isTrackable() || (o.getCompletedAt() != null
                            && !o.getCompletedAt().isBefore(finishedSince)))
                    .toList();
        });

        PresenceService presence = mock(PresenceService.class);
        when(presence.latestFix(anyString()))
                .thenAnswer(call -> Optional.ofNullable(latest.get(call.<String>getArgument(0))));
        TrackingEventRepository events = mock(TrackingEventRepository.class);
        when(events.findLatestForOrder(any(), any(Pageable.class))).thenAnswer(call ->
                Optional.ofNullable(orderFixes.get(call.<UUID>getArgument(0)))
                        .map(List::of).orElse(List.of()));
        StringRedisTemplate redis = mock(StringRedisTemplate.class);
        when(redis.opsForValue()).thenReturn(mock(ValueOperations.class));
        tracking = spy(new TrackingService(events, participants, presence, redis,
                new ObjectMapper().registerModule(new JavaTimeModule()), Duration.ofSeconds(60)));

        // 60 km/h, so kilometres read as minutes.
        RouteProviderRegistry providers = new RouteProviderRegistry(
                List.of(new HaversineRouteProvider(60)), HaversineRouteProvider.NAME);
        eta = new EtaService(tracking, participants, providers, Duration.ofMinutes(5));
        RoutePaths paths = new RoutePaths(providers, mock(StringRedisTemplate.class),
                new ObjectMapper(), Duration.ofHours(24), 150, Duration.ofSeconds(60));
        service = new CheckoutTrackingService(participants, tracking, eta, paths,
                Duration.ofMinutes(5), Duration.ofSeconds(5), clock);
    }

    private Stream<OrderParticipants> all() {
        return Stream.concat(rows.stream(), others.stream());
    }

    // ------------------------------------------------------------------------------ fixtures

    /** One order of the checkout, with its shop pin (or none) and the shared door. */
    private OrderParticipants order(UUID id, String shop, GeoPoint pin, String status, String rider) {
        OrderParticipants order = new OrderParticipants(id, CUSTOMER, "merchant-" + shop, rider,
                status);
        order.applyRoute(null, pin, DOOR);
        order.applyCheckout(CHECKOUT, shop);
        rows.add(order);
        return order;
    }

    /** An order this rider collected at {@code at}. */
    private OrderParticipants collected(UUID id, String shop, GeoPoint pin, String rider,
                                        Instant at) {
        OrderParticipants order = order(id, shop, pin, "PICKED_UP", rider);
        order.stampMilestones("PICKED_UP", at);
        return order;
    }

    /** Somebody else's order, from its own shop to their door, in this rider's hands. */
    private OrderParticipants theirOrder(String rider, String status) {
        OrderParticipants order = new OrderParticipants(X, SOMEONE_ELSE, "merchant-x", rider,
                status);
        order.applyRoute(null, offset(THEIR_DOOR, 0, -900), THEIR_DOOR);
        others.add(order);
        return order;
    }

    /**
     * The rider's phone reported {@code where}, {@code ago}, on {@code orderId}: the rider's latest
     * fix (what the gate reads for the customer) if it is newer than the one before, and the
     * order's own latest position (what the back office reads).
     */
    private void riderAt(UUID orderId, String rider, GeoPoint where, Duration ago) {
        Instant at = clock.instant().minus(ago);
        LatestFix previous = latest.get(rider);
        if (previous == null || !at.isBefore(previous.at())) {
            latest.put(rider, new LatestFix(rider, orderId, where.lat(), where.lng(), 5f, at));
        }
        orderFixes.put(orderId, new TrackingEvent(orderId, rider, where.lat(), where.lng(), 5f,
                at));
    }

    private CheckoutView view() {
        return service.view(CHECKOUT, CUSTOMER, false);
    }

    private static OrderView row(CheckoutView view, UUID id) {
        return view.orders().stream().filter(o -> o.orderId().equals(id)).findFirst().orElseThrow();
    }

    private static List<PathView> pathsOf(CheckoutView view, PathKind kind) {
        return view.paths().stream().filter(p -> p.kind() == kind).toList();
    }

    /**
     * The promise the gate makes about this endpoint: every rider marker is a position the
     * single-order endpoint shows this customer for one of that rider's orders, and every live leg
     * starts at a marker.
     */
    private void showsNothingTheOrderEndpointsWithhold(CheckoutView view) {
        for (RiderView rider : view.riders()) {
            if (rider.position() == null) {
                assertThat(view.paths()).noneMatch(p -> p.kind() == PathKind.RIDER_LEG
                        && p.orderIds().stream().anyMatch(rider.orderIds()::contains));
                continue;
            }
            Pin marker = new Pin(rider.position().lat(), rider.position().lng());
            assertThat(rider.orderIds())
                    .as("some order of the rider shows the customer this marker on its own")
                    .anyMatch(id -> tracking.currentPosition(id, CUSTOMER, false)
                            .map(p -> new Pin(p.lat(), p.lng()).equals(marker))
                            .orElse(false));
            view.paths().stream()
                    .filter(p -> p.kind() == PathKind.RIDER_LEG)
                    .filter(p -> p.orderIds().stream().anyMatch(rider.orderIds()::contains))
                    .forEach(p -> assertThat(p.points().get(0)).isEqualTo(marker));
        }
    }

    // ------------------------------------------------------------------------------ tests

    @Nested
    @DisplayName("before any rider is assigned")
    class BeforeARider {

        @Test
        @DisplayName("shows every shop, the door and a planned path each — but no number and no ETA")
        void pins_and_planned_paths_only() {
            order(A, "Hamra Bakery", SHOP_A, "PREPARING", null);
            order(B, "Achrafieh Pharmacy", SHOP_B, "READY", null);

            CheckoutView view = view();

            assertThat(view.door()).isEqualTo(new Pin(DOOR.lat(), DOOR.lng()));
            assertThat(row(view, A).shop()).isEqualTo(new Pin(SHOP_A.lat(), SHOP_A.lng()));
            assertThat(view.orders()).allSatisfy(o -> {
                assertThat(o.stop()).isNull();
                assertThat(o.expected()).isFalse();
                assertThat(o.riderAssigned()).isFalse();
                // The existing rule: no fix, no number.
                assertThat(o.eta().available()).isFalse();
                assertThat(o.eta().reason()).isEqualTo(Reason.NO_FIX);
            });
            assertThat(view.riders()).isEmpty();
            assertThat(pathsOf(view, PathKind.PLANNED)).hasSize(2)
                    .allSatisfy(p -> assertThat(p.points().get(1))
                            .isEqualTo(new Pin(DOOR.lat(), DOOR.lng())));
            assertThat(pathsOf(view, PathKind.RIDER_LEG)).isEmpty();
        }

        /** Rows sorted by shop name, so a refresh never reshuffles the list. */
        @Test
        @DisplayName("lists the orders in a stable order")
        void rows_are_stable() {
            order(B, "zaatar corner", SHOP_B, "PLACED", null);
            order(A, "Abou Joseph", SHOP_A, "PLACED", null);

            assertThat(view().orders()).extracting(OrderView::storeName)
                    .containsExactly("Abou Joseph", "zaatar corner");
        }
    }

    @Nested
    @DisplayName("a run: one rider holding several of the checkout's orders")
    class Runs {

        /**
         * A was really collected first; B and C are ahead. From a rider standing between Hamra and
         * Achrafieh, Achrafieh (B) is nearer than Ras Beirut (C).
         */
        @Test
        @DisplayName("numbers collected stops by collection time, then the rest nearest-next, marked expected")
        void collected_then_expected() {
            collected(A, "Hamra Bakery", SHOP_A, RIDER, clock.instant().minusSeconds(600));
            order(B, "Achrafieh Pharmacy", SHOP_B, "READY", RIDER);
            order(C, "Ras Beirut Grocer", SHOP_C, "READY", RIDER);
            riderAt(A, RIDER, new GeoPoint(33.8950, 35.5050), Duration.ofSeconds(20));

            CheckoutView view = view();

            assertThat(row(view, A).stop()).isEqualTo(1);
            assertThat(row(view, A).expected()).isFalse();
            assertThat(row(view, B).stop()).isEqualTo(2);
            assertThat(row(view, B).expected()).isTrue();
            assertThat(row(view, C).stop()).isEqualTo(3);
            assertThat(row(view, C).expected()).isTrue();

            RiderView rider = view.riders().get(0);
            assertThat(view.riders()).hasSize(1);
            assertThat(rider.run()).isTrue();
            assertThat(rider.orderIds()).containsExactly(A, B, C);
            assertThat(rider.sighting()).isEqualTo(State.VISIBLE);
            assertThat(rider.position().stale()).isFalse();

            // One live leg for the whole run: rider → B → C → door.
            List<PathView> legs = pathsOf(view, PathKind.RIDER_LEG);
            assertThat(legs).hasSize(1);
            assertThat(legs.get(0).orderIds()).containsExactly(A, B, C);
            assertThat(legs.get(0).points()).containsExactly(
                    new Pin(33.8950, 35.5050),
                    new Pin(SHOP_B.lat(), SHOP_B.lng()),
                    new Pin(SHOP_C.lat(), SHOP_C.lng()),
                    new Pin(DOOR.lat(), DOOR.lng()));
            assertThat(pathsOf(view, PathKind.PLANNED)).isEmpty();
            showsNothingTheOrderEndpointsWithhold(view);
        }

        @Test
        @DisplayName("sends the rider to whichever remaining shop is nearest them")
        void expected_order_follows_the_rider() {
            order(B, "Achrafieh Pharmacy", SHOP_B, "READY", RIDER);
            order(C, "Ras Beirut Grocer", SHOP_C, "READY", RIDER);
            // Standing at the Ras Beirut shop: C first, then B.
            riderAt(C, RIDER, new GeoPoint(33.9001, 35.4801), Duration.ofSeconds(10));

            CheckoutView view = view();

            assertThat(row(view, C).stop()).isEqualTo(1);
            assertThat(row(view, B).stop()).isEqualTo(2);
            assertThat(view.orders()).allSatisfy(o -> assertThat(o.expected()).isTrue());
        }

        /**
         * "In a run, every order shows the run's door ETA", and it is exactly what the
         * single-order panel is told for each of them.
         */
        @Test
        @DisplayName("gives every order the run's door estimate — the same one the order's own panel gets")
        void every_order_shows_the_runs_door_eta() {
            collected(A, "Hamra Bakery", SHOP_A, RIDER, clock.instant().minusSeconds(600));
            order(B, "Achrafieh Pharmacy", SHOP_B, "READY", RIDER);
            riderAt(A, RIDER, SHOP_A, Duration.ofSeconds(5));

            CheckoutView view = view();

            // Rider at A → B → door, summed: never straight to the door past B.
            double viaB = HaversineRouteProvider.distanceMetres(SHOP_A, SHOP_B)
                    + HaversineRouteProvider.distanceMetres(SHOP_B, DOOR);
            assertThat(row(view, A).eta().remainingMetres()).isCloseTo(viaB,
                    org.assertj.core.api.Assertions.within(1d));
            assertThat(row(view, B).eta().remainingMetres())
                    .isEqualTo(row(view, A).eta().remainingMetres());
            // Still collecting (B's goods), so neither is "on the way to you" yet.
            assertThat(row(view, A).eta().leg()).isEqualTo(Leg.TO_PICKUP);

            // The panel's own endpoint agrees, for both orders.
            assertThat(eta.estimateFor(A, CUSTOMER, false).remainingMetres())
                    .isEqualTo(row(view, A).eta().remainingMetres());
            assertThat(eta.estimateFor(B, CUSTOMER, false).remainingMetres())
                    .isEqualTo(row(view, B).eta().remainingMetres());
        }

        /** The cancelled shop leaves the run; the stops that remain close up. */
        @Test
        @DisplayName("renumbers its remaining stops when one of them is cancelled")
        void a_cancel_renumbers() {
            collected(A, "Hamra Bakery", SHOP_A, RIDER, clock.instant().minusSeconds(600));
            OrderParticipants b = order(B, "Achrafieh Pharmacy", SHOP_B, "READY", RIDER);
            order(C, "Ras Beirut Grocer", SHOP_C, "READY", RIDER);
            riderAt(A, RIDER, new GeoPoint(33.8950, 35.5050), Duration.ofSeconds(20));
            b.apply(RIDER, "CANCELLED");
            b.stampMilestones("CANCELLED", clock.instant());

            CheckoutView view = view();

            assertThat(row(view, A).stop()).isEqualTo(1);
            assertThat(row(view, C).stop()).isEqualTo(2);
            assertThat(row(view, B).stop()).isNull();
            assertThat(row(view, B).status()).isEqualTo("CANCELLED");
            assertThat(row(view, B).completedAt()).isEqualTo(clock.instant());
            assertThat(row(view, B).eta().reason()).isEqualTo(Reason.ORDER_COMPLETE);
            assertThat(view.paths()).noneMatch(p -> p.orderIds().contains(B));
            assertThat(view.riders().get(0).orderIds()).containsExactly(A, C);
        }

        /** Two riders, one order each: numbers would suggest a sequence nobody chose. */
        @Test
        @DisplayName("gives no numbers when each order has its own rider")
        void no_numbers_without_a_run() {
            order(A, "Hamra Bakery", SHOP_A, "READY", RIDER);
            order(B, "Achrafieh Pharmacy", SHOP_B, "READY", OTHER_RIDER);
            riderAt(A, RIDER, offset(SHOP_A, 500, 0), Duration.ofSeconds(10));
            riderAt(B, OTHER_RIDER, offset(SHOP_B, 0, 500), Duration.ofSeconds(10));

            CheckoutView view = view();

            assertThat(view.orders()).allSatisfy(o -> {
                assertThat(o.stop()).isNull();
                assertThat(o.expected()).isFalse();
            });
            assertThat(view.riders()).hasSize(2).allSatisfy(r -> assertThat(r.run()).isFalse());
            // A leg each: rider → own shop → door.
            assertThat(pathsOf(view, PathKind.RIDER_LEG)).hasSize(2)
                    .allSatisfy(p -> assertThat(p.points()).hasSize(3));
            showsNothingTheOrderEndpointsWithhold(view);
        }
    }

    @Nested
    @DisplayName("the rider-visibility gate")
    class Gate {

        /**
         * The rider finished somebody else's delivery five minutes ago and their leg switched to
         * this customer's order, but the phone is still 100 m from that other door. The
         * single-order endpoint withholds the rider (the hand-over buffer); so does the map: no
         * marker, no leg from there, no distance or time, not even the fix's time.
         */
        @Test
        @DisplayName("draws no rider inside the hand-over buffer of another customer's door")
        void no_marker_inside_the_handover_buffer() {
            collected(A, "Hamra Bakery", SHOP_A, RIDER, clock.instant().minusSeconds(1_200));
            OrderParticipants theirs = theirOrder(RIDER, "PICKED_UP");
            theirs.apply(RIDER, "DELIVERED");
            theirs.stampMilestones("DELIVERED", clock.instant().minus(Duration.ofMinutes(5)));
            riderAt(A, RIDER, offset(THEIR_DOOR, 100, 0), Duration.ofSeconds(10));

            CheckoutView view = view();

            RiderView rider = view.riders().get(0);
            assertThat(rider.sighting()).isEqualTo(State.ON_ANOTHER_DELIVERY);
            assertThat(rider.position()).isNull();
            assertThat(pathsOf(view, PathKind.RIDER_LEG)).isEmpty();
            EtaResult estimate = row(view, A).eta();
            assertThat(estimate.available()).isFalse();
            assertThat(estimate.reason()).isEqualTo(Reason.RIDER_ON_ANOTHER_DELIVERY);
            assertThat(estimate.remainingMetres()).isNull();
            assertThat(estimate.remainingSeconds()).isNull();
            assertThat(estimate.fixRecordedAt()).isNull();
            assertThat(tracking.currentPosition(A, CUSTOMER, false)).isEmpty();
            showsNothingTheOrderEndpointsWithhold(view);
        }

        @Test
        @DisplayName("draws the rider again once they are past the buffer")
        void a_marker_past_the_handover_buffer() {
            collected(A, "Hamra Bakery", SHOP_A, RIDER, clock.instant().minusSeconds(1_200));
            OrderParticipants theirs = theirOrder(RIDER, "PICKED_UP");
            theirs.apply(RIDER, "DELIVERED");
            theirs.stampMilestones("DELIVERED", clock.instant().minus(Duration.ofMinutes(5)));
            riderAt(A, RIDER, offset(THEIR_DOOR, 400, 0), Duration.ofSeconds(10));

            CheckoutView view = view();

            assertThat(view.riders().get(0).sighting()).isEqualTo(State.VISIBLE);
            assertThat(view.riders().get(0).position()).isNotNull();
            assertThat(pathsOf(view, PathKind.RIDER_LEG)).hasSize(1);
            showsNothingTheOrderEndpointsWithhold(view);
        }

        /** The rider's latest fix went on somebody else's order: they are on that delivery. */
        @Test
        @DisplayName("draws no rider while they are on another customer's delivery")
        void no_marker_on_another_delivery() {
            collected(A, "Hamra Bakery", SHOP_A, RIDER, clock.instant().minusSeconds(600));
            theirOrder(RIDER, "PICKED_UP");
            riderAt(A, RIDER, offset(SHOP_A, 200, 0), Duration.ofSeconds(60));
            riderAt(X, RIDER, offset(THEIR_DOOR, 0, -600), Duration.ofSeconds(5));

            CheckoutView view = view();

            assertThat(view.riders().get(0).sighting()).isEqualTo(State.ON_ANOTHER_DELIVERY);
            assertThat(view.riders().get(0).position()).isNull();
            assertThat(view.paths()).isEmpty();
            assertThat(row(view, A).eta().reason()).isEqualTo(Reason.RIDER_ON_ANOTHER_DELIVERY);
            showsNothingTheOrderEndpointsWithhold(view);
        }

        /**
         * Claims often happen at home. A READY order's rider more than 2 km from the shop is not
         * shown: no marker and no leg — but a time, as the single-order endpoint gives, with no
         * distance measured from the place it withholds.
         */
        @Test
        @DisplayName("draws no rider on a READY order more than 2 km from the shop, and gives a time without metres")
        void no_marker_ready_beyond_two_kilometres() {
            order(A, "Hamra Bakery", SHOP_A, "READY", RIDER);
            riderAt(A, RIDER, offset(SHOP_A, 0, 3_000), Duration.ofSeconds(10));

            CheckoutView view = view();

            RiderView rider = view.riders().get(0);
            assertThat(rider.sighting()).isEqualTo(State.HEADING_TO_SHOP);
            assertThat(rider.position()).isNull();
            assertThat(view.paths()).isEmpty();
            EtaResult estimate = row(view, A).eta();
            assertThat(estimate.available()).isTrue();
            assertThat(estimate.leg()).isEqualTo(Leg.TO_PICKUP);
            assertThat(estimate.remainingSeconds()).isPositive();
            assertThat(estimate.remainingMetres()).as("no distance from a withheld fix").isNull();
            // The panel's time is the same; only the map drops the metres.
            EtaResult panel = eta.estimateFor(A, CUSTOMER, false);
            assertThat(estimate.remainingSeconds()).isEqualTo(panel.remainingSeconds());
            showsNothingTheOrderEndpointsWithhold(view);
        }

        @Test
        @DisplayName("draws the rider once they are within 2 km of the shop")
        void a_marker_ready_within_two_kilometres() {
            order(A, "Hamra Bakery", SHOP_A, "READY", RIDER);
            riderAt(A, RIDER, offset(SHOP_A, 0, 1_500), Duration.ofSeconds(10));

            CheckoutView view = view();

            assertThat(view.riders().get(0).sighting()).isEqualTo(State.VISIBLE);
            assertThat(view.riders().get(0).position()).isNotNull();
            assertThat(pathsOf(view, PathKind.RIDER_LEG)).hasSize(1);
            assertThat(row(view, A).eta().remainingMetres()).isNotNull();
            showsNothingTheOrderEndpointsWithhold(view);
        }

        /**
         * Which shop comes next is worked out from where the rider is. From a withheld fix, the
         * order of the stops would say which shop the rider is nearer, so no order is given.
         */
        @Test
        @DisplayName("works out no stop order from a fix it withholds")
        void no_expected_order_from_a_withheld_fix() {
            order(A, "Hamra Bakery", SHOP_A, "READY", RIDER);
            order(B, "Achrafieh Pharmacy", SHOP_B, "READY", RIDER);
            riderAt(A, RIDER, offset(SHOP_A, 0, -3_000), Duration.ofSeconds(10));

            CheckoutView view = view();

            assertThat(view.riders().get(0).position()).isNull();
            assertThat(view.orders()).allSatisfy(o -> {
                assertThat(o.stop()).isNull();
                assertThat(o.expected()).isFalse();
                assertThat(o.eta().remainingMetres()).isNull();
            });
        }

        /**
         * One marker per rider: shown when the single-order endpoint shows it for any of the
         * rider's orders here — A's shop is 1.2 km away — though C's, 2.4 km away, would not.
         */
        @Test
        @DisplayName("shows a run's rider when the gate shows them on one of its orders")
        void a_run_is_shown_through_any_of_its_orders() {
            order(A, "Hamra Bakery", SHOP_A, "READY", RIDER);
            order(C, "Ras Beirut Grocer", SHOP_C, "READY", RIDER);
            GeoPoint between = new GeoPoint(33.8950, 35.5050);
            riderAt(A, RIDER, between, Duration.ofSeconds(10));

            CheckoutView view = view();

            assertThat(tracking.currentPosition(A, CUSTOMER, false)).isPresent();
            assertThat(tracking.currentPosition(C, CUSTOMER, false)).isEmpty();
            assertThat(view.riders().get(0).position())
                    .extracting(f -> new Pin(f.lat(), f.lng()))
                    .isEqualTo(new Pin(between.lat(), between.lng()));
            showsNothingTheOrderEndpointsWithhold(view);
        }
    }

    @Nested
    @DisplayName("once an order is finished")
    class Finished {

        @Test
        @DisplayName("a delivered order keeps its pin but loses its path and its rider")
        void delivered_drops_path_and_rider() {
            OrderParticipants a = collected(A, "Hamra Bakery", SHOP_A, RIDER,
                    clock.instant().minusSeconds(900));
            a.apply(RIDER, "DELIVERED");
            a.stampMilestones("DELIVERED", clock.instant().minusSeconds(60));
            order(B, "Achrafieh Pharmacy", SHOP_B, "PREPARING", null);
            riderAt(A, RIDER, DOOR, Duration.ofSeconds(70));

            CheckoutView view = view();

            assertThat(row(view, A).shop()).isNotNull();
            assertThat(row(view, A).completedAt()).isEqualTo(clock.instant().minusSeconds(60));
            assertThat(row(view, A).eta().reason()).isEqualTo(Reason.ORDER_COMPLETE);
            assertThat(view.riders()).isEmpty();
            assertThat(view.paths()).noneMatch(p -> p.orderIds().contains(A));
            // Tracking closed: the delivered order's rider is not even asked about.
            verify(tracking, never()).sightingFor(any(OrderParticipants.class), anyString(),
                    anyBoolean());
        }

        @Test
        @DisplayName("with every order finished the map is pins and outcomes only")
        void all_terminal_is_a_static_summary() {
            OrderParticipants a = collected(A, "Hamra Bakery", SHOP_A, RIDER,
                    clock.instant().minusSeconds(900));
            a.apply(RIDER, "DELIVERED");
            order(B, "Achrafieh Pharmacy", SHOP_B, "CANCELLED", null);

            CheckoutView view = view();

            assertThat(view.paths()).isEmpty();
            assertThat(view.riders()).isEmpty();
            assertThat(view.door()).isNotNull();
            assertThat(view.orders()).extracting(OrderView::status)
                    .containsExactly("CANCELLED", "DELIVERED");
        }
    }

    @Nested
    @DisplayName("nothing is drawn that the platform cannot back up")
    class NothingGuessed {

        @Test
        @DisplayName("a shop with no pin is not drawn, and no path passes through it")
        void a_shop_without_a_pin() {
            order(A, "Hamra Bakery", null, "PREPARING", null);
            order(B, "Achrafieh Pharmacy", SHOP_B, "PREPARING", null);

            CheckoutView view = view();

            assertThat(row(view, A).shop()).isNull();
            assertThat(view.paths()).hasSize(1);
            assertThat(view.paths().get(0).orderIds()).containsExactly(B);
        }

        @Test
        @DisplayName("with no door pin there is no door and no line at all")
        void no_door_no_lines() {
            OrderParticipants a = new OrderParticipants(A, CUSTOMER, "m", RIDER, "READY");
            a.applyRoute(null, SHOP_A, null);
            a.applyCheckout(CHECKOUT, "Hamra Bakery");
            rows.add(a);
            OrderParticipants b = new OrderParticipants(B, CUSTOMER, "m", null, "PREPARING");
            b.applyRoute(null, SHOP_B, null);
            b.applyCheckout(CHECKOUT, "Achrafieh Pharmacy");
            rows.add(b);
            riderAt(A, RIDER, offset(SHOP_A, 300, 0), Duration.ofSeconds(5));

            CheckoutView view = view();

            assertThat(view.door()).isNull();
            assertThat(view.paths()).isEmpty();
            assertThat(row(view, A).eta().reason()).isEqualTo(Reason.NO_DESTINATION);
        }

        /** In a run, a stop without a pin cannot be placed: no number, and no leg through it. */
        @Test
        @DisplayName("in a run, a stop without a pin gets no number and breaks no promise")
        void a_pinless_stop_in_a_run() {
            order(A, "Hamra Bakery", SHOP_A, "READY", RIDER);
            order(B, "Achrafieh Pharmacy", null, "READY", RIDER);
            riderAt(A, RIDER, offset(SHOP_A, 300, 0), Duration.ofSeconds(5));

            CheckoutView view = view();

            assertThat(row(view, A).stop()).isEqualTo(1);
            assertThat(row(view, B).stop()).isNull();
            assertThat(pathsOf(view, PathKind.RIDER_LEG)).isEmpty();
            assertThat(row(view, A).eta().reason()).isEqualTo(Reason.NO_DESTINATION);
        }

        /** A fix from twenty minutes ago is a memory: "last seen", no estimate, no line from it. */
        @Test
        @DisplayName("a stale fix is shown as last seen, with no ETA and no leg drawn from it")
        void a_stale_fix() {
            order(A, "Hamra Bakery", SHOP_A, "PICKED_UP", RIDER);
            riderAt(A, RIDER, SHOP_A, Duration.ofMinutes(20));

            CheckoutView view = view();

            RiderView rider = view.riders().get(0);
            assertThat(rider.position()).isNotNull();
            assertThat(rider.position().stale()).isTrue();
            assertThat(row(view, A).eta().available()).isFalse();
            assertThat(row(view, A).eta().reason()).isEqualTo(Reason.STALE_FIX);
            assertThat(view.paths()).isEmpty();
        }

        /** A rider whose phone never reported: the order is theirs, where they are is unknown. */
        @Test
        @DisplayName("a rider with no fix yet has no marker and no line")
        void a_rider_with_no_fix() {
            order(A, "Hamra Bakery", SHOP_A, "READY", RIDER);

            CheckoutView view = view();

            assertThat(row(view, A).riderAssigned()).isTrue();
            assertThat(view.riders().get(0).sighting()).isEqualTo(State.NO_FIX);
            assertThat(view.riders().get(0).position()).isNull();
            assertThat(view.paths()).isEmpty();
            assertThat(row(view, A).eta().reason()).isEqualTo(Reason.NO_FIX);
        }
    }

    @Test
    @DisplayName("names the provider and says straight lines are straight lines")
    void the_provider_label() {
        order(A, "Hamra Bakery", SHOP_A, "PICKED_UP", RIDER);
        riderAt(A, RIDER, SHOP_A, Duration.ofSeconds(5));

        CheckoutView view = view();

        assertThat(view.provider()).isEqualTo(HaversineRouteProvider.NAME);
        assertThat(view.geometry()).isEqualTo(PathGeometry.STRAIGHT);
        assertThat(view.paths()).allSatisfy(p -> {
            assertThat(p.polyline6()).isNull();
            assertThat(p.provider()).isEqualTo(HaversineRouteProvider.NAME);
        });
        assertThat(row(view, A).eta().provider()).isEqualTo(HaversineRouteProvider.NAME);
    }

    @Test
    @DisplayName("says when the rider is also carrying somebody else's order — and nothing more")
    void other_deliveries_flag() {
        order(A, "Hamra Bakery", SHOP_A, "READY", RIDER);
        order(B, "Achrafieh Pharmacy", SHOP_B, "READY", OTHER_RIDER);
        when(participants.riderHasOtherLiveOrders(RIDER, CHECKOUT)).thenReturn(true);

        CheckoutView view = view();

        RiderView busy = view.riders().stream().filter(r -> r.orderIds().contains(A)).findFirst()
                .orElseThrow();
        RiderView free = view.riders().stream().filter(r -> r.orderIds().contains(B)).findFirst()
                .orElseThrow();
        assertThat(busy.hasOtherDeliveries()).isTrue();
        assertThat(free.hasOtherDeliveries()).isFalse();
    }

    @Nested
    @DisplayName("who may see it")
    class Scope {

        @Test
        @DisplayName("somebody with no order in the checkout is told it does not exist")
        void a_stranger_gets_not_found() {
            order(A, "Hamra Bakery", SHOP_A, "PLACED", null);

            assertThatThrownBy(() -> service.view(CHECKOUT, "stranger-sub", false))
                    .isInstanceOf(CheckoutNotFoundException.class);
            verifyNoInteractions(tracking);
        }

        @Test
        @DisplayName("the back office reads any checkout, unscoped")
        void backoffice_reads_all() {
            order(A, "Hamra Bakery", SHOP_A, "PLACED", null);

            assertThat(service.view(CHECKOUT, "backoffice-sub", true).orders()).hasSize(1);
            verify(participants).findByCheckoutId(CHECKOUT);
        }
    }

    @Test
    @DisplayName("is computed at most once every five seconds, however often it is asked for")
    void computed_at_most_every_five_seconds() {
        order(A, "Hamra Bakery", SHOP_A, "PICKED_UP", RIDER);
        riderAt(A, RIDER, SHOP_A, Duration.ofSeconds(5));

        CheckoutView first = view();
        clock.advance(Duration.ofSeconds(3));
        CheckoutView again = view();

        assertThat(again).isSameAs(first);
        verify(tracking, times(1)).sightingFor(any(OrderParticipants.class), any(), anyBoolean());

        clock.advance(Duration.ofSeconds(3));
        CheckoutView later = view();

        assertThat(later).isNotSameAs(first);
        assertThat(later.computedAt()).isEqualTo(clock.instant());
        verify(tracking, times(2)).sightingFor(any(OrderParticipants.class), any(), anyBoolean());
        // The caller is still checked on every request, memo or not.
        verify(participants, times(3)).findByCheckoutIdAndCustomerId(CHECKOUT, CUSTOMER);
    }
}
