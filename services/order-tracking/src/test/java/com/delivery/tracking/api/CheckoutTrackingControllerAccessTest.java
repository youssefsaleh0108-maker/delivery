package com.delivery.tracking.api;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyBoolean;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.time.Duration;
import java.util.Arrays;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.hamcrest.Matchers;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import com.delivery.tracking.domain.OrderParticipants;
import com.delivery.tracking.domain.OrderParticipantsRepository;
import com.delivery.tracking.route.GeoPoint;
import com.delivery.tracking.route.HaversineRouteProvider;
import com.delivery.tracking.route.RoutePaths;
import com.delivery.tracking.route.RouteProviderRegistry;
import com.delivery.tracking.service.CheckoutTrackingService;
import com.delivery.tracking.service.EtaService;
import com.delivery.tracking.service.OtherDeliveriesLatch;
import com.delivery.tracking.service.RiderSighting;
import com.delivery.tracking.service.TrackingService;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * Who may open a customer's checkout map.
 *
 * <p>The checkout's customer, and the back office — nobody else. The map shows every shop the
 * customer bought from in one go and where their door is, so a sibling order's merchant must not
 * see the other shops, and neither may the rider. Every refusal that could reveal whether the
 * checkout exists is the same 404 an unknown checkout gets.
 *
 * <p>The real service answers here, over a repository that scopes rows exactly as the query does
 * (checkout AND customer), so a 404 below is the scoping at work rather than a mock told to throw.
 * Standalone MockMvc: method security is not wired, and every role refusal holds because the
 * controller checks the role itself as well.
 */
@DisplayName("who may open a checkout map")
class CheckoutTrackingControllerAccessTest {

    private static final UUID CHECKOUT = UUID.fromString("c4ec0000-0000-4000-8000-00000000000a");
    private static final UUID ORDER_A = UUID.fromString("0a0a0a0a-0000-4000-8000-000000000001");
    private static final UUID ORDER_B = UUID.fromString("0b0b0b0b-0000-4000-8000-000000000002");
    private static final String CUSTOMER = "customer-sub";
    private static final String SIBLING_MERCHANT = "merchant-b-sub";
    private static final String RIDER = "rider-sub";

    private OrderParticipantsRepository participants;
    private MockMvc mvc;

    @BeforeEach
    void setUp() {
        OrderParticipants a = new OrderParticipants(ORDER_A, CUSTOMER, "merchant-a-sub", RIDER,
                "PICKED_UP");
        a.applyRoute(null, new GeoPoint(33.8938, 35.5018), new GeoPoint(33.8981, 35.5214));
        a.applyCheckout(CHECKOUT, "Hamra Bakery");
        OrderParticipants b = new OrderParticipants(ORDER_B, CUSTOMER, SIBLING_MERCHANT, RIDER,
                "READY");
        b.applyRoute(null, new GeoPoint(33.8869, 35.5131), new GeoPoint(33.8981, 35.5214));
        b.applyCheckout(CHECKOUT, "Achrafieh Pharmacy");

        participants = mock(OrderParticipantsRepository.class);
        // The whole checkout, whoever asks: the service serves it only when every row is the
        // caller's. An unknown checkout gets Mockito's empty list.
        when(participants.findByCheckoutId(CHECKOUT)).thenReturn(List.of(a, b));

        TrackingService tracking = mock(TrackingService.class);
        when(tracking.currentPosition(any(UUID.class), any(), anyBoolean())).thenReturn(Optional.empty());
        when(tracking.sightingFor(any(OrderParticipants.class), any(), anyBoolean()))
                .thenReturn(new RiderSighting(RiderSighting.State.NO_FIX, null, null));
        RouteProviderRegistry providers = new RouteProviderRegistry(
                List.of(new HaversineRouteProvider(18)), HaversineRouteProvider.NAME);
        EtaService eta = new EtaService(tracking, participants, providers, Duration.ofMinutes(5));
        RoutePaths paths = new RoutePaths(providers, mock(StringRedisTemplate.class),
                new ObjectMapper(), Duration.ofHours(24), 150, Duration.ofSeconds(60));
        CheckoutTrackingService service = new CheckoutTrackingService(participants, tracking, eta,
                paths, new OtherDeliveriesLatch(participants, mock(StringRedisTemplate.class),
                        Duration.ofHours(12)),
                Duration.ofMinutes(5), Duration.ofSeconds(5));

        mvc = MockMvcBuilders.standaloneSetup(new CheckoutTrackingController(service)).build();
    }

    @AfterEach
    void tearDown() {
        SecurityContextHolder.clearContext();
    }

    private static void signedInAs(String subject, String... roles) {
        Jwt jwt = Jwt.withTokenValue("token").header("alg", "none").subject(subject).build();
        List<GrantedAuthority> authorities = Arrays.stream(roles)
                .<GrantedAuthority>map(role -> new SimpleGrantedAuthority("ROLE_" + role))
                .toList();
        SecurityContextHolder.getContext().setAuthentication(
                new JwtAuthenticationToken(jwt, authorities));
    }

    private static String url() {
        return "/api/tracking/checkouts/" + CHECKOUT;
    }

    @Test
    @DisplayName("the checkout's own customer reads it")
    void the_customer_reads_their_checkout() throws Exception {
        signedInAs(CUSTOMER, "CUSTOMER");

        mvc.perform(get(url()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.checkoutId").value(CHECKOUT.toString()))
                .andExpect(jsonPath("$.provider").value(HaversineRouteProvider.NAME))
                .andExpect(jsonPath("$.geometry").value("STRAIGHT"))
                .andExpect(jsonPath("$.door.lat").value(33.8981))
                .andExpect(jsonPath("$.orders.length()").value(2))
                .andExpect(jsonPath("$.orders[0].storeName").value("Achrafieh Pharmacy"))
                .andExpect(jsonPath("$.orders[0].eta.reason").value("NO_FIX"))
                // Nothing about the rider beyond where their phone was — never who they are.
                .andExpect(content().string(Matchers.not(Matchers.containsString(RIDER))));
    }

    @Test
    @DisplayName("another customer is told the checkout does not exist")
    void another_customer_gets_404() throws Exception {
        signedInAs("someone-else-sub", "CUSTOMER");

        mvc.perform(get(url()))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.title").value("Checkout not found"));
    }

    @Test
    @DisplayName("a checkout that does not exist is the same 404")
    void an_unknown_checkout_is_the_same_404() throws Exception {
        signedInAs(CUSTOMER, "CUSTOMER");

        mvc.perform(get("/api/tracking/checkouts/" + UUID.randomUUID()))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.title").value("Checkout not found"));
    }

    /**
     * A sibling's merchant who also shops on the platform holds CUSTOMER, gets past the role check,
     * and still finds nothing — the checkout is not theirs, row by row.
     */
    @Test
    @DisplayName("a sibling order's merchant never sees the customer's other shops")
    void a_siblings_merchant_is_refused() throws Exception {
        signedInAs(SIBLING_MERCHANT, "MERCHANT", "CUSTOMER");
        mvc.perform(get(url())).andExpect(status().isNotFound());

        signedInAs(SIBLING_MERCHANT, "MERCHANT");
        mvc.perform(get(url())).andExpect(status().isForbidden());
    }

    @Test
    @DisplayName("the rider carrying both orders is refused too")
    void the_rider_is_refused() throws Exception {
        signedInAs(RIDER, "DELIVERY", "CUSTOMER");
        mvc.perform(get(url())).andExpect(status().isNotFound());

        signedInAs(RIDER, "DELIVERY");
        mvc.perform(get(url())).andExpect(status().isForbidden());
    }

    @Test
    @DisplayName("the back office reads any checkout")
    void backoffice_reads_it() throws Exception {
        signedInAs("backoffice-sub", "BACKOFFICE");

        mvc.perform(get(url()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.orders.length()").value(2));
    }

    @Test
    @DisplayName("nobody signed in is refused before anything is looked up")
    void anonymous_gets_401() throws Exception {
        mvc.perform(get(url())).andExpect(status().isUnauthorized());

        verifyNoInteractions(participants);
    }
}
