package com.delivery.tracking.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyBoolean;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
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

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.data.redis.core.StringRedisTemplate;

import com.delivery.tracking.domain.OrderParticipants;
import com.delivery.tracking.domain.OrderParticipantsRepository;
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
import com.delivery.tracking.service.EtaService.Leg;
import com.delivery.tracking.service.EtaService.Reason;
import com.delivery.tracking.service.TrackingService.Position;

/**
 * What a customer's map of a multi-shop checkout shows, and — mostly — what it refuses to show.
 *
 * <p>Every coordinate on that map is one the platform holds, every number on a pickup stop is
 * either a fact (collected, in collection order) or marked as an expectation, and every line ends
 * at a pin. The tests are arranged around those three promises.
 */
@DisplayName("the checkout map")
class CheckoutTrackingServiceTest {

    private static final UUID CHECKOUT = UUID.fromString("c4ec0000-0000-4000-8000-000000000001");
    private static final String CUSTOMER = "customer-sub";
    private static final String RIDER = "rider-1";
    private static final String OTHER_RIDER = "rider-2";

    // Beirut. The door in Mar Mikhael; shops in Hamra (A), Achrafieh (B) and Ras Beirut (C).
    private static final GeoPoint DOOR = new GeoPoint(33.8981, 35.5214);
    private static final GeoPoint SHOP_A = new GeoPoint(33.8938, 35.5018);
    private static final GeoPoint SHOP_B = new GeoPoint(33.8869, 35.5131);
    private static final GeoPoint SHOP_C = new GeoPoint(33.9000, 35.4800);

    private static final UUID A = UUID.fromString("00000000-0000-4000-8000-00000000000a");
    private static final UUID B = UUID.fromString("00000000-0000-4000-8000-00000000000b");
    private static final UUID C = UUID.fromString("00000000-0000-4000-8000-00000000000c");

    // Starts at the real now: the single-order endpoint compared against below reads the real clock.
    private final MutableClock clock =
            new MutableClock(Instant.now().truncatedTo(java.time.temporal.ChronoUnit.SECONDS));
    private final List<OrderParticipants> rows = new ArrayList<>();
    private final Map<UUID, Position> fixes = new HashMap<>();

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

    @BeforeEach
    void setUp() {
        participants = mock(OrderParticipantsRepository.class);
        tracking = mock(TrackingService.class);
        when(participants.findByCheckoutIdAndCustomerId(CHECKOUT, CUSTOMER)).thenReturn(rows);
        when(participants.findByCheckoutId(CHECKOUT)).thenReturn(rows);
        when(tracking.currentPosition(any(UUID.class), any(), anyBoolean()))
                .thenAnswer(call -> Optional.ofNullable(fixes.get(call.<UUID>getArgument(0))));

        // 60 km/h, so kilometres read as minutes.
        RouteProviderRegistry providers = new RouteProviderRegistry(
                List.of(new HaversineRouteProvider(60)), HaversineRouteProvider.NAME);
        eta = new EtaService(tracking, participants, providers, Duration.ofMinutes(5));
        RoutePaths paths = new RoutePaths(providers, mock(StringRedisTemplate.class),
                new com.fasterxml.jackson.databind.ObjectMapper(), Duration.ofHours(24), 150,
                Duration.ofSeconds(60));
        service = new CheckoutTrackingService(participants, tracking, eta, paths,
                Duration.ofMinutes(5), Duration.ofSeconds(5), clock);
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
        order.stampMilestones(at);
        return order;
    }

    private void riderAt(UUID orderId, String rider, GeoPoint where, Duration ago) {
        fixes.put(orderId, new Position(orderId, rider, where.lat(), where.lng(), 5f,
                clock.instant().minus(ago)));
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
            when(participants.findById(A)).thenReturn(Optional.of(rows.get(0)));
            when(participants.findById(B)).thenReturn(Optional.of(rows.get(1)));

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
            b.stampMilestones(clock.instant());

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
            riderAt(A, RIDER, SHOP_C, Duration.ofSeconds(10));
            riderAt(B, OTHER_RIDER, SHOP_C, Duration.ofSeconds(10));

            CheckoutView view = view();

            assertThat(view.orders()).allSatisfy(o -> {
                assertThat(o.stop()).isNull();
                assertThat(o.expected()).isFalse();
            });
            assertThat(view.riders()).hasSize(2).allSatisfy(r -> assertThat(r.run()).isFalse());
            // A leg each: rider → own shop → door.
            assertThat(pathsOf(view, PathKind.RIDER_LEG)).hasSize(2)
                    .allSatisfy(p -> assertThat(p.points()).hasSize(3));
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
            a.stampMilestones(clock.instant().minusSeconds(60));
            order(B, "Achrafieh Pharmacy", SHOP_B, "PREPARING", null);
            riderAt(A, RIDER, DOOR, Duration.ofSeconds(70));

            CheckoutView view = view();

            assertThat(row(view, A).shop()).isNotNull();
            assertThat(row(view, A).completedAt()).isEqualTo(clock.instant().minusSeconds(60));
            assertThat(row(view, A).eta().reason()).isEqualTo(Reason.ORDER_COMPLETE);
            assertThat(view.riders()).isEmpty();
            assertThat(view.paths()).noneMatch(p -> p.orderIds().contains(A));
            // Tracking closed: the delivered order's position is not even read.
            verify(tracking, never()).currentPosition(any(UUID.class), anyString(), anyBoolean());
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
            riderAt(A, RIDER, SHOP_C, Duration.ofSeconds(5));

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
            riderAt(A, RIDER, SHOP_C, Duration.ofSeconds(5));

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
        verify(tracking, times(1)).currentPosition(any(UUID.class), any(), anyBoolean());

        clock.advance(Duration.ofSeconds(3));
        CheckoutView later = view();

        assertThat(later).isNotSameAs(first);
        assertThat(later.computedAt()).isEqualTo(clock.instant());
        verify(tracking, times(2)).currentPosition(any(UUID.class), any(), anyBoolean());
        // The caller is still checked on every request, memo or not.
        verify(participants, times(3)).findByCheckoutIdAndCustomerId(CHECKOUT, CUSTOMER);
    }
}
