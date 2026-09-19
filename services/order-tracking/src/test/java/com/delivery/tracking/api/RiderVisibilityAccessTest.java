package com.delivery.tracking.api;

import static org.assertj.core.api.Assertions.assertThat;
import static org.hamcrest.Matchers.closeTo;
import static org.hamcrest.Matchers.hasSize;
import static org.hamcrest.Matchers.notNullValue;
import static org.hamcrest.Matchers.nullValue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyDouble;
import static org.mockito.ArgumentMatchers.anyFloat;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.data.domain.Pageable;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.ValueOperations;
import org.springframework.http.MediaType;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import com.delivery.tracking.domain.CarrierMembershipRepository;
import com.delivery.tracking.domain.DutySessionRepository;
import com.delivery.tracking.domain.OrderParticipants;
import com.delivery.tracking.domain.OrderParticipantsRepository;
import com.delivery.tracking.domain.RiderDutyEventRepository;
import com.delivery.tracking.domain.RiderPresence;
import com.delivery.tracking.domain.RiderPresenceRepository;
import com.delivery.tracking.domain.TrackingEvent;
import com.delivery.tracking.domain.TrackingEventRepository;
import com.delivery.tracking.route.GeoPoint;
import com.delivery.tracking.route.HaversineRouteProvider;
import com.delivery.tracking.route.RouteProviderRegistry;
import com.delivery.tracking.service.CarrierScopeResolver;
import com.delivery.tracking.service.DutySessionService;
import com.delivery.tracking.service.EtaService;
import com.delivery.tracking.service.FixPolicy;
import com.delivery.tracking.service.FleetMembershipGuard;
import com.delivery.tracking.service.PresenceService;
import com.delivery.tracking.service.TrackingService;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;

/**
 * Who sees where a rider is, end to end through the routes.
 *
 * <p>Real positions reached read paths built for the old simulated ones: a READY order's trail
 * started at the claim — often the rider's home — every fix went on every order the rider held, so
 * one customer's map showed the way to another's door, and the shop kept watching after pickup.
 * Every case here drives the real controllers, services and fix policy: the rider reports through
 * {@code POST .../ping}, and each audience reads the live position, the sighting, the ETA and the
 * trail. Only the stores are in memory — Postgres and Redis replaced by maps — and the fix policy
 * lets the rider move as fast as a scenario needs (its speed limit has its own suite).
 */
@DisplayName("who sees where a rider is")
class RiderVisibilityAccessTest {

    private static final String RIDER = "rider-sub";
    private static final String CUSTOMER_A = "customer-a";
    private static final String CUSTOMER_B = "customer-b";
    private static final String SHOP_1 = "merchant-1";
    private static final String SHOP_2 = "merchant-2";
    private static final String BACKOFFICE = "backoffice-sub";

    // Downtown Beirut: two shops, two customers' doors, and the rider's home.
    private static final double BASE_LAT = 33.8938;
    private static final double BASE_LNG = 35.5018;
    private static final double METRES_PER_DEGREE_LAT = 111_195.08;
    private static final double METRES_PER_DEGREE_LNG =
            METRES_PER_DEGREE_LAT * Math.cos(Math.toRadians(BASE_LAT));

    private static final GeoPoint SHOP_1_PIN = at(0, 0);
    private static final GeoPoint SHOP_2_PIN = at(1_500, 0);
    private static final GeoPoint DOOR_A = at(-600, -500);
    private static final GeoPoint DOOR_B = at(2_500, 1_500);
    private static final GeoPoint HOME = at(0, 5_000);
    private static final GeoPoint NEAR_SHOP_1 = at(0, 1_500);
    private static final GeoPoint ON_THE_WAY_TO_A = at(-300, -250);
    private static final GeoPoint LONDON = new GeoPoint(51.5074, -0.1278);

    /** A point {@code north} and {@code east} metres from the first shop. */
    private static GeoPoint at(double north, double east) {
        return new GeoPoint(BASE_LAT + north / METRES_PER_DEGREE_LAT,
                BASE_LNG + east / METRES_PER_DEGREE_LNG);
    }

    private final Map<UUID, OrderParticipants> orders = new HashMap<>();
    private final List<TrackingEvent> trail = new ArrayList<>();
    private final Map<String, RiderPresence> presenceRows = new HashMap<>();
    private final Map<String, String> redisStore = new HashMap<>();
    private final List<Object> pushed = new ArrayList<>();

    private MockMvc mvc;

    /** When the rider's phone took the next fix: six seconds apart, inside the last few minutes. */
    private Instant clock;

    @BeforeEach
    void setUp() {
        platform(true);
    }

    @AfterEach
    void tearDown() {
        SecurityContextHolder.clearContext();
    }

    /** Wires the real services over in-memory stores. */
    @SuppressWarnings("unchecked")
    private void platform(boolean serviceAreaEnforced) {
        clock = Instant.now().minus(Duration.ofMinutes(4));

        OrderParticipantsRepository participants = mock(OrderParticipantsRepository.class);
        when(participants.findById(any())).thenAnswer(
                call -> Optional.ofNullable(orders.get(call.<UUID>getArgument(0))));
        when(participants.riderHasLiveOrder(anyString())).thenAnswer(call ->
                orders.values().stream().anyMatch(o ->
                        call.getArgument(0).equals(o.getRiderId()) && o.isTrackable()));
        when(participants.otherCustomersDoors(anyString(), anyString(), any())).thenAnswer(call -> {
            String rider = call.getArgument(0);
            String customer = call.getArgument(1);
            Instant finishedSince = call.getArgument(2);
            return orders.values().stream()
                    .filter(o -> rider.equals(o.getRiderId()))
                    .filter(o -> !customer.equals(o.getCustomerId()))
                    .filter(o -> o.dropoff().isPresent())
                    .filter(o -> o.isTrackable() || (o.getCompletedAt() != null
                            && !o.getCompletedAt().isBefore(finishedSince)))
                    .toList();
        });

        TrackingEventRepository events = mock(TrackingEventRepository.class);
        when(events.save(any(TrackingEvent.class))).thenAnswer(call -> {
            trail.add(call.getArgument(0));
            return call.getArgument(0);
        });
        when(events.findByOrderIdOrderByRecordedAtAsc(any())).thenAnswer(call ->
                storedTrail(call.getArgument(0), Instant.MIN));
        when(events.findByOrderIdAndRecordedAtGreaterThanEqualOrderByRecordedAtAsc(any(), any()))
                .thenAnswer(call -> storedTrail(call.getArgument(0), call.getArgument(1)));
        when(events.findLatestForOrder(any(), any(Pageable.class))).thenAnswer(call -> {
            List<TrackingEvent> all = storedTrail(call.getArgument(0), Instant.MIN);
            return all.isEmpty() ? List.of() : List.of(all.get(all.size() - 1));
        });

        RiderPresenceRepository presenceRepo = mock(RiderPresenceRepository.class);
        when(presenceRepo.findById(anyString())).thenAnswer(
                call -> Optional.ofNullable(presenceRows.get(call.<String>getArgument(0))));
        when(presenceRepo.save(any(RiderPresence.class))).thenAnswer(call -> {
            RiderPresence row = call.getArgument(0);
            presenceRows.put(row.getRiderId(), row);
            return row;
        });
        when(presenceRepo.touchIfDue(anyString(), anyDouble(), anyDouble(), any(), any(), any()))
                .thenAnswer(call -> {
                    RiderPresence row = presenceRows.get(call.<String>getArgument(0));
                    Instant at = call.getArgument(4);
                    Instant staleBefore = call.getArgument(5);
                    if (row == null || (row.getLastSeenAt() != null
                            && !row.getLastSeenAt().isBefore(staleBefore))) {
                        return 0;
                    }
                    row.sighted(call.getArgument(1), call.getArgument(2), call.getArgument(3), at);
                    return 1;
                });

        StringRedisTemplate redis = mock(StringRedisTemplate.class);
        ValueOperations<String, String> values = mock(ValueOperations.class);
        when(redis.opsForValue()).thenReturn(values);
        when(values.get(anyString())).thenAnswer(call -> redisStore.get(call.<String>getArgument(0)));
        doAnswer(call -> {
            redisStore.put(call.getArgument(0), call.getArgument(1));
            return null;
        }).when(values).set(anyString(), anyString(), any(Duration.class));
        when(redis.delete(anyString())).thenAnswer(
                call -> redisStore.remove(call.<String>getArgument(0)) != null);

        FleetMembershipGuard fleetGuard = mock(FleetMembershipGuard.class);
        when(fleetGuard.isOnCallersFleet(anyString(), anyString())).thenReturn(true);
        when(fleetGuard.retainCallersFleet(anyString(), any(), any()))
                .thenAnswer(call -> List.copyOf((java.util.Collection<?>) call.getArgument(1)));
        CarrierMembershipRepository memberships = mock(CarrierMembershipRepository.class);
        when(memberships.findById(anyString())).thenReturn(Optional.empty());
        CarrierScopeResolver carrierScope = mock(CarrierScopeResolver.class);
        when(carrierScope.scopeFor(anyString())).thenReturn(Optional.empty());

        // The shipped limits, except that a rider may cover any distance and a fix may be minutes
        // old: the scenarios below move the rider across Beirut in seconds, and the speed and age
        // limits are FixPolicyTest's.
        FixPolicy policy = new FixPolicy(100f, Duration.ofMinutes(10), Duration.ofSeconds(30),
                1_000_000, Duration.ofMinutes(5), Duration.ofSeconds(5), serviceAreaEnforced,
                FixPolicy.LEBANON.minLat(), FixPolicy.LEBANON.maxLat(),
                FixPolicy.LEBANON.minLng(), FixPolicy.LEBANON.maxLng());

        ObjectMapper json = new ObjectMapper().registerModule(new JavaTimeModule());
        PresenceService presence = new PresenceService(presenceRepo,
                mock(RiderDutyEventRepository.class), mock(DutySessionRepository.class),
                memberships, carrierScope, participants, redis, json, Duration.ofMinutes(2),
                Duration.ofSeconds(30), fleetGuard, policy);
        TrackingService tracking = new TrackingService(events, participants, presence, redis, json,
                Duration.ofSeconds(60));
        EtaService eta = new EtaService(tracking, participants, new RouteProviderRegistry(
                List.of(new HaversineRouteProvider(18)), HaversineRouteProvider.NAME),
                Duration.ofMinutes(5));

        SimpMessagingTemplate live = mock(SimpMessagingTemplate.class);
        doAnswer(call -> pushed.add(call.getArgument(1)))
                .when(live).convertAndSend(anyString(), any(Object.class));

        mvc = MockMvcBuilders.standaloneSetup(
                        new TrackingController(tracking, eta, live),
                        new RiderPresenceController(presence, mock(DutySessionService.class)))
                .setControllerAdvice(new PingProblems())
                .build();
    }

    private List<TrackingEvent> storedTrail(UUID orderId, Instant from) {
        return trail.stream()
                .filter(e -> e.getOrderId().equals(orderId))
                .filter(e -> !e.getRecordedAt().isBefore(from))
                .sorted(Comparator.comparing(TrackingEvent::getRecordedAt))
                .toList();
    }

    // ------------------------------------------------------------------------------ the world

    /** An order held by the rider, from one shop to one door. */
    private UUID order(String customer, String shop, GeoPoint shopPin, GeoPoint door,
                       String status) {
        UUID id = UUID.randomUUID();
        OrderParticipants order = new OrderParticipants(id, customer, shop, RIDER, status);
        order.applyRoute(null, shopPin, door);
        if ("PICKED_UP".equals(status)) {
            order.stampMilestones(status, clock);
        }
        orders.put(id, order);
        return id;
    }

    /** The rider collects: the projection learns PICKED_UP, stamped at the phone's clock. */
    private void pickUp(UUID orderId) {
        OrderParticipants order = orders.get(orderId);
        order.apply(RIDER, "PICKED_UP");
        order.stampMilestones("PICKED_UP", clock);
    }

    private void deliver(UUID orderId) {
        OrderParticipants order = orders.get(orderId);
        order.apply(RIDER, "DELIVERED");
        order.stampMilestones("DELIVERED", clock);
    }

    private Instant nextFixTime() {
        clock = clock.plusSeconds(6);
        return clock;
    }

    private static void signedInAs(String subject, String... roles) {
        Jwt jwt = Jwt.withTokenValue("token").header("alg", "none").subject(subject).build();
        List<GrantedAuthority> authorities = Arrays.stream(roles)
                .<GrantedAuthority>map(role -> new SimpleGrantedAuthority("ROLE_" + role))
                .toList();
        SecurityContextHolder.getContext().setAuthentication(
                new JwtAuthenticationToken(jwt, authorities));
    }

    /** The rider's phone reports a fix taken six seconds after the last, on one order. */
    private ResultActions riderReports(UUID orderId, GeoPoint where) throws Exception {
        return riderReports(orderId, where, nextFixTime());
    }

    private ResultActions riderReports(UUID orderId, GeoPoint where, Instant takenAt)
            throws Exception {
        signedInAs(RIDER, "DELIVERY");
        String time = takenAt == null ? "" : ",\"recordedAt\":\"" + takenAt + "\"";
        return mvc.perform(post("/api/tracking/orders/" + orderId + "/ping")
                .contentType(MediaType.APPLICATION_JSON)
                .content(String.format(Locale.ROOT, "{\"lat\":%.7f,\"lng\":%.7f,\"accuracyM\":6%s}",
                        where.lat(), where.lng(), time)));
    }

    private ResultActions read(String who, String path) throws Exception {
        if (BACKOFFICE.equals(who)) {
            signedInAs(who, "BACKOFFICE");
        } else {
            signedInAs(who, "CUSTOMER", "MERCHANT");
        }
        return mvc.perform(get(path));
    }

    private ResultActions position(String who, UUID orderId) throws Exception {
        return read(who, "/api/tracking/orders/" + orderId);
    }

    private ResultActions sighting(String who, UUID orderId) throws Exception {
        return read(who, "/api/tracking/orders/" + orderId + "/rider");
    }

    private ResultActions eta(String who, UUID orderId) throws Exception {
        return read(who, "/api/tracking/orders/" + orderId + "/eta");
    }

    private ResultActions trailOf(String who, UUID orderId) throws Exception {
        return read(who, "/api/tracking/orders/" + orderId + "/history");
    }

    private static void seenAt(ResultActions result, GeoPoint where) throws Exception {
        result.andExpect(status().isOk())
                .andExpect(jsonPath("$.lat", closeTo(where.lat(), 1e-6)))
                .andExpect(jsonPath("$.lng", closeTo(where.lng(), 1e-6)));
    }

    private void told(String who, UUID orderId, String state) throws Exception {
        sighting(who, orderId)
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.state").value(state))
                .andExpect(jsonPath("$.position").value(nullValue()));
        position(who, orderId).andExpect(status().isNoContent());
    }

    private TrackingController.LiveFrame lastPush() {
        assertThat(pushed).isNotEmpty();
        return (TrackingController.LiveFrame) pushed.get(pushed.size() - 1);
    }

    // -------------------------------------------------------------------------------- cases

    @Nested
    @DisplayName("before pickup")
    class BeforePickup {

        /**
         * The claim happened at home. Neither the customer nor the shop is shown where that is —
         * "on the way to the shop", with an estimate — and nothing of it is kept as a trail.
         */
        @Test
        void far_from_the_shop_the_customer_and_the_shop_get_a_time_but_no_position()
                throws Exception {
            UUID order = order(CUSTOMER_A, SHOP_1, SHOP_1_PIN, DOOR_A, "READY");

            riderReports(order, HOME).andExpect(status().isAccepted());

            for (String who : List.of(CUSTOMER_A, SHOP_1)) {
                told(who, order, "HEADING_TO_SHOP");
                eta(who, order)
                        .andExpect(jsonPath("$.available").value(true))
                        .andExpect(jsonPath("$.leg").value("TO_PICKUP"))
                        .andExpect(jsonPath("$.remainingMetres", notNullValue()));
                trailOf(who, order).andExpect(jsonPath("$", hasSize(0)));
            }
            assertThat(trail).as("a READY fix never goes on the trail").isEmpty();
            assertThat(pushed).as("nor out on the customer's live topic").isEmpty();
        }

        /** Within two kilometres of the shop both see the rider — the dot, still no trail. */
        @Test
        void near_the_shop_both_see_the_rider_move_but_no_trail_is_kept() throws Exception {
            UUID order = order(CUSTOMER_A, SHOP_1, SHOP_1_PIN, DOOR_A, "READY");

            riderReports(order, HOME);
            riderReports(order, NEAR_SHOP_1).andExpect(status().isAccepted());

            for (String who : List.of(CUSTOMER_A, SHOP_1)) {
                seenAt(position(who, order), NEAR_SHOP_1);
                sighting(who, order).andExpect(jsonPath("$.state").value("VISIBLE"));
                trailOf(who, order).andExpect(jsonPath("$", hasSize(0)));
            }
            assertThat(trail).isEmpty();
            assertThat(lastPush().onTrail()).as("the dot moves; no line is drawn through it")
                    .isFalse();
        }

        /** No shop pin to measure two kilometres from: withheld rather than guessed. */
        @Test
        void with_no_shop_pin_the_rider_is_not_shown() throws Exception {
            UUID order = order(CUSTOMER_A, SHOP_1, null, DOOR_A, "READY");

            riderReports(order, NEAR_SHOP_1);

            told(CUSTOMER_A, order, "HEADING_TO_SHOP");
        }
    }

    @Nested
    @DisplayName("after pickup")
    class AfterPickup {

        /**
         * The customer's trail starts at the collection. A point from before it — kept by an
         * older build that put READY fixes on the trail — is not theirs to see; the back office's
         * trail keeps everything.
         */
        @Test
        void the_customer_sees_the_trail_from_the_moment_of_collection() throws Exception {
            UUID order = order(CUSTOMER_A, SHOP_1, SHOP_1_PIN, DOOR_A, "READY");
            trail.add(new TrackingEvent(order, RIDER, HOME.lat(), HOME.lng(), 6f,
                    nextFixTime()));
            riderReports(order, SHOP_1_PIN);
            nextFixTime();
            pickUp(order);

            riderReports(order, ON_THE_WAY_TO_A).andExpect(status().isAccepted());

            seenAt(position(CUSTOMER_A, order), ON_THE_WAY_TO_A);
            trailOf(CUSTOMER_A, order)
                    .andExpect(jsonPath("$", hasSize(1)))
                    .andExpect(jsonPath("$[0].lat", closeTo(ON_THE_WAY_TO_A.lat(), 1e-6)));
            trailOf(BACKOFFICE, order).andExpect(jsonPath("$", hasSize(2)));
            assertThat(lastPush().onTrail()).isTrue();
        }

        /** The shop sees the rider only until pickup: after it, a time and no position or trail. */
        @Test
        void the_shop_loses_sight_of_the_rider_at_pickup() throws Exception {
            UUID order = order(CUSTOMER_A, SHOP_1, SHOP_1_PIN, DOOR_A, "READY");
            riderReports(order, SHOP_1_PIN);
            seenAt(position(SHOP_1, order), SHOP_1_PIN);

            pickUp(order);
            riderReports(order, ON_THE_WAY_TO_A);

            told(SHOP_1, order, "AFTER_PICKUP");
            eta(SHOP_1, order)
                    .andExpect(jsonPath("$.available").value(true))
                    .andExpect(jsonPath("$.leg").value("TO_DROPOFF"));
            trailOf(SHOP_1, order).andExpect(jsonPath("$", hasSize(0)));
            // The customer, meanwhile, follows the rider and the line.
            seenAt(position(CUSTOMER_A, order), ON_THE_WAY_TO_A);
            trailOf(CUSTOMER_A, order).andExpect(jsonPath("$", hasSize(1)));
        }
    }

    @Nested
    @DisplayName("after delivery")
    class AfterDelivery {

        @Test
        void the_customer_sees_nothing_any_more_and_the_back_office_keeps_the_record()
                throws Exception {
            UUID order = order(CUSTOMER_A, SHOP_1, SHOP_1_PIN, DOOR_A, "PICKED_UP");
            riderReports(order, ON_THE_WAY_TO_A);
            riderReports(order, DOOR_A);
            deliver(order);

            told(CUSTOMER_A, order, "CLOSED");
            trailOf(CUSTOMER_A, order).andExpect(jsonPath("$", hasSize(0)));
            eta(CUSTOMER_A, order)
                    .andExpect(jsonPath("$.available").value(false))
                    .andExpect(jsonPath("$.reason").value("ORDER_COMPLETE"));

            seenAt(position(BACKOFFICE, order), DOOR_A);
            trailOf(BACKOFFICE, order).andExpect(jsonPath("$", hasSize(2)));

            riderReports(order, DOOR_A).andExpect(status().isConflict());
        }
    }

    @Nested
    @DisplayName("a rider carrying two customers' orders")
    class TwoCustomers {

        /**
         * The rider's latest fix went on B's order: A is told the rider is on another delivery,
         * and given nothing that points at B's stop — no position, no trail (though A's order has
         * one), no distance, no time, not even when the fix was taken.
         */
        @Test
        void the_customer_whose_leg_is_not_active_is_told_and_shown_nothing() throws Exception {
            UUID forA = order(CUSTOMER_A, SHOP_1, SHOP_1_PIN, DOOR_A, "PICKED_UP");
            UUID forB = order(CUSTOMER_B, SHOP_2, SHOP_2_PIN, DOOR_B, "PICKED_UP");
            riderReports(forA, ON_THE_WAY_TO_A);
            seenAt(position(CUSTOMER_A, forA), ON_THE_WAY_TO_A);
            told(CUSTOMER_B, forB, "ON_ANOTHER_DELIVERY");

            GeoPoint towardsB = at(2_000, 1_000);
            riderReports(forB, towardsB);

            told(CUSTOMER_A, forA, "ON_ANOTHER_DELIVERY");
            trailOf(CUSTOMER_A, forA).andExpect(jsonPath("$", hasSize(0)));
            eta(CUSTOMER_A, forA)
                    .andExpect(jsonPath("$.available").value(false))
                    .andExpect(jsonPath("$.reason").value("RIDER_ON_ANOTHER_DELIVERY"))
                    .andExpect(jsonPath("$.remainingMetres").value(nullValue()))
                    .andExpect(jsonPath("$.remainingSeconds").value(nullValue()))
                    .andExpect(jsonPath("$.estimatedArrival").value(nullValue()))
                    .andExpect(jsonPath("$.fixRecordedAt").value(nullValue()));
            // B follows the rider, and the shop of A's order has nothing either.
            seenAt(position(CUSTOMER_B, forB), towardsB);
            told(SHOP_1, forA, "ON_ANOTHER_DELIVERY");
            // The back office still reads A's order's own last position.
            seenAt(position(BACKOFFICE, forA), ON_THE_WAY_TO_A);
        }
    }

    @Nested
    @DisplayName("one customer's two orders on one rider")
    class OneCustomerTwoOrders {

        /** A multi-shop basket: whichever of the customer's orders the fix went on, they see it. */
        @Test
        void the_customer_sees_the_rider_on_either_of_their_orders() throws Exception {
            UUID first = order(CUSTOMER_A, SHOP_1, SHOP_1_PIN, DOOR_A, "PICKED_UP");
            UUID second = order(CUSTOMER_A, SHOP_2, SHOP_2_PIN, DOOR_A, "PICKED_UP");

            riderReports(second, ON_THE_WAY_TO_A);

            seenAt(position(CUSTOMER_A, first), ON_THE_WAY_TO_A);
            sighting(CUSTOMER_A, first).andExpect(jsonPath("$.state").value("VISIBLE"));
            eta(CUSTOMER_A, first).andExpect(jsonPath("$.available").value(true));
        }

        /**
         * But the shop of one of them is never shown the rider on the other: it would follow the
         * rider to the customer's other shop.
         */
        @Test
        void the_shop_of_one_does_not_follow_the_rider_to_the_other_shop() throws Exception {
            UUID first = order(CUSTOMER_A, SHOP_1, SHOP_1_PIN, DOOR_A, "READY");
            UUID second = order(CUSTOMER_A, SHOP_2, SHOP_2_PIN, DOOR_A, "READY");

            riderReports(second, at(700, 0));

            told(SHOP_1, first, "ON_ANOTHER_DELIVERY");
            seenAt(position(SHOP_2, second), at(700, 0));
            seenAt(position(CUSTOMER_A, first), at(700, 0));
        }
    }

    @Nested
    @DisplayName("at another customer's door")
    class HandOver {

        /**
         * B's delivery done, the leg switches to A — and the first fixes on A's order are still at
         * B's door. Within 300 m of it, for 30 minutes after, A is told the rider is on another
         * delivery, nothing is pushed, and those points never join A's trail.
         */
        @Test
        void the_next_customer_is_not_shown_the_rider_at_the_last_ones_door() throws Exception {
            UUID forA = order(CUSTOMER_A, SHOP_1, SHOP_1_PIN, DOOR_A, "PICKED_UP");
            UUID forB = order(CUSTOMER_B, SHOP_2, SHOP_2_PIN, DOOR_B, "PICKED_UP");
            riderReports(forB, DOOR_B);
            deliver(forB);
            int pushesBefore = pushed.size();

            GeoPoint stillAtB = at(2_500 + 60, 1_500);
            riderReports(forA, stillAtB).andExpect(status().isAccepted());

            told(CUSTOMER_A, forA, "ON_ANOTHER_DELIVERY");
            eta(CUSTOMER_A, forA)
                    .andExpect(jsonPath("$.reason").value("RIDER_ON_ANOTHER_DELIVERY"));
            assertThat(pushed).as("nothing pushed from B's door").hasSize(pushesBefore);

            GeoPoint away = at(1_500, 1_500);
            riderReports(forA, away);

            seenAt(position(CUSTOMER_A, forA), away);
            trailOf(CUSTOMER_A, forA)
                    .andExpect(jsonPath("$", hasSize(1)))
                    .andExpect(jsonPath("$[0].lat", closeTo(away.lat(), 1e-6)));
            // The record keeps both; only the customer's view leaves the door out.
            trailOf(BACKOFFICE, forA).andExpect(jsonPath("$", hasSize(2)));
        }

        /** While B's order is still in the rider's hands, its door counts all the same. */
        @Test
        void a_door_still_to_be_delivered_to_counts_too() throws Exception {
            UUID forA = order(CUSTOMER_A, SHOP_1, SHOP_1_PIN, DOOR_A, "PICKED_UP");
            order(CUSTOMER_B, SHOP_2, SHOP_2_PIN, DOOR_B, "PICKED_UP");

            riderReports(forA, at(2_500 - 100, 1_500));

            told(CUSTOMER_A, forA, "ON_ANOTHER_DELIVERY");
        }

        /** A customer's own door never counts against them. */
        @Test
        void the_customers_own_door_never_counts() throws Exception {
            UUID delivered = order(CUSTOMER_A, SHOP_1, SHOP_1_PIN, DOOR_A, "PICKED_UP");
            UUID stillComing = order(CUSTOMER_A, SHOP_2, SHOP_2_PIN, DOOR_A, "PICKED_UP");
            riderReports(delivered, DOOR_A);
            deliver(delivered);

            riderReports(stillComing, DOOR_A);

            seenAt(position(CUSTOMER_A, stillComing), DOOR_A);
        }
    }

    @Nested
    @DisplayName("what a report must be")
    class Reports {

        @Test
        void a_report_without_a_fix_time_is_refused_and_leaves_nothing() throws Exception {
            UUID order = order(CUSTOMER_A, SHOP_1, SHOP_1_PIN, DOOR_A, "PICKED_UP");

            riderReports(order, ON_THE_WAY_TO_A, null)
                    .andExpect(status().isUnprocessableEntity())
                    .andExpect(jsonPath("$.reason").value("FIX_TIME_MISSING"));

            assertThat(trail).isEmpty();
            assertThat(pushed).isEmpty();
            told(CUSTOMER_A, order, "NO_FIX");
        }

        /** The old simulator's London, where the service area is enforced — dev's default off. */
        @Test
        void a_report_from_london_is_refused_where_the_service_area_is_enforced() throws Exception {
            UUID order = order(CUSTOMER_A, SHOP_1, SHOP_1_PIN, DOOR_A, "PICKED_UP");

            riderReports(order, LONDON)
                    .andExpect(status().isUnprocessableEntity())
                    .andExpect(jsonPath("$.reason").value("OUTSIDE_SERVICE_AREA"));

            assertThat(trail).isEmpty();
        }

        @Test
        void and_accepted_where_it_is_not_as_in_dev() throws Exception {
            platform(false);
            UUID order = order(CUSTOMER_A, SHOP_1, SHOP_1_PIN, DOOR_A, "PICKED_UP");

            riderReports(order, LONDON).andExpect(status().isAccepted());

            assertThat(trail).hasSize(1);
        }

        /**
         * The rate floor: under five seconds after the last accepted fix, a report is answered 202
         * — the app must not count it as a failure — and is neither stored nor pushed. So is one
         * dated the same as the last.
         */
        @Test
        void a_report_under_five_seconds_after_the_last_is_accepted_but_neither_kept_nor_pushed()
                throws Exception {
            UUID order = order(CUSTOMER_A, SHOP_1, SHOP_1_PIN, DOOR_A, "PICKED_UP");
            Instant first = nextFixTime();
            riderReports(order, ON_THE_WAY_TO_A, first).andExpect(status().isAccepted());
            assertThat(trail).hasSize(1);
            assertThat(pushed).hasSize(1);

            riderReports(order, at(-310, -250), first.plusSeconds(3))
                    .andExpect(status().isAccepted());
            riderReports(order, at(-310, -250), first).andExpect(status().isAccepted());

            assertThat(trail).hasSize(1);
            assertThat(pushed).hasSize(1);
            seenAt(position(CUSTOMER_A, order), ON_THE_WAY_TO_A);

            riderReports(order, at(-320, -250), first.plusSeconds(6))
                    .andExpect(status().isAccepted());

            assertThat(trail).hasSize(2);
            assertThat(pushed).hasSize(2);
        }

        /** A stranger's reads are refused as if the order did not exist, as before. */
        @Test
        void a_stranger_is_told_nothing() throws Exception {
            UUID order = order(CUSTOMER_A, SHOP_1, SHOP_1_PIN, DOOR_A, "PICKED_UP");
            riderReports(order, ON_THE_WAY_TO_A);

            for (String path : List.of("", "/rider", "/eta", "/history")) {
                read("stranger-sub", "/api/tracking/orders/" + order + path)
                        .andExpect(status().isNotFound());
            }
        }
    }

    @Nested
    @DisplayName("the back office")
    class BackOffice {

        /** Unchanged: the order's own latest position and its whole trail, whatever the rules
         *  withhold from the customer and the shop. */
        @Test
        void sees_every_orders_own_position_and_whole_trail() throws Exception {
            UUID order = order(CUSTOMER_A, SHOP_1, SHOP_1_PIN, DOOR_A, "READY");
            riderReports(order, HOME);

            seenAt(position(BACKOFFICE, order), HOME);
            sighting(BACKOFFICE, order).andExpect(jsonPath("$.state").value("VISIBLE"));
            told(CUSTOMER_A, order, "HEADING_TO_SHOP");
        }
    }
}
