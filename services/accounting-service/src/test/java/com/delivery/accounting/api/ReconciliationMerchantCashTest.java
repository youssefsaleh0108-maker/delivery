package com.delivery.accounting.api;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.hamcrest.Matchers.startsWith;
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
import com.delivery.accounting.service.ShopTill;

/**
 * The Back Office and a shop's till (V52). A shop holding pickup cash is on the cash-on-hand list as
 * a shop, with what it owes out of its till beside the till. Its payment is recorded through the
 * route a delivery company's payment uses, against what it owes and never the till, and behind the
 * same lock, because a shop is the one party with a reason to mark its own debt paid.
 */
@DisplayName("the Back Office and a shop's till")
class ReconciliationMerchantCashTest {

    private static final String SHOP = "merchant-sub-1";
    private static final String REMIT = "/api/accounting/float/" + SHOP + "/remit";
    /** What the page sends for a shop: what it owes, how it was paid, a key, and who is paying. */
    private static final String COUNTED = """
            {"expectedAmount":"5.00","method":"CASH","note":"counted at the shop",
             "requestKey":"till-key-0001","holderKind":"MERCHANT"}""";

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
    @DisplayName("lists a shop as a shop: its till, what it owes out of it, and the overdue call")
    void listsTheShop() throws Exception {
        signedInAs("op-1", "BACKOFFICE");
        when(carrierCash.cashOnHand()).thenReturn(List.of(new CarrierCashService.OnHand(SHOP,
                CashFloatEntry.HolderKind.MERCHANT, new BigDecimal("40.00"), 1,
                Instant.parse("2026-10-20T09:00:00Z"), true)));
        when(cashFloat.shopTills()).thenReturn(Map.of(SHOP, new ShopTill(
                new BigDecimal("40.00"), new BigDecimal("35.00"), new BigDecimal("5.00"))));

        mvc.perform(get("/api/accounting/float"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].holderRef").value(SHOP))
                .andExpect(jsonPath("$[0].holderKind").value("MERCHANT"))
                .andExpect(jsonPath("$[0].amount").value(40.0))
                .andExpect(jsonPath("$[0].orders").value(1))
                .andExpect(jsonPath("$[0].overdue").value(true))
                // The figure the operator confirms when the shop pays, and the share it keeps.
                .andExpect(jsonPath("$[0].owed").value("5.00"))
                .andExpect(jsonPath("$[0].retained").value("35.00"));
    }

    @Test
    @DisplayName("says nothing of a till beside a rider, and reads no tills for a list with no shop")
    void aRiderHasNoTill() throws Exception {
        signedInAs("op-1", "BACKOFFICE");
        when(carrierCash.cashOnHand()).thenReturn(List.of(new CarrierCashService.OnHand("rider-1",
                CashFloatEntry.HolderKind.RIDER, new BigDecimal("13.25"), 1,
                Instant.parse("2026-10-20T09:00:00Z"), false)));

        mvc.perform(get("/api/accounting/float"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].holderKind").value("RIDER"))
                // RECON-03: a rider's line owed to the platform carries the figure a "banked" is
                // confirmed against — the whole bag, since a rider keeps no share of it — and no
                // share kept, which only a shop's till has.
                .andExpect(jsonPath("$[0].owed").value("13.25"))
                .andExpect(jsonPath("$[0].retained").doesNotExist());
        verify(cashFloat, never()).shopTills();
    }

    @Test
    @DisplayName("records the shop's payment against what it owes, as the shop, by the operator")
    void recordsTheShopsPayment() throws Exception {
        signedInAs("op-1", "BACKOFFICE");
        UUID id = UUID.randomUUID();
        when(cashFloat.remit(eq(SHOP), any(), any(), any(), any())).thenReturn(Optional.of(
                new CashFloatService.Remittance(id, SHOP, new BigDecimal("5.00"), 1, false,
                        new BigDecimal("35.00"))));

        mvc.perform(post(REMIT).contentType(MediaType.APPLICATION_JSON).content(COUNTED))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.remittanceId").value(id.toString()))
                .andExpect(jsonPath("$.amount").value(5.0))
                .andExpect(jsonPath("$.retained").value(35.0))
                .andExpect(jsonPath("$.collections").value(1))
                .andExpect(jsonPath("$.replayed").value(false));

        ArgumentCaptor<BigDecimal> expected = ArgumentCaptor.forClass(BigDecimal.class);
        ArgumentCaptor<CashFloatEntry.Recorded> who =
                ArgumentCaptor.forClass(CashFloatEntry.Recorded.class);
        verify(cashFloat).remit(eq(SHOP), any(), expected.capture(), who.capture(),
                eq(CashFloatEntry.HolderKind.MERCHANT));
        assertThat(expected.getValue()).isEqualByComparingTo("5.00");
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
        when(cashFloat.remit(eq(SHOP), any(), any(), any(), any())).thenReturn(Optional.of(
                new CashFloatService.Remittance(first, SHOP, new BigDecimal("5.00"), 1, true,
                        new BigDecimal("35.00"))));

        mvc.perform(post(REMIT).contentType(MediaType.APPLICATION_JSON).content(COUNTED))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.remittanceId").value(first.toString()))
                .andExpect(jsonPath("$.replayed").value(true));
    }

    @Test
    @DisplayName("answers 409 with what the shop owes now when a pickup was paid meanwhile")
    void theTillMoved() throws Exception {
        signedInAs("op-1", "BACKOFFICE");
        when(cashFloat.remit(eq(SHOP), any(), any(), any(), any()))
                .thenThrow(new CashFloatService.AmountChangedException(new BigDecimal("6.56")));

        mvc.perform(post(REMIT).contentType(MediaType.APPLICATION_JSON).content(COUNTED))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("AMOUNT_CHANGED"))
                .andExpect(jsonPath("$.current").value("6.56"))
                .andExpect(jsonPath("$.error").value(startsWith("The shop owes 6.56 now")));
    }

    @Test
    @DisplayName("answers 409 to a key that already recorded something else")
    void aReusedKey() throws Exception {
        signedInAs("op-1", "BACKOFFICE");
        when(cashFloat.remit(eq(SHOP), any(), any(), any(), any()))
                .thenThrow(new CashFloatService.RequestKeyReusedException());

        mvc.perform(post(REMIT).contentType(MediaType.APPLICATION_JSON).content(COUNTED))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("REQUEST_KEY_REUSED"));
    }

    @Test
    @DisplayName("answers 409 when an account holding a till and a rider's bag was not told which "
            + "is paying")
    void anAccountHoldingBothMustSayWhich() throws Exception {
        signedInAs("op-1", "BACKOFFICE");
        when(cashFloat.remit(eq(SHOP), any(), any(), any(), isNull()))
                .thenThrow(new CashFloatService.HolderKindRequiredException());

        mvc.perform(post(REMIT).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"expectedAmount\":\"53.25\",\"requestKey\":\"till-key-0002\"}"))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("HOLDER_KIND_REQUIRED"));
    }

    @Test
    @DisplayName("answers 400 to a shop's payment that names no amount")
    void aShopsTillNeedsItsAmount() throws Exception {
        signedInAs("op-1", "BACKOFFICE");
        when(cashFloat.remit(eq(SHOP), any(), isNull(), any(), isNull()))
                .thenThrow(new CashFloatService.AmountRequiredException());

        // What a page from before V52 sent: no body at all.
        mvc.perform(post(REMIT))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("AMOUNT_REQUIRED"));
    }

    @Test
    @DisplayName("refuses a holder kind nobody defined, recording nothing")
    void anUnknownKindIsRefused() throws Exception {
        signedInAs("op-1", "BACKOFFICE");

        mvc.perform(post(REMIT).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"expectedAmount\":\"5.00\",\"holderKind\":\"CUSTOMER\"}"))
                .andExpect(status().isBadRequest());
        verify(cashFloat, never()).remit(any(), any(), any(), any(), any());
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

        verify(cashFloat, never()).remit(any(), any(), any(), any(), any());
        verify(cashFloat, never()).shopTills();
        verify(carrierCash, never()).cashOnHand();
    }
}
