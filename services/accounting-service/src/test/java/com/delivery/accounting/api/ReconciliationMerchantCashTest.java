package com.delivery.accounting.api;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
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
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import com.delivery.accounting.domain.AccountingTransactionRepository;
import com.delivery.accounting.domain.CashFloatEntry;
import com.delivery.accounting.domain.CoreBankingSyncLogRepository;
import com.delivery.accounting.service.CarrierCashService;
import com.delivery.accounting.service.CashFloatService;

/**
 * The Back Office and a shop's till (V52): a shop holding pickup cash is on the cash-on-hand list as
 * a shop, and its payment is recorded through the route and the safeguards a delivery company's
 * payment uses — and behind the same lock, because a shop is the one party with a reason to mark
 * its own debt paid.
 */
@DisplayName("the Back Office and a shop's till")
class ReconciliationMerchantCashTest {

    private static final String SHOP = "merchant-sub-1";
    private static final String REMIT = "/api/accounting/float/" + SHOP + "/remit";
    private static final String COUNTED = """
            {"expectedAmount":"52.50","method":"CASH","note":"counted at the shop",
             "requestKey":"till-key-0001"}""";

    private CashFloatService cashFloat;
    private CarrierCashService carrierCash;
    private MockMvc mvc;

    @BeforeEach
    void setUp() {
        cashFloat = mock(CashFloatService.class);
        carrierCash = mock(CarrierCashService.class);
        mvc = MockMvcBuilders.standaloneSetup(new ReconciliationController(
                        mock(AccountingTransactionRepository.class), cashFloat,
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
                        .map(GrantedAuthority.class::cast)
                        .toList()));
    }

    @Test
    @DisplayName("lists a shop holding pickup cash as a shop, with the server's overdue call")
    void listsTheShop() throws Exception {
        signedInAs("op-1", "BACKOFFICE");
        when(carrierCash.cashOnHand()).thenReturn(List.of(new CarrierCashService.OnHand(SHOP,
                CashFloatEntry.HolderKind.MERCHANT, new BigDecimal("52.50"), 2,
                Instant.parse("2026-10-20T09:00:00Z"), true)));

        mvc.perform(get("/api/accounting/float"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].holderRef").value(SHOP))
                .andExpect(jsonPath("$[0].holderKind").value("MERCHANT"))
                .andExpect(jsonPath("$[0].orders").value(2))
                .andExpect(jsonPath("$[0].overdue").value(true));
    }

    @Test
    @DisplayName("records the shop's payment against the counted amount, by the operator")
    void recordsTheCountedTill() throws Exception {
        signedInAs("op-1", "BACKOFFICE");
        UUID id = UUID.randomUUID();
        when(cashFloat.remit(eq(SHOP), any(), any(), any())).thenReturn(Optional.of(
                new CashFloatService.Remittance(id, SHOP, new BigDecimal("52.50"), 2)));

        mvc.perform(post(REMIT).contentType(MediaType.APPLICATION_JSON).content(COUNTED))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.remittanceId").value(id.toString()))
                .andExpect(jsonPath("$.collections").value(2))
                .andExpect(jsonPath("$.replayed").value(false));

        ArgumentCaptor<BigDecimal> expected = ArgumentCaptor.forClass(BigDecimal.class);
        ArgumentCaptor<CashFloatEntry.Recorded> who =
                ArgumentCaptor.forClass(CashFloatEntry.Recorded.class);
        verify(cashFloat).remit(eq(SHOP), any(), expected.capture(), who.capture());
        assertThat(expected.getValue()).isEqualByComparingTo("52.50");
        // Whoever is signed in confirmed it — never a name from the body.
        assertThat(who.getValue().by()).isEqualTo("op-1");
        assertThat(who.getValue().method()).isEqualTo(CashFloatEntry.Method.CASH);
        assertThat(who.getValue().note()).isEqualTo("counted at the shop");
        assertThat(who.getValue().requestKey()).isEqualTo("till-key-0001");
    }

    @Test
    @DisplayName("answers a repeated press with the first payment")
    void aRepeatedPressReplays() throws Exception {
        signedInAs("op-1", "BACKOFFICE");
        UUID first = UUID.randomUUID();
        when(cashFloat.remit(eq(SHOP), any(), any(), any())).thenReturn(Optional.of(
                new CashFloatService.Remittance(first, SHOP, new BigDecimal("52.50"), 2, true)));

        mvc.perform(post(REMIT).contentType(MediaType.APPLICATION_JSON).content(COUNTED))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.remittanceId").value(first.toString()))
                .andExpect(jsonPath("$.replayed").value(true));
    }

    @Test
    @DisplayName("answers 409 with the till's figure when a pickup was paid meanwhile")
    void theTillMoved() throws Exception {
        signedInAs("op-1", "BACKOFFICE");
        when(cashFloat.remit(eq(SHOP), any(), any(), any()))
                .thenThrow(new CashFloatService.AmountChangedException(new BigDecimal("64")));

        mvc.perform(post(REMIT).contentType(MediaType.APPLICATION_JSON).content(COUNTED))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("AMOUNT_CHANGED"))
                .andExpect(jsonPath("$.current").value("64.00"));
    }

    @Test
    @DisplayName("answers 409 to a key that already recorded something else")
    void aReusedKey() throws Exception {
        signedInAs("op-1", "BACKOFFICE");
        when(cashFloat.remit(eq(SHOP), any(), any(), any()))
                .thenThrow(new CashFloatService.RequestKeyReusedException());

        mvc.perform(post(REMIT).contentType(MediaType.APPLICATION_JSON).content(COUNTED))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("REQUEST_KEY_REUSED"));
    }

    /**
     * The in-method lock, proved without the proxy, as for a company: {@code @PreAuthorize} is
     * invisible to a standalone test, and a shop marking its own till paid is exactly the refusal
     * worth seeing.
     */
    @Test
    @DisplayName("a shop can neither mark its own till paid nor read who holds the platform's cash")
    void aShopIsRefused() throws Exception {
        mvc.perform(post(REMIT).contentType(MediaType.APPLICATION_JSON).content(COUNTED))
                .andExpect(status().isUnauthorized());

        signedInAs(SHOP, "MERCHANT");
        mvc.perform(post(REMIT).contentType(MediaType.APPLICATION_JSON).content(COUNTED))
                .andExpect(status().isForbidden());
        mvc.perform(get("/api/accounting/float")).andExpect(status().isForbidden());

        verify(cashFloat, never()).remit(any(), any(), any(), any());
        verify(carrierCash, never()).cashOnHand();
    }
}
