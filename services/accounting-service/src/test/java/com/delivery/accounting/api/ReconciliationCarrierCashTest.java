package com.delivery.accounting.api;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.http.MediaType;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import com.delivery.accounting.domain.AccountingTransactionRepository;
import com.delivery.accounting.domain.CashFloatEntry;
import com.delivery.accounting.domain.CashFloatRepository;
import com.delivery.accounting.domain.CoreBankingSyncLogRepository;
import com.delivery.accounting.service.CarrierCashService;
import com.delivery.accounting.service.CashFloatService;

/**
 * The Back Office's half of carrier custody: seeing what each delivery company holds, and recording
 * the company's payment against the figure the operator actually counted.
 */
@DisplayName("the Back Office and carriers' cash")
class ReconciliationCarrierCashTest {

    private static final String COMPANY = "provider-77";

    private CashFloatRepository floatEntries;
    private CashFloatService cashFloat;
    private CarrierCashService carrierCash;
    private MockMvc mvc;

    @BeforeEach
    void setUp() {
        floatEntries = mock(CashFloatRepository.class);
        cashFloat = mock(CashFloatService.class);
        carrierCash = mock(CarrierCashService.class);
        mvc = MockMvcBuilders.standaloneSetup(new ReconciliationController(
                        mock(AccountingTransactionRepository.class), floatEntries, cashFloat,
                        mock(CoreBankingSyncLogRepository.class), carrierCash))
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

    @Test
    @DisplayName("records a company's payment against the counted amount, by the operator")
    void recordsTheCountedPayment() throws Exception {
        signedInAs("op-1", "BACKOFFICE");
        UUID id = UUID.randomUUID();
        when(cashFloat.remit(eq(COMPANY), any(), any(), any())).thenReturn(Optional.of(
                new CashFloatService.Remittance(id, COMPANY, new BigDecimal("485.00"), 3)));

        mvc.perform(post("/api/accounting/float/" + COMPANY + "/remit")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"expectedAmount":"485.00","method":"BANK_DEPOSIT",
                                 "note":"slip 4471","requestKey":"key-0000-2222"}
                                """))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.remittanceId").value(id.toString()))
                .andExpect(jsonPath("$.collections").value(3));

        ArgumentCaptor<BigDecimal> expected = ArgumentCaptor.forClass(BigDecimal.class);
        ArgumentCaptor<CashFloatEntry.Recorded> who =
                ArgumentCaptor.forClass(CashFloatEntry.Recorded.class);
        verify(cashFloat).remit(eq(COMPANY), any(), expected.capture(), who.capture());
        assertThat(expected.getValue()).isEqualByComparingTo("485.00");
        assertThat(who.getValue().by()).isEqualTo("op-1");
        assertThat(who.getValue().method()).isEqualTo(CashFloatEntry.Method.BANK_DEPOSIT);
        assertThat(who.getValue().note()).isEqualTo("slip 4471");
        assertThat(who.getValue().requestKey()).isEqualTo("key-0000-2222");
    }

    @Test
    @DisplayName("with no body, banks everything as it always did — and still records who")
    void theOldCallStillWorks() throws Exception {
        signedInAs("op-1", "BACKOFFICE");
        when(cashFloat.remit(eq("rider-1"), any(), isNull(), any())).thenReturn(Optional.empty());

        mvc.perform(post("/api/accounting/float/rider-1/remit"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.collections").value(0));

        ArgumentCaptor<CashFloatEntry.Recorded> who =
                ArgumentCaptor.forClass(CashFloatEntry.Recorded.class);
        verify(cashFloat).remit(eq("rider-1"), any(), isNull(), who.capture());
        assertThat(who.getValue().by()).isEqualTo("op-1");
    }

    @Test
    @DisplayName("answers 409 with the current figure when a hand-over landed meanwhile")
    void amountMoved() throws Exception {
        signedInAs("op-1", "BACKOFFICE");
        when(cashFloat.remit(eq(COMPANY), any(), any(), any()))
                .thenThrow(new CashFloatService.AmountChangedException(new BigDecimal("525.00")));

        mvc.perform(post("/api/accounting/float/" + COMPANY + "/remit")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"expectedAmount\":\"485.00\"}"))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("AMOUNT_CHANGED"))
                .andExpect(jsonPath("$.current").value("525.00"));
    }

    @Test
    @DisplayName("a delivery company cannot mark its own debt paid")
    void aCarrierCannotRemit() throws Exception {
        signedInAs("carrier-staff", "CARRIER");

        mvc.perform(post("/api/accounting/float/" + COMPANY + "/remit"))
                .andExpect(status().isForbidden());
        mvc.perform(get("/api/accounting/float/carriers")).andExpect(status().isForbidden());

        verify(cashFloat, never()).remit(any(), any(), any(), any());
        verify(carrierCash, never()).carriers();
    }

    @Test
    @DisplayName("lists what each company holds and what its riders hold, in two-decimal strings")
    void carriersListing() throws Exception {
        signedInAs("op-1", "BACKOFFICE");
        when(carrierCash.overdueAfterHours()).thenReturn(48);
        when(carrierCash.carriers()).thenReturn(List.of(new CarrierCashService.CarrierHolding(
                COMPANY, new BigDecimal("485.5"), 3, Instant.parse("2026-10-20T09:00:00Z"), true,
                new BigDecimal("180"), 2, Instant.parse("2026-10-21T10:00:00Z"), null)));

        mvc.perform(get("/api/accounting/float/carriers"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.overdueAfterHours").value(48))
                .andExpect(jsonPath("$.carriers[0].carrierRef").value(COMPANY))
                .andExpect(jsonPath("$.carriers[0].held").value("485.50"))
                .andExpect(jsonPath("$.carriers[0].withRiders").value("180.00"))
                .andExpect(jsonPath("$.carriers[0].overdue").value(true))
                .andExpect(jsonPath("$.carriers[0].lastPaidAt").doesNotExist());
    }

    @Test
    @DisplayName("flags an overdue holder by the server's own limit")
    void floatCarriesOverdue() throws Exception {
        signedInAs("op-1", "BACKOFFICE");
        Instant old = Instant.parse("2026-10-20T09:00:00Z");
        CashFloatRepository.HolderBalance row = mock(CashFloatRepository.HolderBalance.class);
        when(row.getHolderRef()).thenReturn(COMPANY);
        when(row.getHolderKind()).thenReturn(CashFloatEntry.HolderKind.PROVIDER);
        when(row.getAmount()).thenReturn(new BigDecimal("485.00"));
        when(row.getOrders()).thenReturn(3L);
        when(row.getOldest()).thenReturn(old);
        when(floatEntries.outstandingByHolder()).thenReturn(List.of(row));
        when(carrierCash.isOverdue(old)).thenReturn(true);

        mvc.perform(get("/api/accounting/float"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].holderKind").value("PROVIDER"))
                .andExpect(jsonPath("$[0].overdue").value(true));
    }
}
