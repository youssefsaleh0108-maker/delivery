package com.delivery.transfer.api;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;
import org.springframework.core.MethodParameter;
import org.springframework.http.MediaType;
import org.springframework.security.core.authority.AuthorityUtils;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.bind.support.WebDataBinderFactory;
import org.springframework.web.context.request.NativeWebRequest;
import org.springframework.web.method.support.HandlerMethodArgumentResolver;
import org.springframework.web.method.support.ModelAndViewContainer;

import com.delivery.transfer.client.OrderManagerClient;
import com.delivery.transfer.client.OrderManagerClient.OrderSummary;
import com.delivery.transfer.client.OrderManagerClient.OrderUnavailableException;
import com.delivery.transfer.connector.CashOnDeliveryConnector;
import com.delivery.transfer.connector.ConnectorRegistry;
import com.delivery.transfer.connector.SimulatedWalletConnector;
import com.delivery.transfer.domain.MoneyTransfer;
import com.delivery.transfer.domain.MoneyTransferRepository;
import com.delivery.transfer.domain.SplitPlan;
import com.delivery.transfer.domain.SplitPlanRepository;
import com.delivery.transfer.domain.SplitShare;
import com.delivery.transfer.domain.TransferMethod;
import com.delivery.transfer.service.SplitService;
import com.delivery.transfer.service.TransferService;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * RECON-02: who may read an order's split plan, and what each of them gets.
 *
 * <p>The pinned {@link SplitPlanReadersTest} proves a stranger is told nothing. These prove the other
 * side — the host, an invitee and back office read the plan; the order's own rider reads the amounts
 * and whom to collect them from, with no usernames — and that a stranger's 404 cannot be told apart
 * from an order with no plan. They also sweep the other split endpoints, and the transfer read by
 * order, for the same flaw.
 */
@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
@DisplayName("RECON-02: an order's split plan is read by its host, invitees, rider and back office")
class SplitPlanAccessTest {

    private static final UUID ORDER = UUID.fromString("42c91f1c-4883-4620-9842-f8b190f8c429");
    private static final UUID NO_PLAN = UUID.fromString("0b1e2c3d-0000-4000-8000-000000000000");

    @Mock private SplitPlanRepository plans;
    @Mock private MoneyTransferRepository transferRows;
    @Mock private OrderManagerClient orders;

    private SplitPlan plan;
    private Caller caller;
    private MockMvc mvc;

    @BeforeEach
    void setUp() {
        plan = new SplitPlan("host-sub", "host", "Host Name", "Recon", SplitPlan.Mode.EVEN,
                new BigDecimal("19.50"), new BigDecimal("90000"), Instant.now().plusSeconds(900));
        SplitShare host = new SplitShare("host", "Host Name", new BigDecimal("9.50"), null);
        host.commitWithOrder();
        plan.addShare(host);
        SplitShare friend = new SplitShare("friend", "Friend Name", new BigDecimal("5.00"), 1);
        friend.commitSimulated(SplitShare.Method.WHISH);
        plan.addShare(friend);
        plan.addShare(new SplitShare(null, "Guest", new BigDecimal("5.00"), 1));
        plan.placed(ORDER);
        when(plans.findByOrderId(ORDER)).thenReturn(Optional.of(plan));
        when(plans.findByOrderId(NO_PLAN)).thenReturn(Optional.empty());
        when(plans.findById(any())).thenAnswer(call ->
                plan.getId().equals(call.getArgument(0)) ? Optional.of(plan) : Optional.empty());

        TransferService transfers = new TransferService(transferRows,
                new ConnectorRegistry(List.of(new CashOnDeliveryConnector(),
                        new SimulatedWalletConnector(true))),
                orders, new BigDecimal("90000"), new BigDecimal("100000"));
        caller = new Caller();
        mvc = MockMvcBuilders.standaloneSetup(
                        new SplitController(new SplitService(plans, transfers)),
                        new TransferController(transfers))
                .setControllerAdvice(new ApiExceptionHandler())
                .setCustomArgumentResolvers(caller)
                .build();
    }

    @AfterEach
    void tearDown() {
        SecurityContextHolder.clearContext();
    }

    /** Signs the request in as {@code subject} / {@code username} holding {@code role}. */
    private void as(String subject, String username, String role) {
        caller.jwt = Jwt.withTokenValue("token-of-" + subject)
                .header("alg", "none")
                .subject(subject)
                .claim("preferred_username", username)
                .build();
        SecurityContextHolder.getContext().setAuthentication(new JwtAuthenticationToken(
                caller.jwt, AuthorityUtils.createAuthorityList("ROLE_" + role)));
    }

    /** What Order Manager answers the caller about ORDER: carried by {@code rider}, paid {@code by}. */
    private void orderCarriedBy(String rider, String by) {
        when(orders.fetch(ORDER)).thenReturn(new OrderSummary(ORDER, "host-sub", rider,
                "PICKED_UP", new BigDecimal("19.50"), by, "CASH".equals(by) ? "DUE" : "AUTHORIZED"));
    }

    private ResultActions readPlanFor(UUID order) throws Exception {
        return mvc.perform(get("/api/transfers/splits/for-order/{orderId}", order));
    }

    @Nested
    @DisplayName("the whole plan")
    class WholePlan {

        @Test
        @DisplayName("the host reads it, usernames and all")
        void host() throws Exception {
            as("host-sub", "host", "CUSTOMER");

            readPlanFor(ORDER).andExpect(status().isOk())
                    .andExpect(jsonPath("$.hostUsername").value("host"))
                    .andExpect(jsonPath("$.shares[?(@.name == 'Friend Name')].username")
                            .value("friend"));
        }

        @Test
        @DisplayName("an invitee reads it")
        void invitee() throws Exception {
            as("friend-sub", "friend", "CUSTOMER");

            readPlanFor(ORDER).andExpect(status().isOk())
                    .andExpect(jsonPath("$.hostName").value("Host Name"));
        }

        @Test
        @DisplayName("back office reads it without being on the order")
        void backOffice() throws Exception {
            as("ops-sub", "ops", "BACKOFFICE");

            readPlanFor(ORDER).andExpect(status().isOk())
                    .andExpect(jsonPath("$.hostUsername").value("host"));
        }
    }

    @Nested
    @DisplayName("the order's rider")
    class Rider {

        @Test
        @DisplayName("reads the amounts and whom to collect them from, and no usernames")
        void amountsOnly() throws Exception {
            as("rider-sub", "rider", "DELIVERY");
            orderCarriedBy("rider-sub", "CASH");

            String body = readPlanFor(ORDER).andExpect(status().isOk())
                    .andExpect(jsonPath("$.shares.length()").value(3))
                    .andExpect(jsonPath("$.shares[?(@.name == 'Friend Name')].amountUsd")
                            .value(5.00))
                    .andReturn().getResponse().getContentAsString();

            assertThat(body).doesNotContain("\"username\"", "hostUsername", "hostName", "\"host\"",
                    "\"friend\"", "storeName");
        }

        /**
         * Every share of a cash order is handed over at this door — the host's slice and a
         * simulated wallet share included — so an app from before RECON-01, which adds up only the
         * CASH_AT_DOOR shares, asks for the order's whole 19.50 too.
         */
        @Test
        @DisplayName("on a cash order, every share is cash at this door, a simulated one still labelled")
        void cashOrder() throws Exception {
            as("rider-sub", "rider", "DELIVERY");
            orderCarriedBy("rider-sub", "CASH");

            readPlanFor(ORDER).andExpect(status().isOk())
                    .andExpect(jsonPath("$.shares[*].method").value(
                            org.hamcrest.Matchers.everyItem(org.hamcrest.Matchers.is("CASH_AT_DOOR"))))
                    .andExpect(jsonPath("$.shares[?(@.name == 'Friend Name')].simulated")
                            .value(true))
                    .andExpect(jsonPath("$.shares[?(@.name == 'Friend Name')].simulatedMethod")
                            .value("WHISH"));
        }

        @Test
        @DisplayName("on a wallet order, every share travelled with the order: nothing at the door")
        void walletOrder() throws Exception {
            as("rider-sub", "rider", "DELIVERY");
            orderCarriedBy("rider-sub", "WALLET");

            readPlanFor(ORDER).andExpect(status().isOk())
                    .andExpect(jsonPath("$.shares[*].method").value(
                            org.hamcrest.Matchers.everyItem(org.hamcrest.Matchers.is("HOST_ORDER"))));
        }

        @Test
        @DisplayName("a rider on another order is told nothing, even when the order answers them")
        void anotherOrdersRider() throws Exception {
            as("other-rider-sub", "other", "DELIVERY");
            orderCarriedBy("rider-sub", "CASH");

            readPlanFor(ORDER).andExpect(status().isNotFound());
        }

        @Test
        @DisplayName("a rider the order does not answer is told nothing")
        void orderManagerSaysNo() throws Exception {
            as("stranger-rider-sub", "stranger", "DELIVERY");
            when(orders.fetch(ORDER)).thenThrow(
                    new OrderUnavailableException("That order does not exist, or is not yours"));

            readPlanFor(ORDER).andExpect(status().isNotFound());
        }
    }

    @Test
    @DisplayName("a stranger's 404 is the same answer as an order with no plan")
    void strangerCannotTellAPlanExists() throws Exception {
        as("stranger-sub", "stranger", "CUSTOMER");
        when(orders.fetch(any())).thenThrow(
                new OrderUnavailableException("That order does not exist, or is not yours"));

        String withPlan = readPlanFor(ORDER).andExpect(status().isNotFound())
                .andReturn().getResponse().getContentAsString();
        String withoutPlan = readPlanFor(NO_PLAN).andExpect(status().isNotFound())
                .andReturn().getResponse().getContentAsString();

        assertThat(detail(withPlan)).isEqualTo(detail(withoutPlan));
    }

    private static String detail(String problem) {
        return problem.replaceAll(".*\"detail\":\"([^\"]*)\".*", "$1");
    }

    /** The same flaw looked for everywhere else a plan or a transfer is read by id. */
    @Nested
    @DisplayName("the other endpoints")
    class Sweep {

        @Test
        @DisplayName("a plan by id is 404 to anybody but its host and invitees")
        void planById() throws Exception {
            as("stranger-sub", "stranger", "CUSTOMER");

            mvc.perform(get("/api/transfers/splits/{id}", plan.getId()))
                    .andExpect(status().isNotFound());
        }

        @Test
        @DisplayName("the host's actions are 404 to anybody but the host")
        void hostActions() throws Exception {
            as("friend-sub", "friend", "CUSTOMER");

            for (String action : List.of("cover", "remind", "cancel")) {
                mvc.perform(post("/api/transfers/splits/{id}/" + action, plan.getId()))
                        .andExpect(status().isNotFound());
            }
            mvc.perform(post("/api/transfers/splits/{id}/attach-order", plan.getId())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{\"orderId\":\"" + ORDER + "\"}"))
                    .andExpect(status().isNotFound());
        }

        @Test
        @DisplayName("somebody else's transfer by order is 404, like one that does not exist")
        void transferByOrder() throws Exception {
            as("stranger-sub", "stranger", "CUSTOMER");
            when(transferRows.findByOrderId(ORDER)).thenReturn(Optional.of(new MoneyTransfer(
                    ORDER, "host-sub", TransferMethod.CASH_ON_DELIVERY, new BigDecimal("19.50"),
                    new BigDecimal("19.50"), BigDecimal.ZERO, new BigDecimal("90000"))));

            mvc.perform(get("/api/transfers/order/{orderId}", ORDER))
                    .andExpect(status().isNotFound());
        }
    }

    /** The signed-in caller, switched per test by {@link #as}. */
    private static final class Caller implements HandlerMethodArgumentResolver {

        private Jwt jwt;

        @Override
        public boolean supportsParameter(MethodParameter parameter) {
            return Jwt.class.equals(parameter.getParameterType());
        }

        @Override
        public Object resolveArgument(MethodParameter parameter, ModelAndViewContainer mav,
                                      NativeWebRequest request, WebDataBinderFactory binder) {
            return jwt;
        }
    }
}
