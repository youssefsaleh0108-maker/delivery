package com.delivery.tracking.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.within;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyBoolean;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import com.delivery.tracking.domain.OrderParticipants;
import com.delivery.tracking.domain.OrderParticipantsRepository;
import com.delivery.tracking.route.GeoPoint;
import com.delivery.tracking.route.HaversineRouteProvider;
import com.delivery.tracking.route.RouteProviderRegistry;
import com.delivery.tracking.service.EtaService.EtaResult;
import com.delivery.tracking.service.EtaService.Leg;
import com.delivery.tracking.service.EtaService.Reason;
import com.delivery.tracking.service.TrackingService.Position;

/**
 * The single-order ETA when the order's rider holds other orders of the same checkout.
 *
 * <p>Such a rider is not going straight to the door: they still have the siblings' shops to visit,
 * and an estimate that ignored them would be minutes short and would disagree with the checkout
 * map the customer can open beside it. The single-order panel and the map must give one answer.
 */
@DisplayName("an ETA for an order whose rider carries several of the checkout's orders")
class EtaServiceRunTest {

    private static final UUID CHECKOUT = UUID.fromString("c4ec0000-0000-4000-8000-000000000002");
    private static final String CUSTOMER = "customer-sub";
    private static final String RIDER = "rider-sub";

    private static final GeoPoint DOOR = new GeoPoint(33.8981, 35.5214);
    private static final GeoPoint SHOP_A = new GeoPoint(33.8938, 35.5018);
    private static final GeoPoint SHOP_B = new GeoPoint(33.8869, 35.5131);

    private static final UUID A = UUID.fromString("00000000-0000-4000-8000-0000000000a1");
    private static final UUID B = UUID.fromString("00000000-0000-4000-8000-0000000000b1");

    private final List<OrderParticipants> checkout = new ArrayList<>();
    private final Map<UUID, Position> fixes = new HashMap<>();
    private OrderParticipantsRepository participants;
    private EtaService eta;

    @BeforeEach
    void setUp() {
        participants = mock(OrderParticipantsRepository.class);
        TrackingService tracking = mock(TrackingService.class);
        when(participants.findByCheckoutId(CHECKOUT)).thenReturn(checkout);
        when(participants.findById(any())).thenAnswer(call -> checkout.stream()
                .filter(o -> o.getOrderId().equals(call.getArgument(0))).findFirst());
        when(tracking.sightingFor(any(OrderParticipants.class), any(), anyBoolean()))
                .thenAnswer(call -> Optional.ofNullable(
                                fixes.get(call.<OrderParticipants>getArgument(0).getOrderId()))
                        .map(RiderSighting::visible)
                        .orElseGet(() -> RiderSighting.nothing(RiderSighting.State.NO_FIX)));
        RouteProviderRegistry providers = new RouteProviderRegistry(
                List.of(new HaversineRouteProvider(60)), HaversineRouteProvider.NAME);
        eta = new EtaService(tracking, participants, providers, Duration.ofMinutes(5));
    }

    private OrderParticipants order(UUID id, String merchant, GeoPoint shop, String status,
                                    String customer) {
        OrderParticipants order = new OrderParticipants(id, customer, merchant, RIDER, status);
        order.applyRoute(null, shop, DOOR);
        order.applyCheckout(CHECKOUT, merchant);
        checkout.add(order);
        return order;
    }

    private void fixOn(UUID orderId, GeoPoint where, Instant at) {
        fixes.put(orderId, new Position(orderId, RIDER, where.lat(), where.lng(), 5f, at));
    }

    private static double via(GeoPoint... stops) {
        double metres = 0;
        for (int i = 1; i < stops.length; i++) {
            metres += HaversineRouteProvider.distanceMetres(stops[i - 1], stops[i]);
        }
        return metres;
    }

    @Test
    @DisplayName("runs through the sibling's shop still ahead, not straight to the door")
    void the_estimate_includes_the_siblings_shop() {
        OrderParticipants a = order(A, "merchant-a", SHOP_A, "PICKED_UP", CUSTOMER);
        a.stampMilestones("PICKED_UP", Instant.now().minusSeconds(300));
        order(B, "merchant-b", SHOP_B, "READY", CUSTOMER);
        fixOn(A, SHOP_A, Instant.now().minusSeconds(5));

        EtaResult result = eta.estimateFor(A, CUSTOMER, false);

        assertThat(result.available()).isTrue();
        assertThat(result.remainingMetres()).isCloseTo(via(SHOP_A, SHOP_B, DOOR), within(1d));
        // The goods are aboard, but the rider is still heading to a shop.
        assertThat(result.leg()).isEqualTo(Leg.TO_PICKUP);
    }

    /** The customer is on every order of the run, so the freshest fix across it is theirs. */
    @Test
    @DisplayName("uses the rider's latest fix across the run for the customer")
    void the_latest_fix_across_the_run_is_used() {
        OrderParticipants a = order(A, "merchant-a", SHOP_A, "PICKED_UP", CUSTOMER);
        a.stampMilestones("PICKED_UP", Instant.now().minusSeconds(300));
        order(B, "merchant-b", SHOP_B, "READY", CUSTOMER);
        // Old on B, fresh on A: the fresh one is where the rider is.
        fixOn(B, SHOP_B, Instant.now().minusSeconds(200));
        fixOn(A, SHOP_A, Instant.now().minusSeconds(5));

        EtaResult forB = eta.estimateFor(B, CUSTOMER, false);

        assertThat(forB.available()).isTrue();
        assertThat(forB.remainingMetres()).isCloseTo(via(SHOP_A, SHOP_B, DOOR), within(1d));
        assertThat(forB.fixRecordedAt()).isEqualTo(fixes.get(A).recordedAt());
    }

    /**
     * The sibling's merchant is not on the other order, so the gate is never asked about it for
     * them: their estimate is measured from what they may be given, never from the sibling's fix.
     */
    @Test
    @DisplayName("never reads a sibling's fix for a merchant who is not on the sibling")
    void a_merchant_never_reads_the_siblings_fix() {
        OrderParticipants a = order(A, "merchant-a", SHOP_A, "PICKED_UP", CUSTOMER);
        a.stampMilestones("PICKED_UP", Instant.now().minusSeconds(300));
        order(B, "merchant-b", SHOP_B, "READY", CUSTOMER);
        fixOn(B, SHOP_B, Instant.now().minusSeconds(200));
        fixOn(A, SHOP_A, Instant.now().minusSeconds(5));

        EtaResult forB = eta.estimateFor(B, "merchant-b", false);

        assertThat(forB.fixRecordedAt()).isEqualTo(fixes.get(B).recordedAt());
        assertThat(forB.remainingMetres()).isCloseTo(via(SHOP_B, DOOR), within(1d));
    }

    @Test
    @DisplayName("once everything is collected the leg is to the door, and both orders agree")
    void all_collected_goes_to_the_door() {
        OrderParticipants a = order(A, "merchant-a", SHOP_A, "PICKED_UP", CUSTOMER);
        a.stampMilestones("PICKED_UP", Instant.now().minusSeconds(600));
        OrderParticipants b = order(B, "merchant-b", SHOP_B, "PICKED_UP", CUSTOMER);
        b.stampMilestones("PICKED_UP", Instant.now().minusSeconds(120));
        fixOn(B, SHOP_B, Instant.now().minusSeconds(3));

        EtaResult forA = eta.estimateFor(A, CUSTOMER, false);
        EtaResult forB = eta.estimateFor(B, CUSTOMER, false);

        assertThat(forA.leg()).isEqualTo(Leg.TO_DROPOFF);
        assertThat(forA.remainingMetres()).isCloseTo(via(SHOP_B, DOOR), within(1d));
        assertThat(forB.remainingMetres()).isEqualTo(forA.remainingMetres());
    }

    @Test
    @DisplayName("a sibling shop with no pin makes the journey unmeasurable, not shorter")
    void a_pinless_sibling_is_no_destination() {
        OrderParticipants a = order(A, "merchant-a", SHOP_A, "PICKED_UP", CUSTOMER);
        a.stampMilestones("PICKED_UP", Instant.now().minusSeconds(300));
        order(B, "merchant-b", null, "READY", CUSTOMER);
        fixOn(A, SHOP_A, Instant.now().minusSeconds(5));

        EtaResult result = eta.estimateFor(A, CUSTOMER, false);

        assertThat(result.available()).isFalse();
        assertThat(result.reason()).isEqualTo(Reason.NO_DESTINATION);
    }

    /** A finished sibling is not on the way anywhere. */
    @Test
    @DisplayName("a delivered or cancelled sibling is not a stop")
    void a_finished_sibling_is_not_a_stop() {
        order(A, "merchant-a", SHOP_A, "PICKED_UP", CUSTOMER);
        order(B, "merchant-b", SHOP_B, "CANCELLED", CUSTOMER);
        fixOn(A, SHOP_A, Instant.now().minusSeconds(5));

        EtaResult result = eta.estimateFor(A, CUSTOMER, false);

        assertThat(result.leg()).isEqualTo(Leg.TO_DROPOFF);
        assertThat(result.remainingMetres()).isCloseTo(via(SHOP_A, DOOR), within(1d));
    }

    /**
     * A checkout id is a server-generated link, but this projection is fed by messages: a row
     * mislabelled with another customer's checkout must never route this customer's rider.
     */
    @Test
    @DisplayName("another customer's order under the same checkout id is never a stop")
    void only_the_same_customers_siblings_count() {
        order(A, "merchant-a", SHOP_A, "PICKED_UP", CUSTOMER);
        order(B, "merchant-b", SHOP_B, "READY", "someone-else");
        fixOn(A, SHOP_A, Instant.now().minusSeconds(5));

        EtaResult result = eta.estimateFor(A, CUSTOMER, false);

        assertThat(result.leg()).isEqualTo(Leg.TO_DROPOFF);
        assertThat(result.remainingMetres()).isCloseTo(via(SHOP_A, DOOR), within(1d));
    }

    /** A different rider on the sibling makes it somebody else's journey. */
    @Test
    @DisplayName("a sibling carried by another rider is not part of this rider's journey")
    void another_riders_sibling_is_not_a_stop() {
        order(A, "merchant-a", SHOP_A, "PICKED_UP", CUSTOMER);
        OrderParticipants b = new OrderParticipants(B, CUSTOMER, "merchant-b", "rider-2", "READY");
        b.applyRoute(null, SHOP_B, DOOR);
        b.applyCheckout(CHECKOUT, "merchant-b");
        checkout.add(b);
        fixOn(A, SHOP_A, Instant.now().minusSeconds(5));

        assertThat(eta.estimateFor(A, CUSTOMER, false).remainingMetres())
                .isCloseTo(via(SHOP_A, DOOR), within(1d));
        // And the sibling's own estimate never reads this rider's fix.
        assertThat(eta.estimateFor(B, CUSTOMER, false).reason()).isEqualTo(Reason.NO_FIX);
    }

    @Test
    @DisplayName("a stranger still learns nothing, run or not")
    void a_stranger_is_refused() {
        order(A, "merchant-a", SHOP_A, "PICKED_UP", CUSTOMER);
        order(B, "merchant-b", SHOP_B, "READY", CUSTOMER);

        org.assertj.core.api.Assertions.assertThatThrownBy(
                        () -> eta.estimateFor(A, "merchant-b", false))
                .isInstanceOf(TrackingService.TrackingNotFoundException.class);
        // Only the order asked about is ever read for authorisation.
        org.mockito.Mockito.verify(participants, org.mockito.Mockito.never())
                .findByCheckoutId(eq(CHECKOUT));
    }
}
