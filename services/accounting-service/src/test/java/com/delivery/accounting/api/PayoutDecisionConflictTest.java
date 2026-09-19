package com.delivery.accounting.api;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.math.BigDecimal;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.orm.ObjectOptimisticLockingFailureException;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.security.web.method.annotation.AuthenticationPrincipalArgumentResolver;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import com.delivery.accounting.domain.AlreadyDecidedException;
import com.delivery.accounting.domain.PointsEntry.OwnerKind;
import com.delivery.accounting.domain.PointsRedemption;
import com.delivery.accounting.domain.RiderCashOut;
import com.delivery.accounting.service.CarrierCompanyClient;
import com.delivery.accounting.service.PointsService;
import com.delivery.accounting.service.RiderEarningsService;

/**
 * RECON-07: of two decisions on one payout request, the one that lost is told so with a 409.
 *
 * <p>The version check itself is proven against Postgres by {@code
 * MoneyCustodyAndPayoutPostgresTest}; this is the other half — that the decision that lost reaches
 * the caller as a conflict, whether it lost at commit (the optimistic lock) or arrived after the
 * other had committed (the request already decided).
 */
@DisplayName("RECON-07: the losing decision on a payout is a 409")
class PayoutDecisionConflictTest {

    private RiderEarningsService earnings;
    private PointsService points;
    private MockMvc riderMvc;
    private MockMvc pointsMvc;

    @BeforeEach
    void setUp() {
        earnings = mock(RiderEarningsService.class);
        points = mock(PointsService.class);
        when(points.valueOf(anyLong())).thenReturn(new BigDecimal("10.00"));
        riderMvc = MockMvcBuilders.standaloneSetup(new RiderEarningsController(earnings))
                .setCustomArgumentResolvers(new AuthenticationPrincipalArgumentResolver())
                .build();
        pointsMvc = MockMvcBuilders
                .standaloneSetup(new PointsController(points, mock(CarrierCompanyClient.class)))
                .setCustomArgumentResolvers(new AuthenticationPrincipalArgumentResolver())
                .build();
        Jwt jwt = Jwt.withTokenValue("token").header("alg", "none").subject("merchant-1")
                .claim("realm_access", Map.of("roles", List.of("BACKOFFICE", "MERCHANT")))
                .build();
        SecurityContextHolder.getContext().setAuthentication(new JwtAuthenticationToken(jwt,
                List.of(new SimpleGrantedAuthority("ROLE_BACKOFFICE"),
                        new SimpleGrantedAuthority("ROLE_MERCHANT"))));
    }

    @AfterEach
    void tearDown() {
        SecurityContextHolder.clearContext();
    }

    private static ObjectOptimisticLockingFailureException lostAtCommit(Class<?> entity) {
        return new ObjectOptimisticLockingFailureException(entity, UUID.randomUUID());
    }

    @Test
    @DisplayName("a cash-out paid as another operator refuses it: the loser at commit gets 409")
    void cashOutLostAtCommit() throws Exception {
        UUID id = UUID.randomUUID();
        when(earnings.rejectCashOut(eq(id), any(), any())).thenThrow(lostAtCommit(RiderCashOut.class));

        riderMvc.perform(post("/api/rider/cash-outs/" + id + "/reject"))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("ALREADY_DECIDED"));
    }

    @Test
    @DisplayName("a cash-out already refused cannot be paid: 409, not 400")
    void cashOutAlreadyDecided() throws Exception {
        UUID id = UUID.randomUUID();
        when(earnings.payCashOut(eq(id), any(), any()))
                .thenThrow(new AlreadyDecidedException("Cannot pay a cash-out that is REJECTED"));

        riderMvc.perform(post("/api/rider/cash-outs/" + id + "/pay"))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.error").value("Cannot pay a cash-out that is REJECTED"));
    }

    @Test
    @DisplayName("a payout provider's refusal is still a 400: nothing was decided")
    void providerRefusalIsNotAConflict() throws Exception {
        UUID id = UUID.randomUUID();
        when(earnings.payCashOut(eq(id), any(), any()))
                .thenThrow(new IllegalStateException("The payout provider refused: no account"));

        riderMvc.perform(post("/api/rider/cash-outs/" + id + "/pay"))
                .andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("a redemption refused as its owner cancels it: the loser at commit gets 409")
    void redemptionLostAtCommit() throws Exception {
        UUID id = UUID.randomUUID();
        when(points.reject(eq(id), any(), any())).thenThrow(lostAtCommit(PointsRedemption.class));
        when(points.approve(eq(id), any(), any())).thenThrow(lostAtCommit(PointsRedemption.class));

        pointsMvc.perform(post("/api/points/redemptions/" + id + "/reject"))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("ALREADY_DECIDED"));
        pointsMvc.perform(post("/api/points/redemptions/" + id + "/approve"))
                .andExpect(status().isConflict());
    }

    @Test
    @DisplayName("an owner cancelling what an operator already approved gets 409")
    void cancelAfterApproval() throws Exception {
        PointsRedemption mine = new PointsRedemption(OwnerKind.MERCHANT, "merchant-1", 1000L,
                new BigDecimal("10.00"), "USD", null, "merchant-1");
        when(points.find(mine.getId())).thenReturn(Optional.of(mine));
        when(points.cancel(eq(mine.getId()), any()))
                .thenThrow(new AlreadyDecidedException("Cannot cancel a redemption that is APPROVED"));

        pointsMvc.perform(post("/api/points/redemptions/" + mine.getId() + "/cancel"))
                .andExpect(status().isConflict());
    }
}
