package com.delivery.transfer.api;

import java.math.BigDecimal;
import java.util.Optional;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;
import org.springframework.core.MethodParameter;
import org.springframework.http.MediaType;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.bind.support.WebDataBinderFactory;
import org.springframework.web.context.request.NativeWebRequest;
import org.springframework.web.method.support.HandlerMethodArgumentResolver;
import org.springframework.web.method.support.ModelAndViewContainer;

import com.delivery.transfer.client.OrderManagerClient;
import com.delivery.transfer.client.OrderManagerClient.OrderSummary;
import com.delivery.transfer.connector.CashOnDeliveryConnector;
import com.delivery.transfer.connector.ConnectorRegistry;
import com.delivery.transfer.domain.MoneyTransfer;
import com.delivery.transfer.domain.MoneyTransferRepository;
import com.delivery.transfer.domain.TransferMethod;
import com.delivery.transfer.service.TransferService;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * The money surface as a client actually meets it: a status, and a body it can act on.
 *
 * <p>Three separate end-to-end failures live here. A missing field reached the arithmetic and
 * answered 500; a quote priced numbers the POST behind it refuses; and every refusal arrived as
 * the same empty 400 whatever it was about. The service is real in these cases — the refusals and
 * the arithmetic are the thing under test — and only the repository, the registry and Order
 * Manager are stood in for.
 */
@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
class TransferControllerTest {

    private static final String PAYER = "customer-sub";
    private static final UUID ORDER = UUID.fromString("11111111-1111-1111-1111-111111111111");
    private static final UUID STORED_ORDER = UUID.fromString("22222222-2222-2222-2222-222222222222");

    /**
     * One order's money, as every path must print it: dollars to the cent, lira whole. The rate
     * arrives as a config value on the POST and off a {@code numeric(12,2)} column on the GET, and
     * a client comparing the two must find no difference.
     */
    private static final String MONEY = "\"amountUsd\":10.01,\"splitUsd\":10.00,"
            + "\"splitLbpInUsd\":0.01,\"splitLbpFace\":1000,\"rateUsed\":90000,";

    @Mock private MoneyTransferRepository transfers;
    @Mock private ConnectorRegistry registry;
    @Mock private OrderManagerClient orders;

    private MockMvc mvc;

    @BeforeEach
    void setUp() {
        TransferService service = new TransferService(transfers, registry, orders,
                new BigDecimal("90000"), new BigDecimal("100000"));

        when(registry.forMethod(any())).thenReturn(Optional.of(new CashOnDeliveryConnector()));
        when(transfers.findByOrderId(ORDER)).thenReturn(Optional.empty());
        when(transfers.save(any())).thenAnswer(call -> call.getArgument(0));
        when(orders.fetch(any())).thenReturn(new OrderSummary(ORDER, PAYER, "PLACED"));
        // The same transfer as Postgres hands it back: every column at the scale it was declared
        // with, which is where the rate grew its two decimals.
        when(transfers.findByOrderId(STORED_ORDER)).thenReturn(Optional.of(new MoneyTransfer(
                STORED_ORDER, PAYER, TransferMethod.CASH_ON_DELIVERY,
                new BigDecimal("10.01"), new BigDecimal("10.00"), new BigDecimal("0.01"),
                new BigDecimal("90000.00"))));

        mvc = MockMvcBuilders.standaloneSetup(new TransferController(service))
                .setControllerAdvice(new ApiExceptionHandler())
                .setCustomArgumentResolvers(new CallersJwt())
                .build();
    }

    @Test
    @DisplayName("a quote missing amountUsd is the caller's 400, not our 500")
    void missingAmountIsA400() throws Exception {
        String body = mvc.perform(post("/api/transfers/quote")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"splitUsd\":5.00}"))
                .andExpect(status().isBadRequest())
                .andReturn().getResponse().getContentAsString();

        // Named, so the client knows which field to fill rather than which screen to blame.
        assertThat(body).contains("amountUsd");
    }

    @Test
    @DisplayName("an initiate missing orderId is the caller's 400, not our 500")
    void missingOrderIdIsA400() throws Exception {
        mvc.perform(post("/api/transfers")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"method\":\"CASH_ON_DELIVERY\",\"amountUsd\":10.01}"))
                .andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("a quote refuses a negative amount, as the POST behind it would")
    void quoteRefusesNegativeAmount() throws Exception {
        String body = mvc.perform(post("/api/transfers/quote")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"amountUsd\":-5.00}"))
                .andExpect(status().isUnprocessableEntity())
                .andReturn().getResponse().getContentAsString();

        assertThat(body).contains("amountUsd must be positive");
    }

    /**
     * Two refusals, two answers. They were byte-identical, so a client could only say "something
     * went wrong" to a customer who needed to be told which number to change.
     */
    @Test
    @DisplayName("a quote refuses a split larger than the total, in its own words")
    void quoteRefusesOversizedSplit() throws Exception {
        String body = mvc.perform(post("/api/transfers/quote")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"amountUsd\":10.00,\"splitUsd\":25.00}"))
                .andExpect(status().isUnprocessableEntity())
                .andReturn().getResponse().getContentAsString();

        assertThat(body).contains("splitUsd must be between 0 and amountUsd");
    }

    @Test
    @DisplayName("a legal quote prices the lira part on a note that exists")
    void quotePrices() throws Exception {
        String body = mvc.perform(post("/api/transfers/quote")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"amountUsd\":10.01,\"splitUsd\":10.00}"))
                .andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString();

        assertThat(body).contains("\"lbpPerUsd\":90000")
                .contains("\"amountUsd\":10.01")
                .contains("\"splitLbpFace\":1000")
                .doesNotContain("90000.00");
    }

    @Test
    @DisplayName("the record reads back exactly as it was recorded")
    void moneyReadsBackTheSameWayItWasWritten() throws Exception {
        String recorded = mvc.perform(post("/api/transfers")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"orderId\":\"" + ORDER + "\",\"method\":\"CASH_ON_DELIVERY\","
                                + "\"amountUsd\":10.01,\"splitUsd\":10.00}"))
                .andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString();

        String readBack = mvc.perform(get("/api/transfers/order/" + STORED_ORDER))
                .andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString();

        assertThat(recorded).contains(MONEY);
        assertThat(readBack).contains(MONEY);
    }

    /** Stands in for the resource server's principal, which no test has a real token from. */
    private static final class CallersJwt implements HandlerMethodArgumentResolver {

        private final Jwt jwt = Jwt.withTokenValue("test-token")
                .header("alg", "none")
                .subject(PAYER)
                .claim("preferred_username", PAYER)
                .build();

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
