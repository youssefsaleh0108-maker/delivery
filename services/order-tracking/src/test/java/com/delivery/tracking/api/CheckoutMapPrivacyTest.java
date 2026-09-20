package com.delivery.tracking.api;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.within;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyDouble;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
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
import com.delivery.tracking.route.RoutePaths;
import com.delivery.tracking.route.RouteProviderRegistry;
import com.delivery.tracking.service.CarrierScopeResolver;
import com.delivery.tracking.service.CheckoutTrackingService;
import com.delivery.tracking.service.EtaService;
import com.delivery.tracking.service.FixPolicy;
import com.delivery.tracking.service.FleetMembershipGuard;
import com.delivery.tracking.service.OtherDeliveriesLatch;
import com.delivery.tracking.service.PresenceService;
import com.delivery.tracking.service.TrackingService;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;

/**
 * What a customer's checkout map can learn about riders and about other customers — read as the
 * JSON the app is sent.
 *
 * <p>The rider reports through {@code POST .../ping} and the customer reads
 * {@code GET /api/tracking/checkouts/{id}}, through the real controllers, services, fix policy and
 * rider-visibility gate; only the stores are in memory. The same rider also carries another
 * customer's order, and every answer is searched, as text and as a tree of points, for anything of
 * that order: its ids, its shop, its door, a stop, a leg or a distance through it.
 */
@DisplayName("what a checkout map tells a customer about riders and other customers")
class CheckoutMapPrivacyTest {

    private static final String RIDER = "rider-7f3a";
    private static final String CUSTOMER = "customer-a";
    private static final String THEM = "customer-b";
    private static final String THEIR_SHOP = "merchant-3";
    private static final String THEIR_SHOP_NAME = "Corner Three";
    private static final UUID CHECKOUT = UUID.fromString("c4ec0000-0000-4000-8000-0000000000c1");

    private static final double BASE_LAT = 33.8938;
    private static final double BASE_LNG = 35.5018;
    private static final double METRES_PER_DEGREE_LAT = 111_195.08;
    private static final double METRES_PER_DEGREE_LNG =
            METRES_PER_DEGREE_LAT * Math.cos(Math.toRadians(BASE_LAT));

    private static final GeoPoint SHOP_1 = at(0, 0);
    private static final GeoPoint SHOP_2 = at(1_500, 0);
    private static final GeoPoint DOOR_A = at(-600, -500);
    private static final GeoPoint SHOP_3 = at(-1_000, 3_000);
    private static final GeoPoint DOOR_B = at(2_500, 1_500);
    private static final GeoPoint HOME = at(0, 5_000);

    /** A point {@code north} and {@code east} metres from the first shop. */
    private static GeoPoint at(double north, double east) {
        return new GeoPoint(BASE_LAT + north / METRES_PER_DEGREE_LAT,
                BASE_LNG + east / METRES_PER_DEGREE_LNG);
    }

    private final Map<UUID, OrderParticipants> orders = new HashMap<>();
    private final List<TrackingEvent> trail = new ArrayList<>();
    private final Map<String, RiderPresence> presenceRows = new HashMap<>();
    private final Map<String, String> redisStore = new HashMap<>();
    private final ObjectMapper json = new ObjectMapper().registerModule(new JavaTimeModule());

    private MockMvc mvc;
    private Instant clock;

    @BeforeEach
    @SuppressWarnings("unchecked")
    void setUp() {
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
        when(participants.findByCheckoutId(any())).thenAnswer(call -> orders.values().stream()
                .filter(o -> call.getArgument(0).equals(o.getCheckoutId()))
                .toList());
        when(participants.riderHasOtherLiveOrders(anyString(), any())).thenAnswer(call ->
                orders.values().stream().anyMatch(o ->
                        call.getArgument(0).equals(o.getRiderId()) && o.isTrackable()
                                && !call.getArgument(1).equals(o.getCheckoutId())));

        TrackingEventRepository events = mock(TrackingEventRepository.class);
        when(events.save(any(TrackingEvent.class))).thenAnswer(call -> {
            trail.add(call.getArgument(0));
            return call.getArgument(0);
        });
        when(events.findLatestForOrder(any(), any(Pageable.class))).thenAnswer(call ->
                trail.stream()
                        .filter(e -> e.getOrderId().equals(call.getArgument(0)))
                        .max(Comparator.comparing(TrackingEvent::getRecordedAt))
                        .map(List::of).orElse(List.of()));

        RiderPresenceRepository presenceRepo = mock(RiderPresenceRepository.class);
        when(presenceRepo.findById(anyString())).thenAnswer(
                call -> Optional.ofNullable(presenceRows.get(call.<String>getArgument(0))));
        when(presenceRepo.save(any(RiderPresence.class))).thenAnswer(call -> {
            RiderPresence row = call.getArgument(0);
            presenceRows.put(row.getRiderId(), row);
            return row;
        });
        when(presenceRepo.touchIfDue(anyString(), anyDouble(), anyDouble(), any(), any(), any()))
                .thenReturn(1);

        StringRedisTemplate redis = mock(StringRedisTemplate.class);
        ValueOperations<String, String> values = mock(ValueOperations.class);
        when(redis.opsForValue()).thenReturn(values);
        when(values.get(anyString())).thenAnswer(call -> redisStore.get(call.<String>getArgument(0)));
        doAnswer(call -> {
            redisStore.put(call.getArgument(0), call.getArgument(1));
            return null;
        }).when(values).set(anyString(), anyString(), any(Duration.class));
        when(redis.hasKey(anyString()))
                .thenAnswer(call -> redisStore.containsKey(call.<String>getArgument(0)));
        when(redis.delete(anyString())).thenAnswer(
                call -> redisStore.remove(call.<String>getArgument(0)) != null);

        CarrierMembershipRepository memberships = mock(CarrierMembershipRepository.class);
        when(memberships.findById(anyString())).thenReturn(Optional.empty());
        CarrierScopeResolver carrierScope = mock(CarrierScopeResolver.class);
        when(carrierScope.scopeFor(anyString())).thenReturn(Optional.empty());
        presenceRows.put(RIDER, RiderPresence.firstSeen(RIDER, clock));

        // The shipped limits, except that the rider may cover any distance in the six seconds
        // between two reports: the speed limit has its own suite.
        FixPolicy policy = new FixPolicy(100f, Duration.ofMinutes(10), Duration.ofSeconds(30),
                1_000_000, Duration.ofMinutes(5), Duration.ofSeconds(5), true,
                FixPolicy.LEBANON.minLat(), FixPolicy.LEBANON.maxLat(),
                FixPolicy.LEBANON.minLng(), FixPolicy.LEBANON.maxLng());
        PresenceService presence = new PresenceService(presenceRepo,
                mock(RiderDutyEventRepository.class), mock(DutySessionRepository.class),
                memberships, carrierScope, participants, redis, json, Duration.ofMinutes(2),
                Duration.ofSeconds(30), mock(FleetMembershipGuard.class), policy);
        TrackingService tracking = new TrackingService(events, participants, presence, redis,
                json, Duration.ofSeconds(60));
        RouteProviderRegistry providers = new RouteProviderRegistry(
                List.of(new HaversineRouteProvider(18)), HaversineRouteProvider.NAME);
        EtaService eta = new EtaService(tracking, participants, providers, Duration.ofMinutes(5));
        RoutePaths paths = new RoutePaths(providers, redis, json, Duration.ofHours(24), 150,
                Duration.ofSeconds(60));
        // Recomputed on every read, so each read below sees the reports before it.
        CheckoutTrackingService checkouts = new CheckoutTrackingService(participants, tracking,
                eta, paths, new OtherDeliveriesLatch(participants, redis, Duration.ofHours(12)),
                Duration.ofMinutes(5), Duration.ZERO);

        mvc = MockMvcBuilders.standaloneSetup(
                        new TrackingController(tracking, eta, mock(SimpMessagingTemplate.class)),
                        new CheckoutTrackingController(checkouts))
                .setControllerAdvice(new PingProblems())
                .build();
    }

    @AfterEach
    void tearDown() {
        SecurityContextHolder.clearContext();
    }

    // ------------------------------------------------------------------------------ the world

    private UUID order(String customer, String merchant, String name, GeoPoint shop, GeoPoint door,
                       String status, UUID checkout) {
        UUID id = UUID.randomUUID();
        OrderParticipants order = new OrderParticipants(id, customer, merchant, RIDER, status);
        order.applyRoute(null, shop, door);
        order.applyCheckout(checkout, name);
        if ("PICKED_UP".equals(status)) {
            order.stampMilestones(status, clock);
        }
        orders.put(id, order);
        return id;
    }

    private void deliver(UUID orderId) {
        OrderParticipants order = orders.get(orderId);
        order.apply(RIDER, "DELIVERED");
        order.stampMilestones("DELIVERED", clock);
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
    private void riderReports(UUID orderId, GeoPoint where) throws Exception {
        clock = clock.plusSeconds(6);
        signedInAs(RIDER, "DELIVERY");
        mvc.perform(post("/api/tracking/orders/" + orderId + "/ping")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(String.format(Locale.ROOT,
                                "{\"lat\":%.7f,\"lng\":%.7f,\"accuracyM\":6,\"recordedAt\":\"%s\"}",
                                where.lat(), where.lng(), clock)))
                .andExpect(status().isAccepted());
    }

    /** The checkout map exactly as the customer's app receives it. */
    private String customersMap() throws Exception {
        signedInAs(CUSTOMER, "CUSTOMER");
        return mvc.perform(get("/api/tracking/checkouts/" + CHECKOUT))
                .andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString();
    }

    private String sighting(String who, UUID orderId) throws Exception {
        signedInAs(who, "CUSTOMER");
        return json.readTree(mvc.perform(get("/api/tracking/orders/" + orderId + "/rider"))
                .andReturn().getResponse().getContentAsString()).path("state").asText();
    }

    /** Every {lat, lng} object anywhere in the answer. */
    private static List<GeoPoint> pointsIn(JsonNode node) {
        List<GeoPoint> points = new ArrayList<>();
        if (node.isObject()) {
            if (node.path("lat").isNumber() && node.path("lng").isNumber()) {
                points.add(new GeoPoint(node.get("lat").asDouble(), node.get("lng").asDouble()));
            }
            node.elements().forEachRemaining(child -> points.addAll(pointsIn(child)));
        } else if (node.isArray()) {
            node.elements().forEachRemaining(child -> points.addAll(pointsIn(child)));
        }
        return points;
    }

    /** Every number anywhere in the answer, for the distance checks. */
    private static List<Double> numbersIn(JsonNode node) {
        List<Double> numbers = new ArrayList<>();
        if (node.isNumber()) {
            numbers.add(node.asDouble());
        }
        node.elements().forEachRemaining(child -> numbers.addAll(numbersIn(child)));
        return numbers;
    }

    private static double metres(GeoPoint a, GeoPoint b) {
        return HaversineRouteProvider.distanceMetres(a, b);
    }

    /**
     * Nothing of the other customer's order is in the answer: not its id or its people, not its
     * shop or its door or anywhere within the hand-over buffer of that door, not the rider's id,
     * no row or stop or line for it, and no distance through its shop or to its door.
     */
    private void nothingOfTheirOrder(String body, UUID theirs, List<UUID> ours) throws Exception {
        assertThat(body)
                .doesNotContain(theirs.toString())
                .doesNotContain(THEM)
                .doesNotContain(THEIR_SHOP)
                .doesNotContain(THEIR_SHOP_NAME)
                .doesNotContain(RIDER);

        JsonNode map = json.readTree(body);
        for (GeoPoint point : pointsIn(map)) {
            assertThat(metres(point, DOOR_B)).as("a point near their door").isGreaterThan(300);
            assertThat(metres(point, SHOP_3)).as("a point at their shop").isGreaterThan(50);
        }

        Set<String> ourIds = new HashSet<>();
        ours.forEach(id -> ourIds.add(id.toString()));
        map.path("orders").forEach(row -> assertThat(ourIds).contains(row.path("orderId").asText()));
        map.path("riders").forEach(rider -> rider.path("orderIds")
                .forEach(id -> assertThat(ourIds).contains(id.asText())));
        map.path("paths").forEach(path -> path.path("orderIds")
                .forEach(id -> assertThat(ourIds).contains(id.asText())));

        // No number in the answer is a distance of their journey, alone or tacked onto ours.
        List<Double> theirDistances = new ArrayList<>(List.of(
                metres(SHOP_3, DOOR_B), metres(DOOR_A, DOOR_B), metres(DOOR_A, SHOP_3)));
        for (double number : numbersIn(map)) {
            for (double theirs1 : theirDistances) {
                assertThat(Math.abs(number - theirs1)).as("a distance of their journey")
                        .isGreaterThan(1);
            }
        }
    }

    // -------------------------------------------------------------------------------- cases

    /**
     * The same rider carries this customer's two-shop basket and somebody else's order. Through
     * that other delivery, its hand-over and the first fixes after it, the customer's map is
     * searched for anything of it — and once the rider is clear of the other door, the map shows
     * exactly this customer's own journey.
     */
    @Test
    @DisplayName("another customer's order on the same rider leaves no trace in the JSON")
    void another_customers_order_leaves_no_trace() throws Exception {
        UUID first = order(CUSTOMER, "merchant-1", "Shop One", SHOP_1, DOOR_A, "PICKED_UP",
                CHECKOUT);
        UUID second = order(CUSTOMER, "merchant-2", "Shop Two", SHOP_2, DOOR_A, "READY",
                CHECKOUT);
        UUID theirs = order(THEM, THEIR_SHOP, THEIR_SHOP_NAME, SHOP_3, DOOR_B, "PICKED_UP", null);
        List<UUID> ours = List.of(first, second);

        // On their delivery: the rider's fixes go on their order.
        riderReports(theirs, at(2_000, 1_000));
        String onTheirs = customersMap();
        nothingOfTheirOrder(onTheirs, theirs, ours);
        JsonNode map = json.readTree(onTheirs);
        assertThat(map.at("/riders/0/sighting").asText()).isEqualTo("ON_ANOTHER_DELIVERY");
        assertThat(map.at("/riders/0/position").isNull()).isTrue();
        assertThat(map.path("paths").size()).isZero();
        assertThat(map.at("/orders/0/eta/reason").asText()).isEqualTo("RIDER_ON_ANOTHER_DELIVERY");
        assertThat(map.at("/riders/0/hasOtherDeliveries").asBoolean()).isTrue();

        // At their door, and the first fixes on this customer's order still there.
        riderReports(theirs, DOOR_B);
        deliver(theirs);
        riderReports(first, at(2_500 + 60, 1_500));
        String atTheirDoor = customersMap();
        nothingOfTheirOrder(atTheirDoor, theirs, ours);
        map = json.readTree(atTheirDoor);
        assertThat(map.at("/riders/0/sighting").asText()).isEqualTo("ON_ANOTHER_DELIVERY");
        assertThat(map.at("/riders/0/position").isNull()).isTrue();
        assertThat(sighting(CUSTOMER, first)).isEqualTo("ON_ANOTHER_DELIVERY");
        // Their order is delivered, and the flag does not flip back here, at their door.
        assertThat(map.at("/riders/0/hasOtherDeliveries").asBoolean()).isTrue();

        // Clear of it: this customer's rider, on this customer's journey, and nothing else.
        GeoPoint away = at(1_200, 300);
        riderReports(first, away);
        String clear = customersMap();
        nothingOfTheirOrder(clear, theirs, ours);
        map = json.readTree(clear);
        assertThat(map.at("/riders/0/sighting").asText()).isEqualTo("VISIBLE");
        assertThat(map.at("/riders/0/position/lat").asDouble()).isCloseTo(away.lat(), within(1e-6));
        assertThat(map.at("/riders/0/hasOtherDeliveries").asBoolean()).isTrue();
        double run = metres(away, SHOP_2) + metres(SHOP_2, DOOR_A);
        for (JsonNode row : map.path("orders")) {
            assertThat(row.at("/eta/remainingMetres").asDouble()).isCloseTo(run, within(1d));
        }
        assertThat(map.path("paths").size()).isEqualTo(1);
        assertThat(map.at("/paths/0/metres").asDouble()).isCloseTo(run, within(1d));
    }

    /**
     * The rider claimed both orders at home, five kilometres out. The customer is shown no rider,
     * no line and no stop order worked out from there, and a time without a distance — and not a
     * point near home anywhere in the answer. Within two kilometres of a shop, the rider appears.
     */
    @Test
    @DisplayName("a READY rider more than 2 km from the shop is not on the map")
    void ready_far_from_the_shop_is_not_on_the_map() throws Exception {
        UUID first = order(CUSTOMER, "merchant-1", "Shop One", SHOP_1, DOOR_A, "READY", CHECKOUT);
        UUID second = order(CUSTOMER, "merchant-2", "Shop Two", SHOP_2, DOOR_A, "READY",
                CHECKOUT);

        riderReports(first, HOME);
        String atHome = customersMap();
        JsonNode map = json.readTree(atHome);
        assertThat(map.at("/riders/0/sighting").asText()).isEqualTo("HEADING_TO_SHOP");
        assertThat(map.at("/riders/0/position").isNull()).isTrue();
        assertThat(map.path("paths").size()).isZero();
        for (JsonNode row : map.path("orders")) {
            assertThat(row.path("stop").isNull()).isTrue();
            assertThat(row.at("/eta/available").asBoolean()).isTrue();
            assertThat(row.at("/eta/remainingSeconds").isNumber()).isTrue();
            assertThat(row.at("/eta/remainingMetres").isNull()).isTrue();
        }
        for (GeoPoint point : pointsIn(map)) {
            assertThat(metres(point, HOME)).isGreaterThan(1_000);
        }
        assertThat(sighting(CUSTOMER, first)).isEqualTo("HEADING_TO_SHOP");
        assertThat(sighting(CUSTOMER, second)).isEqualTo("HEADING_TO_SHOP");

        GeoPoint nearShop = at(0, 1_500);
        riderReports(first, nearShop);
        map = json.readTree(customersMap());
        assertThat(map.at("/riders/0/sighting").asText()).isEqualTo("VISIBLE");
        assertThat(map.at("/riders/0/position/lng").asDouble())
                .isCloseTo(nearShop.lng(), within(1e-6));
        assertThat(map.path("paths").size()).isEqualTo(1);
    }
}
