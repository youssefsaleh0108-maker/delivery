package com.delivery.transfer.api;

import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.Optional;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.core.MethodParameter;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.bind.support.WebDataBinderFactory;
import org.springframework.web.context.request.NativeWebRequest;
import org.springframework.web.method.support.HandlerMethodArgumentResolver;
import org.springframework.web.method.support.ModelAndViewContainer;

import com.delivery.transfer.domain.SplitPlan;
import com.delivery.transfer.domain.SplitPlanRepository;
import com.delivery.transfer.domain.SplitShare;
import com.delivery.transfer.service.SplitService;
import com.delivery.transfer.service.TransferService;

/**
 * RECON-02: any rider or customer can read any order's split plan.
 *
 * <p>{@code GET /api/transfers/splits/for-order/{orderId}} is open to every DELIVERY and CUSTOMER
 * token and takes no caller at all ({@code SplitController.forOrder}, {@code SplitService.forOrder}),
 * so it answers anybody holding an order id with the host's name and username, every friend's name
 * and username, and what each of them pays. Riders see the ids of every order on the job board.
 *
 * <p>Reproduced on dev on 2026-09-19 (deep test): the demo rider, not on order 42c91f1c, got 404 for
 * the order itself and 200 for its plan, with {@code hostName, hostUsername} and each share's
 * {@code name, username, amountUsd}.
 *
 * <p>Fails until the plan is refused to anybody but its host, its invitees and the order's own
 * rider.
 */
@ExtendWith(MockitoExtension.class)
@DisplayName("RECON-02: an order's split plan is not read by strangers")
class SplitPlanReadersTest {

    private static final UUID ORDER = UUID.fromString("42c91f1c-4883-4620-9842-f8b190f8c429");

    @Mock
    private SplitPlanRepository plans;
    @Mock
    private TransferService transfers;

    private MockMvc mvc;

    @BeforeEach
    void setUp() {
        SplitPlan plan = new SplitPlan("host-sub", "host", "Host Name", "Recon", SplitPlan.Mode.EVEN,
                new BigDecimal("19.50"), new BigDecimal("90000"), Instant.now().plusSeconds(900));
        SplitShare host = new SplitShare("host", "Host Name", new BigDecimal("14.50"), null);
        host.pay(SplitShare.Method.HOST_ORDER);
        plan.addShare(host);
        plan.addShare(new SplitShare("friend", "Friend Name", new BigDecimal("5.00"), 1));
        plan.placed(ORDER);
        when(plans.findByOrderId(ORDER)).thenReturn(Optional.of(plan));

        mvc = MockMvcBuilders.standaloneSetup(new SplitController(new SplitService(plans, transfers)))
                .setControllerAdvice(new ApiExceptionHandler())
                .setCustomArgumentResolvers(new Caller("stranger-rider-sub", "stranger"))
                .build();
    }

    @Test
    @DisplayName("a rider who is not on the order is told nothing about who pays what")
    void aStrangerGetsNothing() throws Exception {
        mvc.perform(get("/api/transfers/splits/for-order/{orderId}", ORDER))
                .andExpect(status().isNotFound());
    }

    /** The signed-in caller: somebody who is neither the host, an invitee nor the order's rider. */
    private static final class Caller implements HandlerMethodArgumentResolver {

        private final Jwt jwt;

        Caller(String subject, String username) {
            this.jwt = Jwt.withTokenValue("test-token")
                    .header("alg", "none")
                    .subject(subject)
                    .claim("preferred_username", username)
                    .build();
        }

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
