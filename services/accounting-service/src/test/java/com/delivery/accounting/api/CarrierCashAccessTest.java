package com.delivery.accounting.api;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
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
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.mockito.ArgumentCaptor;
import org.springframework.http.MediaType;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import com.delivery.accounting.domain.CashFloatEntry;
import com.delivery.accounting.service.CarrierCashService;
import com.delivery.accounting.service.CarrierCompanyClient;
import com.delivery.accounting.service.CashFloatService;

/**
 * Who may read and clear a delivery company's cash.
 *
 * <p><strong>The test that matters is {@code theCompanyComesFromTheToken}.</strong> Every route here
 * acts on a company's money, and the defence is structural: there is no company parameter at all,
 * so the only thing that can name one is the caller's own token, exchanged through Order Manager.
 * This tries every shape of "please use the rival instead" and confirms the service is still asked
 * about the caller's company.
 *
 * <p>Standalone MockMvc with no method security, which is exactly why the controller checks the
 * role itself: a rule that only holds when a proxy is present cannot be tested and will one day
 * stop holding.
 */
@DisplayName("who may touch a delivery company's cash")
class CarrierCashAccessTest {

    private static final String COMPANY = "provider-77";
    private static final String RIVAL = "provider-rival";
    private static final String STAFF = "carrier-staff-sub";
    private static final String RIDER = "rider-sub-1";
    private static final LocalDate TODAY = LocalDate.parse("2026-10-24");

    private CarrierCashService cash;
    private CashFloatService cashFloat;
    private CarrierCompanyClient carrierCompanies;
    private MockMvc mvc;

    @BeforeEach
    void setUp() {
        cash = mock(CarrierCashService.class);
        cashFloat = mock(CashFloatService.class);
        carrierCompanies = mock(CarrierCompanyClient.class);
        when(cash.today()).thenReturn(TODAY);
        when(cash.currency()).thenReturn("USD");
        mvc = MockMvcBuilders
                .standaloneSetup(new CarrierCashController(cash, cashFloat, carrierCompanies))
                .build();
    }

    @AfterEach
    void tearDown() {
        SecurityContextHolder.clearContext();
    }

    private static void signedInAs(String subject, String... roles) {
        Jwt jwt = Jwt.withTokenValue("token").header("alg", "none").subject(subject).build();
        SecurityContextHolder.getContext().setAuthentication(new JwtAuthenticationToken(jwt,
                java.util.Arrays.stream(roles)
                        .map(role -> new SimpleGrantedAuthority("ROLE_" + role))
                        .map(org.springframework.security.core.GrantedAuthority.class::cast)
                        .toList()));
    }

    private void asCompanyStaff() {
        signedInAs(STAFF, "CARRIER");
        when(carrierCompanies.companyIdFor("token")).thenReturn(COMPANY);
    }

    private static CarrierCashService.Overview overview() {
        return new CarrierCashService.Overview(TODAY, "USD", 48,
                new CarrierCashService.Totals(new BigDecimal("180"), 2, new BigDecimal("40"), 1,
                        new BigDecimal("485.5"), 3, new BigDecimal("50"), 1),
                List.of(new CarrierCashService.RiderRow(RIDER, "Youssef Kanaan",
                        new BigDecimal("100"), 1, new BigDecimal("2.25"), 1,
                        new BigDecimal("150"), 2, Instant.parse("2026-10-21T10:00:00Z"), null,
                        CarrierCashService.Standing.OVERDUE, 74L)));
    }

    // ------------------------------------------------------------------------------ the company

    @Test
    @DisplayName("reads the caller's own company, however the request names another")
    void theCompanyComesFromTheToken() throws Exception {
        asCompanyStaff();
        when(cash.overview(COMPANY, TODAY)).thenReturn(overview());

        mvc.perform(get("/api/accounting/carrier/cash")
                        .param("carrierRef", RIVAL)
                        .param("company", RIVAL)
                        .param("providerId", RIVAL)
                        .header("X-Company", RIVAL))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.day").value("2026-10-24"))
                .andExpect(jsonPath("$.overdueAfterHours").value(48))
                // Money is a two-decimal string on the wire, never a JSON number.
                .andExpect(jsonPath("$.totals.withRiders").value("180.00"))
                .andExpect(jsonPath("$.totals.held").value("485.50"))
                .andExpect(jsonPath("$.riders[0].holding").value("150.00"))
                .andExpect(jsonPath("$.riders[0].standing").value("OVERDUE"))
                .andExpect(jsonPath("$.riders[0].overdueHours").value(74))
                .andExpect(jsonPath("$.riders[0].lastHandoverAt").doesNotExist());

        verify(cash).overview(COMPANY, TODAY);
        verify(cash, never()).overview(eq(RIVAL), any());
    }

    @Test
    @DisplayName("asks for the day it was given, and refuses one that is not a date")
    void theDay() throws Exception {
        asCompanyStaff();
        when(cash.overview(COMPANY, LocalDate.parse("2026-10-20"))).thenReturn(overview());

        mvc.perform(get("/api/accounting/carrier/cash").param("day", "2026-10-20"))
                .andExpect(status().isOk());
        mvc.perform(get("/api/accounting/carrier/cash").param("day", "last tuesday"))
                .andExpect(status().isBadRequest());
    }

    @ParameterizedTest(name = "{0} is refused")
    @ValueSource(strings = {"BACKOFFICE", "DELIVERY", "MERCHANT", "CUSTOMER"})
    @DisplayName("every other role is refused, before any company is looked up")
    void otherRolesAreRefused(String role) throws Exception {
        signedInAs("somebody", role);

        mvc.perform(get("/api/accounting/carrier/cash")).andExpect(status().isForbidden());
        mvc.perform(get("/api/accounting/carrier/cash/riders/" + RIDER))
                .andExpect(status().isForbidden());
        mvc.perform(get("/api/accounting/carrier/cash/owed")).andExpect(status().isForbidden());
        mvc.perform(get("/api/accounting/carrier/cash/handovers")).andExpect(status().isForbidden());
        mvc.perform(post("/api/accounting/carrier/cash/riders/" + RIDER + "/handovers")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"expectedAmount\":\"10.00\"}"))
                .andExpect(status().isForbidden());

        verifyNoInteractions(carrierCompanies, cashFloat);
        verify(cash, never()).overview(any(), any());
    }

    @Test
    @DisplayName("an anonymous request is told to sign in")
    void anonymous() throws Exception {
        mvc.perform(get("/api/accounting/carrier/cash")).andExpect(status().isUnauthorized());
        verifyNoInteractions(carrierCompanies);
    }

    @Test
    @DisplayName("staff of no company are told so, not shown an empty page")
    void noCompany() throws Exception {
        signedInAs(STAFF, "CARRIER");
        when(carrierCompanies.companyIdFor("token"))
                .thenThrow(new CarrierCompanyClient.NoCompanyException("not staff"));

        mvc.perform(get("/api/accounting/carrier/cash"))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("NO_COMPANY"));
        verify(cash, never()).overview(any(), any());
    }

    @Test
    @DisplayName("an Order Manager outage is a 503, never 'nobody is holding cash'")
    void outage() throws Exception {
        signedInAs(STAFF, "CARRIER");
        when(carrierCompanies.companyIdFor("token"))
                .thenThrow(new IllegalStateException("Order Manager unreachable"));

        mvc.perform(get("/api/accounting/carrier/cash/owed"))
                .andExpect(status().isServiceUnavailable());
        verify(cash, never()).owed(any());
    }

    // ------------------------------------------------------------------------------- the rider

    @Test
    @DisplayName("a rider who never carried cash for this company is not found")
    void anotherCompanysRider() throws Exception {
        asCompanyStaff();
        when(cash.rider(COMPANY, "rival-rider")).thenReturn(Optional.empty());

        mvc.perform(get("/api/accounting/carrier/cash/riders/rival-rider"))
                .andExpect(status().isNotFound());
    }

    @Test
    @DisplayName("a rider's page goes on the wire in two-decimal strings, naming the recorder only")
    void riderPageWireShape() throws Exception {
        asCompanyStaff();
        when(cash.rider(COMPANY, RIDER)).thenReturn(Optional.of(
                new CarrierCashService.RiderSettlement(RIDER, "Youssef Kanaan", "USD", 48,
                        new BigDecimal("265"), new BigDecimal("4.5"),
                        CarrierCashService.Standing.OVERDUE, 74L,
                        List.of(new CarrierCashService.HeldCollection(UUID.randomUUID(),
                                new BigDecimal("120"), Instant.parse("2026-10-21T09:00:00Z"),
                                null, true)),
                        List.of(new CarrierCashService.HandoverView(UUID.randomUUID(), RIDER,
                                "Youssef Kanaan", new BigDecimal("232"), 4,
                                CashFloatEntry.Method.CASH, null, STAFF, "Kamal M.",
                                Instant.parse("2026-10-23T18:00:00Z"))),
                        Instant.parse("2026-10-21T09:00:00Z"))));

        mvc.perform(get("/api/accounting/carrier/cash/riders/" + RIDER))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.holding").value("265.00"))
                .andExpect(jsonPath("$.earnedOnHeld").value("4.50"))
                .andExpect(jsonPath("$.held[0].amount").value("120.00"))
                .andExpect(jsonPath("$.held[0].overdue").value(true))
                // "No figure" stays null on the wire; the client must not see a zero.
                .andExpect(jsonPath("$.held[0].earned").doesNotExist())
                .andExpect(jsonPath("$.handovers[0].amount").value("232.00"))
                .andExpect(jsonPath("$.handovers[0].recordedByName").value("Kamal M."))
                // The recorder's account id never leaves the server, only the name.
                .andExpect(jsonPath("$.handovers[0].recordedBy").doesNotExist());
    }

    @Test
    @DisplayName("what the company owes, and its payments, go on the wire in two-decimal strings")
    void owedWireShape() throws Exception {
        asCompanyStaff();
        when(cash.owed(COMPANY)).thenReturn(new CarrierCashService.Owed("USD", 48,
                new BigDecimal("485"), 2, Instant.parse("2026-10-20T10:00:00Z"), true,
                new BigDecimal("100"), 2,
                List.of(new CarrierCashService.Payment(UUID.randomUUID(), new BigDecimal("900"), 12,
                        CashFloatEntry.Method.BANK_DEPOSIT, Instant.parse("2026-10-19T10:00:00Z")))));

        mvc.perform(get("/api/accounting/carrier/cash/owed"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.held").value("485.00"))
                .andExpect(jsonPath("$.overdue").value(true))
                .andExpect(jsonPath("$.withRiders").value("100.00"))
                .andExpect(jsonPath("$.payments[0].amount").value("900.00"))
                .andExpect(jsonPath("$.payments[0].method").value("BANK_DEPOSIT"));
        verify(cash).owed(COMPANY);
    }

    @Test
    @DisplayName("the hand-over history is the caller's company's, at the size asked for")
    void historyIsTheCompanys() throws Exception {
        asCompanyStaff();
        when(cash.history(COMPANY, 10)).thenReturn(List.of());

        mvc.perform(get("/api/accounting/carrier/cash/handovers").param("limit", "10"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.handovers").isEmpty());
        verify(cash).history(COMPANY, 10);
        verify(cash, never()).history(eq(RIVAL), anyInt());
    }

    // --------------------------------------------------------------------------- the hand-over

    @Nested
    @DisplayName("recording a hand-over")
    class Handing {

        private CashFloatService.Handover recorded(boolean replayed) {
            return new CashFloatService.Handover(UUID.randomUUID(), RIDER, COMPANY,
                    new BigDecimal("485"), 3, CashFloatEntry.Method.CASH, "counted", STAFF,
                    Instant.parse("2026-10-24T11:00:00Z"), replayed);
        }

        @Test
        @DisplayName("records it for the caller's company, by the caller, whatever the body says")
        void recordedByTheCaller() throws Exception {
            asCompanyStaff();
            when(cash.carriesFor(COMPANY, RIDER)).thenReturn(true);
            when(cashFloat.handOver(eq(COMPANY), eq(RIDER), any(), any())).thenReturn(recorded(false));

            mvc.perform(post("/api/accounting/carrier/cash/riders/" + RIDER + "/handovers")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("""
                                    {"expectedAmount":"485.00","method":"cash","note":" counted ",
                                     "requestKey":"key-0000-1111",
                                     "recordedBy":"somebody-else","carrierRef":"%s"}
                                    """.formatted(RIVAL)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.amount").value("485.00"))
                    .andExpect(jsonPath("$.collections").value(3))
                    .andExpect(jsonPath("$.replayed").value(false));

            ArgumentCaptor<BigDecimal> amount = ArgumentCaptor.forClass(BigDecimal.class);
            ArgumentCaptor<CashFloatEntry.Recorded> who =
                    ArgumentCaptor.forClass(CashFloatEntry.Recorded.class);
            verify(cashFloat).handOver(eq(COMPANY), eq(RIDER), amount.capture(), who.capture());
            assertThat(amount.getValue()).isEqualByComparingTo("485.00");
            assertThat(who.getValue().by()).isEqualTo(STAFF);
            assertThat(who.getValue().method()).isEqualTo(CashFloatEntry.Method.CASH);
            assertThat(who.getValue().note()).isEqualTo("counted");
            assertThat(who.getValue().requestKey()).isEqualTo("key-0000-1111");
            verify(cashFloat, never()).handOver(eq(RIVAL), anyString(), any(), any());
        }

        @Test
        @DisplayName("is refused for a rider who never carried cash for this company")
        void notOurRider() throws Exception {
            asCompanyStaff();
            when(cash.carriesFor(COMPANY, "rival-rider")).thenReturn(false);

            mvc.perform(post("/api/accounting/carrier/cash/riders/rival-rider/handovers")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{\"expectedAmount\":\"10.00\"}"))
                    .andExpect(status().isNotFound());
            verifyNoInteractions(cashFloat);
        }

        @Test
        @DisplayName("answers 409 with the current figure when the amount moved")
        void amountChanged() throws Exception {
            asCompanyStaff();
            when(cash.carriesFor(COMPANY, RIDER)).thenReturn(true);
            when(cashFloat.handOver(eq(COMPANY), eq(RIDER), any(), any()))
                    .thenThrow(new CashFloatService.AmountChangedException(new BigDecimal("515.00")));

            mvc.perform(post("/api/accounting/carrier/cash/riders/" + RIDER + "/handovers")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{\"expectedAmount\":\"485.00\"}"))
                    .andExpect(status().isConflict())
                    .andExpect(jsonPath("$.code").value("AMOUNT_CHANGED"))
                    .andExpect(jsonPath("$.current").value("515.00"));
        }

        @Test
        @DisplayName("answers a repeated key with the first hand-over")
        void replayed() throws Exception {
            asCompanyStaff();
            when(cash.carriesFor(COMPANY, RIDER)).thenReturn(true);
            when(cashFloat.handOver(eq(COMPANY), eq(RIDER), any(), any())).thenReturn(recorded(true));

            mvc.perform(post("/api/accounting/carrier/cash/riders/" + RIDER + "/handovers")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{\"expectedAmount\":\"485.00\",\"requestKey\":\"key-0000-1111\"}"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.replayed").value(true));
        }

        @Test
        @DisplayName("refuses a body with no amount, an unknown method, a malformed key or a pay run's key")
        void badBodies() throws Exception {
            asCompanyStaff();
            for (String body : List.of(
                    "{}",
                    "{\"expectedAmount\":\"10.00\",\"method\":\"CHEQUE\"}",
                    // Only an approved pay run writes this. A counter claiming it would mark cash
                    // taken against a rider's pay that nobody took.
                    "{\"expectedAmount\":\"10.00\",\"method\":\"PAYROLL_DEDUCTION\"}",
                    "{\"expectedAmount\":\"10.00\",\"requestKey\":\"a b\"}",
                    // A pay run's key, worked out from the run and the rider. Recorded here first, it
                    // would be replayed as that run's deduction and the rider would pay twice.
                    "{\"expectedAmount\":\"10.00\","
                            + "\"requestKey\":\"payroll-0123456789abcdef0123456789abcdef\"}",
                    "{\"expectedAmount\":\"10.00\",\"requestKey\":\"PAYROLL-0123456789abcdef\"}")) {
                mvc.perform(post("/api/accounting/carrier/cash/riders/" + RIDER + "/handovers")
                                .contentType(MediaType.APPLICATION_JSON)
                                .content(body))
                        .andExpect(status().isBadRequest());
            }
            verifyNoInteractions(cashFloat);
        }
    }
}
