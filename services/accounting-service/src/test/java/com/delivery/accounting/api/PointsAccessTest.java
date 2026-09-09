package com.delivery.accounting.api;

import java.math.BigDecimal;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.security.web.method.annotation.AuthenticationPrincipalArgumentResolver;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import com.delivery.accounting.domain.PointsEntry.OwnerKind;
import com.delivery.accounting.domain.PointsRedemption;
import com.delivery.accounting.service.CarrierCompanyClient;
import com.delivery.accounting.service.PointsService;

/**
 * Whose points a token may read and spend.
 *
 * <p><strong>The carrier routes are the ones worth checking.</strong> Every other owner is keyed on
 * the token subject and there is nothing to tamper with, but a delivery company is keyed on Order
 * Manager's provider id, which the caller has to name — and {@code hasRole('CARRIER')} is held by
 * every company on the platform. Each test below names a rival company and asserts both the refusal
 * and that the rival's figures were never computed.
 *
 * <p>Standalone MockMvc, matching {@link StatementAccessTest}. Method security is NOT wired here,
 * which is the point: these refusals are the controller's own and hold without a proxy.
 */
@DisplayName("whose points a token may reach")
class PointsAccessTest {

    private static final String MY_COMPANY = "provider-77";
    private static final String RIVAL_COMPANY = "provider-99";
    private static final String MY_TOKEN = "carrier-token";

    private PointsService points;
    private CarrierCompanyClient carrierCompanies;
    private MockMvc mvc;

    @BeforeEach
    void setUp() {
        points = mock(PointsService.class);
        carrierCompanies = mock(CarrierCompanyClient.class);
        when(points.valueOf(anyLong())).thenReturn(new BigDecimal("1.00"));
        mvc = MockMvcBuilders
                .standaloneSetup(new PointsController(points, carrierCompanies))
                .setCustomArgumentResolvers(new AuthenticationPrincipalArgumentResolver())
                .build();
    }

    @AfterEach
    void tearDown() {
        SecurityContextHolder.clearContext();
    }

    private static void signedInAs(String subject, String tokenValue, String... roles) {
        Jwt jwt = Jwt.withTokenValue(tokenValue)
                .header("alg", "none")
                .subject(subject)
                .claim("realm_access", Map.of("roles", List.of(roles)))
                .build();
        List<GrantedAuthority> authorities = java.util.Arrays.stream(roles)
                .map(role -> new SimpleGrantedAuthority("ROLE_" + role))
                .map(GrantedAuthority.class::cast)
                .toList();
        SecurityContextHolder.getContext()
                .setAuthentication(new JwtAuthenticationToken(jwt, authorities));
    }

    private static void signedInAsCarrier() {
        signedInAs("carrier-staff-sub", MY_TOKEN, "CARRIER");
    }

    private static PointsRedemption redemptionOf(OwnerKind kind, String ref) {
        return new PointsRedemption(kind, ref, 500L, new BigDecimal("5.00"), "USD", null,
                "requester-sub");
    }

    // ------------------------------------------------------------------- the carrier balance

    @Nested
    @DisplayName("a carrier's balance and rider breakdown")
    class CarrierBalance {

        @Test
        @DisplayName("refuses a company the caller does not run")
        void aForeignCompanyIsRefused() throws Exception {
            signedInAsCarrier();
            when(carrierCompanies.companyIdFor(MY_TOKEN)).thenReturn(MY_COMPANY);

            mvc.perform(get("/api/points/carriers/" + RIVAL_COMPANY + "/balance"))
                    .andExpect(status().isForbidden())
                    .andExpect(jsonPath("$.message").value("That is not your delivery company"));

            // Not merely hidden: the rival's balance and the names of its riders were never read.
            verify(points, never()).balanceOf(any(), eq(RIVAL_COMPANY));
            verify(points, never()).riderBreakdown(RIVAL_COMPANY);
        }

        @Test
        @DisplayName("answers for the company the caller does run")
        void ownCompanyIsAnswered() throws Exception {
            signedInAsCarrier();
            when(carrierCompanies.companyIdFor(MY_TOKEN)).thenReturn(MY_COMPANY);
            when(points.balanceOf(OwnerKind.CARRIER, MY_COMPANY)).thenReturn(1200L);
            when(points.riderBreakdown(MY_COMPANY))
                    .thenReturn(List.of(new PointsService.RiderEarning("rider-1", 700L)));

            mvc.perform(get("/api/points/carriers/" + MY_COMPANY + "/balance"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.ownerRef").value(MY_COMPANY))
                    .andExpect(jsonPath("$.points").value(1200))
                    .andExpect(jsonPath("$.riders[0].riderRef").value("rider-1"));
        }

        @Test
        @DisplayName("refuses an account attached to no company at all")
        void staffOfNoCompanyIsRefused() throws Exception {
            signedInAsCarrier();
            when(carrierCompanies.companyIdFor(MY_TOKEN))
                    .thenThrow(new CarrierCompanyClient.NoCompanyException("not staff"));

            mvc.perform(get("/api/points/carriers/" + MY_COMPANY + "/balance"))
                    .andExpect(status().isForbidden())
                    .andExpect(jsonPath("$.message").value("That is not your delivery company"));

            verify(points, never()).balanceOf(any(), anyString());
        }

        /** An outage in the ownership check must not become a way past it. */
        @Test
        @DisplayName("answers 503 when the company cannot be confirmed, never the figures")
        void anOutageIsNotPermission() throws Exception {
            signedInAsCarrier();
            when(carrierCompanies.companyIdFor(MY_TOKEN))
                    .thenThrow(new IllegalStateException("Order Manager unreachable"));

            mvc.perform(get("/api/points/carriers/" + MY_COMPANY + "/balance"))
                    .andExpect(status().isServiceUnavailable());

            verify(points, never()).balanceOf(any(), anyString());
        }
    }

    // ------------------------------------------------------------------------- the redemptions

    @Nested
    @DisplayName("listing redemptions")
    class Listing {

        @Test
        @DisplayName("refuses another company's payout history")
        void aForeignOwnerRefIsRefused() throws Exception {
            signedInAsCarrier();
            when(carrierCompanies.companyIdFor(MY_TOKEN)).thenReturn(MY_COMPANY);

            mvc.perform(get("/api/points/redemptions").param("ownerRef", RIVAL_COMPANY))
                    .andExpect(status().isForbidden())
                    .andExpect(jsonPath("$.message").value("That is not your delivery company"));

            verify(points, never()).requestsFor(any(), eq(RIVAL_COMPANY));
        }

        /** Naming nothing asks the same question, so it resolves to the same company. */
        @Test
        @DisplayName("resolves the caller's own company when none is named")
        void ownCompanyIsResolvedFromTheToken() throws Exception {
            signedInAsCarrier();
            when(carrierCompanies.companyIdFor(MY_TOKEN)).thenReturn(MY_COMPANY);
            when(points.requestsFor(OwnerKind.CARRIER, MY_COMPANY)).thenReturn(List.of());

            mvc.perform(get("/api/points/redemptions"))
                    .andExpect(status().isOk());

            verify(points).requestsFor(OwnerKind.CARRIER, MY_COMPANY);
        }
    }

    @Nested
    @DisplayName("requesting a redemption")
    class Requesting {

        @Test
        @DisplayName("refuses one drawn on another company's points")
        void aForeignProviderIsRefused() throws Exception {
            signedInAsCarrier();
            when(carrierCompanies.companyIdFor(MY_TOKEN)).thenReturn(MY_COMPANY);

            mvc.perform(post("/api/points/redemptions")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{\"ownerKind\":\"CARRIER\",\"ownerRef\":\"" + RIVAL_COMPANY
                                    + "\",\"points\":500}"))
                    .andExpect(status().isForbidden())
                    .andExpect(jsonPath("$.message").value("That is not your delivery company"));

            verify(points, never()).request(any(), anyString(), anyLong(), any(), anyString());
        }

        /**
         * The kind travels in the body, so it is a claim about the caller and has to be checked
         * against their roles like any other.
         */
        @Test
        @DisplayName("refuses a merchant claiming a carrier balance")
        void aKindTheCallerDoesNotHoldIsRefused() throws Exception {
            signedInAs("merchant-sub", "merchant-token", "MERCHANT");

            mvc.perform(post("/api/points/redemptions")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{\"ownerKind\":\"CARRIER\",\"ownerRef\":\"" + RIVAL_COMPANY
                                    + "\",\"points\":500}"))
                    .andExpect(status().isForbidden());

            verify(points, never()).request(any(), anyString(), anyLong(), any(), anyString());
            verifyNoInteractions(carrierCompanies);
        }
    }

    @Nested
    @DisplayName("cancelling a redemption")
    class Cancelling {

        private final UUID id = UUID.randomUUID();

        @Test
        @DisplayName("refuses one belonging to somebody else")
        void anotherOwnersRequestIsRefused() throws Exception {
            signedInAs("merchant-sub", "merchant-token", "MERCHANT");
            when(points.find(id)).thenReturn(
                    Optional.of(redemptionOf(OwnerKind.MERCHANT, "rival-merchant-sub")));

            mvc.perform(post("/api/points/redemptions/" + id + "/cancel"))
                    .andExpect(status().isForbidden());

            // The points stay held: cancelling releases them, so this was a way to disrupt
            // somebody else's payout as well as to read that it exists.
            verify(points, never()).cancel(any(), anyString());
        }

        @Test
        @DisplayName("refuses another delivery company's request")
        void anotherCompanysRequestIsRefused() throws Exception {
            signedInAsCarrier();
            when(carrierCompanies.companyIdFor(MY_TOKEN)).thenReturn(MY_COMPANY);
            when(points.find(id)).thenReturn(
                    Optional.of(redemptionOf(OwnerKind.CARRIER, RIVAL_COMPANY)));

            mvc.perform(post("/api/points/redemptions/" + id + "/cancel"))
                    .andExpect(status().isForbidden());

            verify(points, never()).cancel(any(), anyString());
        }

        @Test
        @DisplayName("allows the owner to withdraw their own")
        void theOwnerMayWithdraw() throws Exception {
            signedInAs("merchant-sub", "merchant-token", "MERCHANT");
            PointsRedemption mine = redemptionOf(OwnerKind.MERCHANT, "merchant-sub");
            when(points.find(id)).thenReturn(Optional.of(mine));
            when(points.cancel(id, "merchant-sub")).thenReturn(mine);

            mvc.perform(post("/api/points/redemptions/" + id + "/cancel"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.ownerRef").value("merchant-sub"));

            verify(points).cancel(id, "merchant-sub");
        }
    }
}
