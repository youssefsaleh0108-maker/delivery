package com.delivery.accounting.api;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
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
import org.mockito.ArgumentCaptor;
import org.springframework.http.MediaType;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import com.delivery.accounting.domain.CounterpartyKind;
import com.delivery.accounting.domain.StatementDispatch;
import com.delivery.accounting.service.CarrierCompanyClient;
import com.delivery.accounting.service.Statement;
import com.delivery.accounting.service.StatementDispatchService;
import com.delivery.accounting.service.StatementRange;
import com.delivery.accounting.service.StatementService;

/**
 * Who may read whose money.
 *
 * <p><strong>The test in this file that matters is {@code aMerchantOnlyEverSeesTheirOwn}.</strong>
 * {@code /mine} is the endpoint most likely to leak another shop's revenue, and the defence is
 * structural rather than a check: there is no counterparty parameter on the route at all, so the
 * reference can only come from {@code jwt.getSubject()}. This asserts that by trying every way a
 * caller could name somebody else and confirming the service is still asked about the caller.
 *
 * <p>Standalone MockMvc, matching the pattern the rest of the platform's API tests use. Method
 * security is NOT wired here, which is exactly why the controller checks the roles itself as well:
 * a rule that only holds when a proxy is present is a rule that cannot be tested and will one day
 * stop holding.
 */
@DisplayName("who may read a statement")
class StatementAccessTest {

    private static final String MY_SHOP = "merchant-sub-mine";
    private static final String RIVAL_SHOP = "merchant-sub-rival";

    private StatementService statements;
    private StatementDispatchService dispatch;
    private CarrierCompanyClient carrierCompanies;
    private MockMvc mvc;

    @BeforeEach
    void setUp() {
        statements = mock(StatementService.class);
        dispatch = mock(StatementDispatchService.class);
        carrierCompanies = mock(CarrierCompanyClient.class);
        when(statements.zone()).thenReturn(ZoneId.of("UTC"));
        mvc = MockMvcBuilders
                .standaloneSetup(new StatementController(statements, dispatch, carrierCompanies))
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

    private Statement statementFor(String ref) {
        StatementRange august = StatementRange.of(LocalDate.parse("2026-08-01"),
                LocalDate.parse("2026-08-29"), ZoneId.of("UTC"));
        return Statement.of(CounterpartyKind.MERCHANT, ref, "A Shop", august, "USD",
                List.of(Statement.Line.credit("Goods sold", new BigDecimal("119.50"), "2 orders"),
                        Statement.Line.debit("Platform commission (12.5%)",
                                new BigDecimal("14.94"), null)),
                new BigDecimal("104.56"), List.of(), 2, null);
    }

    // ------------------------------------------------------------------------------------ /mine

    @Nested
    @DisplayName("the self-serve route")
    class Mine {

        @Test
        @DisplayName("shows a merchant only their own figures, however they ask")
        void aMerchantOnlyEverSeesTheirOwn() throws Exception {
            signedInAs(MY_SHOP, "MERCHANT");
            when(statements.build(eq(CounterpartyKind.MERCHANT), eq(MY_SHOP), any()))
                    .thenReturn(statementFor(MY_SHOP));

            // Every shape of "please give me the other shop" a caller could reach for. None of them
            // is a parameter this route reads, and none of them may change the answer.
            mvc.perform(get("/api/accounting/statements/mine")
                            .param("from", "2026-08-01").param("to", "2026-08-29")
                            .param("ref", RIVAL_SHOP)
                            .param("counterpartyRef", RIVAL_SHOP)
                            .param("kind", "MERCHANT")
                            .param("sub", RIVAL_SHOP))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.ref").value(MY_SHOP))
                    .andExpect(jsonPath("$.net.amount").value("104.56"));

            ArgumentCaptor<String> asked = ArgumentCaptor.forClass(String.class);
            verify(statements).build(eq(CounterpartyKind.MERCHANT), asked.capture(), any());
            assertThat(asked.getValue()).isEqualTo(MY_SHOP);
            // And the rival's figures were never even computed.
            verify(statements, never()).build(any(), eq(RIVAL_SHOP), any());
        }

        @Test
        @DisplayName("resolves a rider from their DELIVERY role")
        void deliveryBecomesRider() throws Exception {
            signedInAs("rider-1", "DELIVERY");
            when(statements.build(eq(CounterpartyKind.RIDER), eq("rider-1"), any()))
                    .thenReturn(statementFor("rider-1"));

            mvc.perform(get("/api/accounting/statements/mine")
                            .param("from", "2026-08-01").param("to", "2026-08-29"))
                    .andExpect(status().isOk());

            verify(statements).build(eq(CounterpartyKind.RIDER), eq("rider-1"), any());
        }

        @Test
        @DisplayName("resolves a delivery company from their CARRIER role")
        void carrierBecomesCarrier() throws Exception {
            // The identifier a carrier's legs are ACTUALLY attributed with is Order Manager's
            // provider id, not the Keycloak subject on their token. Asking for legs by the subject
            // matched nothing, and the failure was silent in the worst way: no rows sum to zero,
            // the balance check passes, and the company is shown a legitimate-looking quiet month
            // while its money sits in the ledger under an id nobody looked for.
            signedInAs("carrier-staff-sub", "CARRIER");
            when(carrierCompanies.companyIdFor("token")).thenReturn("provider-77");
            when(statements.build(eq(CounterpartyKind.CARRIER), eq("provider-77"), any()))
                    .thenReturn(statementFor("provider-77"));

            mvc.perform(get("/api/accounting/statements/mine")
                            .param("from", "2026-08-01").param("to", "2026-08-29"))
                    .andExpect(status().isOk());

            verify(statements).build(eq(CounterpartyKind.CARRIER), eq("provider-77"), any());
            // And never by the subject, which is the shape of the bug.
            verify(statements, never())
                    .build(eq(CounterpartyKind.CARRIER), eq("carrier-staff-sub"), any());
        }

        /**
         * Staff of no company is refused, not zeroed.
         *
         * <p>"You are owed nothing" and "you are not attached to a company" are different facts and
         * used to render identically. Only one of them is something the reader can act on.
         */
        @Test
        @DisplayName("a carrier account attached to no company is told so, not shown zero")
        void carrierWithNoCompanyIsRefused() throws Exception {
            signedInAs("carrier-staff-sub", "CARRIER");
            when(carrierCompanies.companyIdFor("token"))
                    .thenThrow(new CarrierCompanyClient.NoCompanyException("not staff"));

            mvc.perform(get("/api/accounting/statements/mine")
                            .param("from", "2026-08-01").param("to", "2026-08-29"))
                    .andExpect(status().isForbidden());

            verify(statements, never()).build(any(), any(), any());
        }

        /**
         * And an outage is not silently converted into "no company", which would read to a carrier
         * as being owed nothing on a day the platform simply could not answer.
         */
        @Test
        @DisplayName("an outage resolving the company is a 503, never an empty statement")
        void carrierLookupOutageIsNotAnEmptyStatement() throws Exception {
            signedInAs("carrier-staff-sub", "CARRIER");
            when(carrierCompanies.companyIdFor("token"))
                    .thenThrow(new IllegalStateException("Order Manager unreachable"));

            mvc.perform(get("/api/accounting/statements/mine")
                            .param("from", "2026-08-01").param("to", "2026-08-29"))
                    .andExpect(status().isServiceUnavailable());

            verify(statements, never()).build(any(), any(), any());
        }

        /** A merchant and a rider are still keyed on the subject; only a carrier is exchanged. */
        @Test
        @DisplayName("no company lookup happens for a merchant")
        void onlyCarriersAreExchanged() throws Exception {
            signedInAs(MY_SHOP, "MERCHANT");
            when(statements.build(eq(CounterpartyKind.MERCHANT), eq(MY_SHOP), any()))
                    .thenReturn(statementFor(MY_SHOP));

            mvc.perform(get("/api/accounting/statements/mine")
                            .param("from", "2026-08-01").param("to", "2026-08-29"))
                    .andExpect(status().isOk());

            verifyNoInteractions(carrierCompanies);
        }

        @Test
        @DisplayName("refuses a customer, who has no statement")
        void aCustomerIsRefused() throws Exception {
            signedInAs("customer-1", "CUSTOMER");

            mvc.perform(get("/api/accounting/statements/mine")
                            .param("from", "2026-08-01").param("to", "2026-08-29"))
                    .andExpect(status().isForbidden());

            // Nothing was computed. A customer's record of what they paid is the order.
            verifyNoInteractions(dispatch);
            verify(statements, never()).build(any(), anyString(), any());
        }

        @Test
        @DisplayName("refuses an operator with no partner role of their own")
        void backofficeHasNoOwnStatement() throws Exception {
            signedInAs("op-1", "BACKOFFICE");

            mvc.perform(get("/api/accounting/statements/mine")
                            .param("from", "2026-08-01").param("to", "2026-08-29"))
                    .andExpect(status().isForbidden());

            verify(statements, never()).build(any(), anyString(), any());
        }

        @Test
        @DisplayName("refuses a request with no token at all")
        void anonymousIsRefused() throws Exception {
            mvc.perform(get("/api/accounting/statements/mine")
                            .param("from", "2026-08-01").param("to", "2026-08-29"))
                    .andExpect(status().isUnauthorized());

            verify(statements, never()).build(any(), anyString(), any());
        }
    }

    // ------------------------------------------------------------------------------- Backoffice

    @Nested
    @DisplayName("the Backoffice routes")
    class Backoffice {

        @Test
        @DisplayName("refuse a merchant reaching for another shop by path")
        void aMerchantCannotNameSomebodyElse() throws Exception {
            signedInAs(MY_SHOP, "MERCHANT");

            mvc.perform(get("/api/accounting/statements/MERCHANT/" + RIVAL_SHOP)
                            .param("from", "2026-08-01").param("to", "2026-08-29"))
                    .andExpect(status().isForbidden());

            // The second lock, and the reason it is written as well as @PreAuthorize: method
            // security is a proxy, and this refusal has to hold without one.
            verify(statements, never()).build(any(), anyString(), any());
        }

        @Test
        @DisplayName("refuse a rider reading the counterparties listing")
        void aRiderCannotListEverybody() throws Exception {
            signedInAs("rider-1", "DELIVERY");

            mvc.perform(get("/api/accounting/statements/counterparties")
                            .param("from", "2026-08-01").param("to", "2026-08-29"))
                    .andExpect(status().isForbidden());

            verify(statements, never()).list(any());
        }

        @Test
        @DisplayName("refuse anonymous callers")
        void anonymousIsRefused() throws Exception {
            mvc.perform(get("/api/accounting/statements/counterparties")
                            .param("from", "2026-08-01").param("to", "2026-08-29"))
                    .andExpect(status().isUnauthorized());
        }

        @Test
        @DisplayName("let an operator read one counterparty's statement")
        void anOperatorMayRead() throws Exception {
            signedInAs("op-1", "BACKOFFICE");
            when(statements.build(eq(CounterpartyKind.MERCHANT), eq(RIVAL_SHOP), any()))
                    .thenReturn(statementFor(RIVAL_SHOP));

            mvc.perform(get("/api/accounting/statements/MERCHANT/" + RIVAL_SHOP)
                            .param("from", "2026-08-01").param("to", "2026-08-29"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.ref").value(RIVAL_SHOP))
                    // Money on the wire is a string with two decimals, never a JSON number.
                    .andExpect(jsonPath("$.lines[0].amount").value("119.50"))
                    .andExpect(jsonPath("$.net.direction").value("WE_OWE"));
        }

        @Test
        @DisplayName("refuse a counterparty kind that is not one")
        void anUnknownKindIsRejected() throws Exception {
            signedInAs("op-1", "BACKOFFICE");

            mvc.perform(get("/api/accounting/statements/SUPPLIER/whoever")
                            .param("from", "2026-08-01").param("to", "2026-08-29"))
                    .andExpect(status().isBadRequest());

            verify(statements, never()).build(any(), anyString(), any());
        }
    }

    // ------------------------------------------------------------------------------- the period

    @Nested
    @DisplayName("the period")
    class Period {

        @BeforeEach
        void asAnOperator() {
            signedInAs("op-1", "BACKOFFICE");
        }

        @Test
        @DisplayName("refuses a range that ends before it starts")
        void invertedIsRejected() throws Exception {
            mvc.perform(get("/api/accounting/statements/MERCHANT/" + MY_SHOP)
                            .param("from", "2026-08-29").param("to", "2026-08-01"))
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.error").value(
                            org.hamcrest.Matchers.containsString("ends before it starts")));

            verify(statements, never()).build(any(), anyString(), any());
        }

        @Test
        @DisplayName("refuses more than a year and a day")
        void oversizedIsRejected() throws Exception {
            mvc.perform(get("/api/accounting/statements/MERCHANT/" + MY_SHOP)
                            .param("from", "2026-01-01").param("to", "2027-06-01"))
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.error").value(
                            org.hamcrest.Matchers.containsString("the most in one request")));
        }

        @Test
        @DisplayName("refuses something that is not a date")
        void nonsenseIsRejected() throws Exception {
            mvc.perform(get("/api/accounting/statements/MERCHANT/" + MY_SHOP)
                            .param("from", "last tuesday").param("to", "2026-08-29"))
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.error").value(
                            org.hamcrest.Matchers.containsString("ISO date")));
        }

        @Test
        @DisplayName("applies the same rules on the self-serve route")
        void mineIsValidatedToo() throws Exception {
            signedInAs(MY_SHOP, "MERCHANT");

            mvc.perform(get("/api/accounting/statements/mine")
                            .param("from", "2026-08-29").param("to", "2026-08-01"))
                    .andExpect(status().isBadRequest());
        }
    }

    // ------------------------------------------------------------------------------------ send

    @Nested
    @DisplayName("sending one")
    class Send {

        @Test
        @DisplayName("is refused for anybody but an operator")
        void merchantsCannotSend() throws Exception {
            signedInAs(MY_SHOP, "MERCHANT");

            mvc.perform(post("/api/accounting/statements/MERCHANT/" + MY_SHOP + "/send")
                            .param("from", "2026-08-01").param("to", "2026-08-29")
                            .contentType(MediaType.APPLICATION_JSON).content("{}"))
                    .andExpect(status().isForbidden());

            verifyNoInteractions(dispatch);
        }

        @Test
        @DisplayName("answers with where it went and what recorded it")
        void reportsTheDispatch() throws Exception {
            signedInAs("op-1", "BACKOFFICE");
            StatementDispatch sent = new StatementDispatch(CounterpartyKind.MERCHANT, MY_SHOP,
                    LocalDate.parse("2026-08-01"), LocalDate.parse("2026-08-29"), "EMAIL",
                    "shop@example.com", new BigDecimal("104.56"), "WE_OWE", "USD", "n-1", "op-1");
            when(dispatch.send(eq(CounterpartyKind.MERCHANT), eq(MY_SHOP), any(), any(),
                    org.mockito.ArgumentMatchers.anyBoolean(), eq("op-1"))).thenReturn(sent);

            mvc.perform(post("/api/accounting/statements/MERCHANT/" + MY_SHOP + "/send")
                            .param("from", "2026-08-01").param("to", "2026-08-29")
                            .contentType(MediaType.APPLICATION_JSON).content("{}"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.sentTo").value("shop@example.com"))
                    .andExpect(jsonPath("$.dispatchId").value(sent.getId().toString()))
                    .andExpect(jsonPath("$.sentAt").exists());
        }

        @Test
        @DisplayName("answers 409 when no address can be resolved and none was given")
        void noRecipientIsAConflict() throws Exception {
            signedInAs("op-1", "BACKOFFICE");
            when(dispatch.send(any(), anyString(), any(), any(),
                    org.mockito.ArgumentMatchers.anyBoolean(), anyString()))
                    .thenThrow(new StatementDispatchService.NoRecipientException(
                            "No email address is on file, and none was supplied."));

            mvc.perform(post("/api/accounting/statements/CARRIER/provider-1/send")
                            .param("from", "2026-08-01").param("to", "2026-08-29")
                            .contentType(MediaType.APPLICATION_JSON).content("{}"))
                    .andExpect(status().isConflict())
                    .andExpect(jsonPath("$.code").value("NO_RECIPIENT"));
        }

        @Test
        @DisplayName("answers 409 with the previous send when the period has already gone")
        void aRepeatIsAConflict() throws Exception {
            signedInAs("op-1", "BACKOFFICE");
            StatementDispatch previous = new StatementDispatch(CounterpartyKind.MERCHANT, MY_SHOP,
                    LocalDate.parse("2026-08-01"), LocalDate.parse("2026-08-29"), "EMAIL",
                    "shop@example.com", new BigDecimal("104.56"), "WE_OWE", "USD", "n-1", "op-1");
            when(dispatch.send(any(), anyString(), any(), any(),
                    org.mockito.ArgumentMatchers.anyBoolean(), anyString()))
                    .thenThrow(new StatementDispatchService.AlreadySentException(previous));

            mvc.perform(post("/api/accounting/statements/MERCHANT/" + MY_SHOP + "/send")
                            .param("from", "2026-08-01").param("to", "2026-08-29")
                            .contentType(MediaType.APPLICATION_JSON).content("{}"))
                    .andExpect(status().isConflict())
                    .andExpect(jsonPath("$.code").value("ALREADY_SENT"))
                    // The refusal quotes when and where, because "already sent" with no details is
                    // an answer the operator has to go and investigate.
                    .andExpect(jsonPath("$.sentTo").value("shop@example.com"))
                    .andExpect(jsonPath("$.sentAt").exists());
        }

        @Test
        @DisplayName("names the operator who sent it, never the counterparty")
        void theSenderIsTheCaller() throws Exception {
            signedInAs("op-1", "BACKOFFICE");
            StatementDispatch sent = new StatementDispatch(CounterpartyKind.MERCHANT, MY_SHOP,
                    LocalDate.parse("2026-08-01"), LocalDate.parse("2026-08-29"), "EMAIL",
                    "override@example.com", new BigDecimal("104.56"), "WE_OWE", "USD", null,
                    "op-1");
            when(dispatch.send(any(), anyString(), any(), any(),
                    org.mockito.ArgumentMatchers.anyBoolean(), anyString())).thenReturn(sent);

            mvc.perform(post("/api/accounting/statements/MERCHANT/" + MY_SHOP + "/send")
                            .param("from", "2026-08-01").param("to", "2026-08-29")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{\"to\":\"override@example.com\"}"))
                    .andExpect(status().isOk());

            verify(dispatch).send(eq(CounterpartyKind.MERCHANT), eq(MY_SHOP), any(),
                    eq("override@example.com"), eq(false), eq("op-1"));
        }
    }

    @Test
    @DisplayName("the counterparties listing carries the unattributed remainder")
    void listingCarriesTheRemainder() throws Exception {
        signedInAs("op-1", "BACKOFFICE");
        StatementRange august = StatementRange.of(LocalDate.parse("2026-08-01"),
                LocalDate.parse("2026-08-29"), ZoneId.of("UTC"));
        when(statements.list(any())).thenReturn(new StatementService.Counterparties(
                august, "USD", List.of(),
                new StatementService.Unattributed(new BigDecimal("2121.80"), 45,
                        "45 orders cannot be assigned.")));

        mvc.perform(get("/api/accounting/statements/counterparties")
                        .param("from", "2026-08-01").param("to", "2026-08-29"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.from").value("2026-08-01"))
                .andExpect(jsonPath("$.currency").value("USD"))
                // The number that says the ledger holds far more money than the listing above it.
                .andExpect(jsonPath("$.unattributed.amount").value("2121.80"))
                .andExpect(jsonPath("$.unattributed.orders").value(45));
    }
}
