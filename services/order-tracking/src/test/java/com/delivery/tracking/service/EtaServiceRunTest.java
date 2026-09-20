package com.delivery.tracking.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.assertj.core.api.Assertions.within;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
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
import org.springframework.data.domain.Pageable;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.ValueOperations;

import com.delivery.tracking.domain.OrderParticipants;
import com.delivery.tracking.domain.OrderParticipantsRepository;
import com.delivery.tracking.domain.TrackingEvent;
import com.delivery.tracking.domain.TrackingEventRepository;
import com.delivery.tracking.route.GeoPoint;
import com.delivery.tracking.route.HaversineRouteProvider;
import com.delivery.tracking.route.RouteProviderRegistry;
import com.delivery.tracking.service.EtaService.EtaResult;
import com.delivery.tracking.service.EtaService.Leg;
import com.delivery.tracking.service.EtaService.Reason;
import com.delivery.tracking.service.PresenceService.LatestFix;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;

/**
 * The single-order ETA when the order's rider holds other orders of the same checkout.
 *
 * <p>Such a rider is not going straight to the door: they still have the siblings' shops to visit,
 * and an estimate that ignored them would be minutes short and would disagree with the checkout
 * map the customer can open beside it. The single-order panel and the map must give one answer —
 * <em>for the people the whole run belongs to</em>. A shop is not one of them: a detour through
 * the customer's other shop would tell it that the customer is buying elsewhere and roughly where,
 * so a shop's order is estimated as if it were alone.
 *
 * <p>The rider-visibility gate is the real one, over an in-memory presence store.
 */
@DisplayName("an ETA for an order whose rider carries several of the checkout's orders")
class EtaServiceRunTest {

    private static final UUID CHECKOUT = UUID.fromString("c4ec0000-0000-4000-8000-000000000002");
    private static final String CUSTOMER = "customer-sub";
    private static final String RIDER = "rider-sub";
    private static final String MERCHANT_A = "merchant-a";
    private static final String MERCHANT_B = "merchant-b";

    private static final GeoPoint DOOR = new GeoPoint(33.8981, 35.5214);
    private static final GeoPoint SHOP_A = new GeoPoint(33.8938, 35.5018);
    private static final GeoPoint SHOP_B = new GeoPoint(33.8869, 35.5131);

    private static final UUID A = UUID.fromString("00000000-0000-4000-8000-0000000000a1");
    private static final UUID B = UUID.fromString("00000000-0000-4000-8000-0000000000b1");

    private final List<OrderParticipants> checkout = new ArrayList<>();
    private final Map<String, LatestFix> latest = new HashMap<>();
    private final Map<UUID, TrackingEvent> orderFixes = new HashMap<>();
    private OrderParticipantsRepository participants;
    private EtaService eta;

    @BeforeEach
    @SuppressWarnings("unchecked")
    void setUp() {
        participants = mock(OrderParticipantsRepository.class);
        when(participants.findByCheckoutId(CHECKOUT)).thenReturn(checkout);
        when(participants.findById(any())).thenAnswer(call -> checkout.stream()
                .filter(o -> o.getOrderId().equals(call.getArgument(0))).findFirst());
        when(participants.otherCustomersDoors(anyString(), anyString(), any())).thenAnswer(call -> {
            String rider = call.getArgument(0);
            String customer = call.getArgument(1);
            Instant finishedSince = call.getArgument(2);
            return checkout.stream()
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
        TrackingService tracking = new TrackingService(events, participants, presence, redis,
                new ObjectMapper().registerModule(new JavaTimeModule()), Duration.ofSeconds(60));

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

    /** The rider's latest fix, reported on {@code orderId}. */
    private void fixOn(UUID orderId, GeoPoint where, Instant at) {
        fixOn(orderId, RIDER, where, at);
    }

    private void fixOn(UUID orderId, String rider, GeoPoint where, Instant at) {
        LatestFix previous = latest.get(rider);
        if (previous == null || !at.isBefore(previous.at())) {
            latest.put(rider, new LatestFix(rider, orderId, where.lat(), where.lng(), 5f, at));
        }
        orderFixes.put(orderId, new TrackingEvent(orderId, rider, where.lat(), where.lng(), 5f,
                at));
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
        OrderParticipants a = order(A, MERCHANT_A, SHOP_A, "PICKED_UP", CUSTOMER);
        a.stampMilestones("PICKED_UP", Instant.now().minusSeconds(300));
        order(B, MERCHANT_B, SHOP_B, "READY", CUSTOMER);
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
        OrderParticipants a = order(A, MERCHANT_A, SHOP_A, "PICKED_UP", CUSTOMER);
        a.stampMilestones("PICKED_UP", Instant.now().minusSeconds(300));
        order(B, MERCHANT_B, SHOP_B, "READY", CUSTOMER);
        // Old on B, fresh on A: the fresh one is where the rider is.
        fixOn(B, SHOP_B, Instant.now().minusSeconds(200));
        fixOn(A, SHOP_A, Instant.now().minusSeconds(5));

        EtaResult forB = eta.estimateFor(B, CUSTOMER, false);

        assertThat(forB.available()).isTrue();
        assertThat(forB.remainingMetres()).isCloseTo(via(SHOP_A, SHOP_B, DOOR), within(1d));
        assertThat(forB.fixRecordedAt()).isEqualTo(latest.get(RIDER).at());
    }

    /**
     * The shop whose goods are aboard asks about its own order. Through the run it would be told
     * the rider is still collecting — from a shop it has no business knowing about — and given a
     * distance that is the detour there and back. Alone: straight to the door.
     */
    @Test
    @DisplayName("gives a merchant the order as if it were the only one")
    void a_merchant_sees_the_order_alone() {
        OrderParticipants a = order(A, MERCHANT_A, SHOP_A, "PICKED_UP", CUSTOMER);
        a.stampMilestones("PICKED_UP", Instant.now().minusSeconds(300));
        order(B, MERCHANT_B, SHOP_B, "READY", CUSTOMER);
        GeoPoint riderAt = new GeoPoint(33.8950, 35.5050);
        fixOn(A, riderAt, Instant.now().minusSeconds(5));

        EtaResult forShop = eta.estimateFor(A, MERCHANT_A, false);

        assertThat(forShop.available()).isTrue();
        assertThat(forShop.leg()).as("their goods are aboard; nobody else's shop is ahead")
                .isEqualTo(Leg.TO_DROPOFF);
        assertThat(forShop.remainingMetres()).isCloseTo(via(riderAt, DOOR), within(1d));
        // The checkout is not even read for them.
        verify(participants, never()).findByCheckoutId(CHECKOUT);

        // Not a metre of the sibling's detour, which is what the customer is told.
        EtaResult forCustomer = eta.estimateFor(A, CUSTOMER, false);
        assertThat(forCustomer.leg()).isEqualTo(Leg.TO_PICKUP);
        assertThat(forCustomer.remainingMetres())
                .isCloseTo(via(riderAt, SHOP_B, DOOR), within(1d));
        assertThat(forShop.remainingMetres()).isLessThan(forCustomer.remainingMetres());
    }

    /**
     * And the sibling's own shop, while the rider's fix is on the other order, is told nothing at
     * all: the gate's rule, which a run must not talk its way around.
     */
    @Test
    @DisplayName("tells a sibling's merchant nothing while the fix is on the other order")
    void the_siblings_merchant_is_told_nothing() {
        OrderParticipants a = order(A, MERCHANT_A, SHOP_A, "PICKED_UP", CUSTOMER);
        a.stampMilestones("PICKED_UP", Instant.now().minusSeconds(300));
        order(B, MERCHANT_B, SHOP_B, "READY", CUSTOMER);
        fixOn(A, SHOP_A, Instant.now().minusSeconds(5));

        EtaResult forSiblingsShop = eta.estimateFor(B, MERCHANT_B, false);

        assertThat(forSiblingsShop.available()).isFalse();
        assertThat(forSiblingsShop.reason()).isEqualTo(Reason.RIDER_ON_ANOTHER_DELIVERY);
        assertThat(forSiblingsShop.remainingMetres()).isNull();
        assertThat(forSiblingsShop.remainingSeconds()).isNull();
        assertThat(forSiblingsShop.fixRecordedAt()).isNull();
    }

    /** The rider carrying the run sees it whole: it is their own journey. */
    @Test
    @DisplayName("gives the rider the whole run")
    void the_rider_sees_the_run() {
        OrderParticipants a = order(A, MERCHANT_A, SHOP_A, "PICKED_UP", CUSTOMER);
        a.stampMilestones("PICKED_UP", Instant.now().minusSeconds(300));
        order(B, MERCHANT_B, SHOP_B, "READY", CUSTOMER);
        fixOn(A, SHOP_A, Instant.now().minusSeconds(5));

        EtaResult forRider = eta.estimateFor(A, RIDER, false);

        assertThat(forRider.leg()).isEqualTo(Leg.TO_PICKUP);
        assertThat(forRider.remainingMetres()).isCloseTo(via(SHOP_A, SHOP_B, DOOR), within(1d));
    }

    @Test
    @DisplayName("once everything is collected the leg is to the door, and both orders agree")
    void all_collected_goes_to_the_door() {
        OrderParticipants a = order(A, MERCHANT_A, SHOP_A, "PICKED_UP", CUSTOMER);
        a.stampMilestones("PICKED_UP", Instant.now().minusSeconds(600));
        OrderParticipants b = order(B, MERCHANT_B, SHOP_B, "PICKED_UP", CUSTOMER);
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
        OrderParticipants a = order(A, MERCHANT_A, SHOP_A, "PICKED_UP", CUSTOMER);
        a.stampMilestones("PICKED_UP", Instant.now().minusSeconds(300));
        order(B, MERCHANT_B, null, "READY", CUSTOMER);
        fixOn(A, SHOP_A, Instant.now().minusSeconds(5));

        EtaResult result = eta.estimateFor(A, CUSTOMER, false);

        assertThat(result.available()).isFalse();
        assertThat(result.reason()).isEqualTo(Reason.NO_DESTINATION);
    }

    /** A finished sibling is not on the way anywhere. */
    @Test
    @DisplayName("a delivered or cancelled sibling is not a stop")
    void a_finished_sibling_is_not_a_stop() {
        order(A, MERCHANT_A, SHOP_A, "PICKED_UP", CUSTOMER);
        order(B, MERCHANT_B, SHOP_B, "CANCELLED", CUSTOMER);
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
        order(A, MERCHANT_A, SHOP_A, "PICKED_UP", CUSTOMER);
        order(B, MERCHANT_B, SHOP_B, "READY", "someone-else");
        fixOn(A, SHOP_A, Instant.now().minusSeconds(5));

        EtaResult result = eta.estimateFor(A, CUSTOMER, false);

        assertThat(result.leg()).isEqualTo(Leg.TO_DROPOFF);
        assertThat(result.remainingMetres()).isCloseTo(via(SHOP_A, DOOR), within(1d));
    }

    /** A different rider on the sibling makes it somebody else's journey. */
    @Test
    @DisplayName("a sibling carried by another rider is not part of this rider's journey")
    void another_riders_sibling_is_not_a_stop() {
        order(A, MERCHANT_A, SHOP_A, "PICKED_UP", CUSTOMER);
        OrderParticipants b = new OrderParticipants(B, CUSTOMER, MERCHANT_B, "rider-2", "READY");
        b.applyRoute(null, SHOP_B, DOOR);
        b.applyCheckout(CHECKOUT, MERCHANT_B);
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
        order(A, MERCHANT_A, SHOP_A, "PICKED_UP", CUSTOMER);
        order(B, MERCHANT_B, SHOP_B, "READY", CUSTOMER);

        assertThatThrownBy(() -> eta.estimateFor(A, "stranger-sub", false))
                .isInstanceOf(TrackingService.TrackingNotFoundException.class);
        // Only the order asked about is ever read for authorisation.
        verify(participants, never()).findByCheckoutId(CHECKOUT);
    }
}
