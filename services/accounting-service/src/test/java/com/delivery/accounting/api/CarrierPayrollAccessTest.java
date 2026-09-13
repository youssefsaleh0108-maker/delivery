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
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.mockito.ArgumentCaptor;
import org.springframework.http.MediaType;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import com.delivery.accounting.domain.CarrierPayLine;
import com.delivery.accounting.domain.CarrierPayLine.Kind;
import com.delivery.accounting.domain.CarrierPayPolicy;
import com.delivery.accounting.domain.CarrierPayPolicy.PayCycle;
import com.delivery.accounting.domain.CarrierPayRun;
import com.delivery.accounting.domain.CarrierPayslip;
import com.delivery.accounting.domain.CashFloatEntry.Method;
import com.delivery.accounting.service.CarrierCompanyClient;
import com.delivery.accounting.service.CarrierPayrollService;
import com.delivery.accounting.service.CarrierPayrollService.Approval;
import com.delivery.accounting.service.CarrierPayrollService.ApprovalOutcome;
import com.delivery.accounting.service.CarrierPayrollService.PayrollRefusal;
import com.delivery.accounting.service.CarrierPayrollService.RunView;
import com.delivery.accounting.service.CashFloatService;

/**
 * Who may run a delivery company's payroll.
 *
 * <p>The defence is the same as on the company's cash routes, and so is the proof: no route takes a
 * company, so {@code theCompanyComesFromTheToken} tries every way a request could name a rival and
 * confirms the service is still asked about the caller's own company; every other role is refused
 * before any company is looked up; and who did something is always the token's subject.
 *
 * <p>Standalone MockMvc with no method security — which is why the controller checks the role
 * itself, and why this test can prove it does.
 */
@DisplayName("who may run a delivery company's payroll")
class CarrierPayrollAccessTest {

    private static final String BASE = "/api/accounting/carrier/payroll";
    private static final String COMPANY = "provider-77";
    private static final String RIVAL = "provider-rival";
    private static final String STAFF = "carrier-staff-sub";
    private static final String RIDER = "rider-youssef";
    private static final UUID RUN = UUID.fromString("7a1f3a52-7f5e-4c61-9d2f-0c9a8f4d2b11");
    private static final UUID SLIP = UUID.fromString("0e6f9b0c-5c55-4a1e-8b2c-3f1d7d9a4e22");

    private CarrierPayrollService payroll;
    private CarrierCompanyClient carrierCompanies;
    private MockMvc mvc;

    @BeforeEach
    void setUp() {
        payroll = mock(CarrierPayrollService.class);
        carrierCompanies = mock(CarrierCompanyClient.class);
        mvc = MockMvcBuilders
                .standaloneSetup(new CarrierPayrollController(payroll, carrierCompanies))
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

    private void asCompanyStaff() {
        signedInAs(STAFF, "CARRIER");
        when(carrierCompanies.companyIdFor("token")).thenReturn(COMPANY);
    }

    private static MockHttpServletRequestBuilder json(MockHttpServletRequestBuilder request,
                                                      String body) {
        return request.contentType(MediaType.APPLICATION_JSON).content(body);
    }

    /** Every route, with a body it would accept. */
    private static List<MockHttpServletRequestBuilder> everyRoute() {
        String run = BASE + "/runs/" + RUN;
        return List.of(
                get(BASE + "/policy"),
                json(post(BASE + "/policy"), "{\"effectiveFrom\":\"2026-10-16\",\"perDeliveryRate\":\"2.00\"}"),
                get(BASE + "/periods"),
                json(post(BASE + "/runs"), "{\"periodFrom\":\"2026-10-01\"}"),
                get(run),
                post(run + "/recompute"),
                delete(run),
                json(post(run + "/lines"), "{\"riderRef\":\"r\",\"kind\":\"BONUS\",\"label\":\"x\",\"amount\":\"1.00\"}"),
                delete(run + "/lines/" + UUID.randomUUID()),
                json(post(run + "/approve"), "{\"revision\":1}"),
                json(post(run + "/payslips/" + SLIP + "/paid"), "{\"method\":\"CASH\"}"),
                json(post(run + "/payslips/" + SLIP + "/failed"), "{\"reason\":\"x\"}"),
                json(post(run + "/pay"), "{\"expectedTotal\":\"1.00\",\"method\":\"CASH\"}"),
                json(post(run + "/corrections"), "{\"riderRef\":\"r\",\"kind\":\"BONUS\",\"amount\":\"1.00\",\"reason\":\"x\"}"));
    }

    /** A run's page built from real entities, so the wire shape is proved on what the service returns. */
    private static RunView runView() {
        Instant at = Instant.parse("2026-10-20T09:00:00Z");
        CarrierPayPolicy policy = CarrierPayPolicy.version(COMPANY, LocalDate.parse("2026-09-01"),
                new CarrierPayPolicy.Terms(PayCycle.SEMI_MONTHLY, new BigDecimal("2.35"),
                        new BigDecimal("4.00"), true, new BigDecimal("1.50"),
                        new BigDecimal("0.00"), new BigDecimal("0.00")),
                "USD", STAFF, at);
        CarrierPayRun run = CarrierPayRun.draft(COMPANY, LocalDate.parse("2026-10-01"),
                LocalDate.parse("2026-10-15"), policy.getId(), "USD", STAFF, at);
        run.recomputed(policy.getId(), CarrierPayRun.Attendance.INCLUDED, null, at,
                CarrierPayRun.Deliveries.ORDERS, null, at, at);
        CarrierPayslip slip = CarrierPayslip.draft(run.getId(), RIDER, new CarrierPayslip.Figures(
                17, 28_800L, 0L, 0L, 0, 0,
                new BigDecimal("32.00"), new BigDecimal("39.95"), new BigDecimal("25.00"),
                new BigDecimal("60.00"), new BigDecimal("96.95"), new BigDecimal("36.95"),
                new BigDecimal("15.00"), new BigDecimal("60.00"), new BigDecimal("60.00")));
        CarrierPayLine deliveries = CarrierPayLine.computed(run.getId(), RIDER, Kind.DELIVERIES,
                new BigDecimal("17.0000"), new BigDecimal("2.3500"), new BigDecimal("39.95"), at);
        CarrierPayLine hours = CarrierPayLine.computed(run.getId(), RIDER, Kind.HOURS,
                new BigDecimal("8.0000"), new BigDecimal("4.0000"), new BigDecimal("32.00"), at);
        CarrierPayLine bonus = CarrierPayLine.manual(run.getId(), RIDER, Kind.BONUS, "Eid bonus",
                new BigDecimal("25.00"), STAFF, at);
        CarrierPayrollService.Totals totals = new CarrierPayrollService.Totals(1,
                new BigDecimal("36.95"), new BigDecimal("36.95"), new BigDecimal("96.95"),
                new BigDecimal("25"), new BigDecimal("60"), BigDecimal.ZERO, new BigDecimal("15"),
                new BigDecimal("60"), BigDecimal.ZERO, BigDecimal.ZERO, 0, 0, 0);
        return new RunView(run, new CarrierPayrollService.PolicyView(policy, "Kamal M."), null,
                List.of(new CarrierPayrollService.PayslipView(slip, "Youssef Kanaan",
                        List.of(new CarrierPayrollService.LineView(deliveries, null),
                                new CarrierPayrollService.LineView(hours, null),
                                new CarrierPayrollService.LineView(bonus, "Kamal M.")),
                        false, null, null)),
                totals, List.of(), List.of(), true, 2, false, false, false);
    }

    // ----------------------------------------------------------------------------- the company

    @Test
    @DisplayName("works on the caller's own company, however the request names another")
    void theCompanyComesFromTheToken() throws Exception {
        asCompanyStaff();
        when(payroll.periods(COMPANY)).thenReturn(new CarrierPayrollService.PeriodsPage(
                "Asia/Beirut", "USD", LocalDate.parse("2026-10-20"), true, List.of()));
        when(payroll.start(eq(COMPANY), any(), eq(STAFF), eq("token"))).thenReturn(runView());

        mvc.perform(get(BASE + "/periods")
                        .param("carrierRef", RIVAL)
                        .param("company", RIVAL)
                        .header("X-Company", RIVAL))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.hasPolicy").value(true));
        mvc.perform(json(post(BASE + "/runs"),
                        "{\"periodFrom\":\"2026-10-01\",\"carrierRef\":\"" + RIVAL + "\"}"))
                .andExpect(status().isCreated());

        verify(payroll).periods(COMPANY);
        verify(payroll).start(COMPANY, LocalDate.parse("2026-10-01"), STAFF, "token");
        verify(payroll, never()).periods(RIVAL);
    }

    @ParameterizedTest(name = "{0} is refused")
    @ValueSource(strings = {"BACKOFFICE", "DELIVERY", "MERCHANT", "CUSTOMER"})
    @DisplayName("every other role is refused on every route, before any company is looked up")
    void otherRolesAreRefused(String role) throws Exception {
        signedInAs("somebody", role);

        for (MockHttpServletRequestBuilder request : everyRoute()) {
            mvc.perform(request).andExpect(status().isForbidden());
        }
        verifyNoInteractions(carrierCompanies, payroll);
    }

    @Test
    @DisplayName("an anonymous request is told to sign in, on every route")
    void anonymous() throws Exception {
        for (MockHttpServletRequestBuilder request : everyRoute()) {
            mvc.perform(request).andExpect(status().isUnauthorized());
        }
        verifyNoInteractions(carrierCompanies, payroll);
    }

    @Test
    @DisplayName("staff of no company are told so, and an Order Manager outage is a 503")
    void noCompanyAndOutage() throws Exception {
        signedInAs(STAFF, "CARRIER");
        when(carrierCompanies.companyIdFor("token"))
                .thenThrow(new CarrierCompanyClient.NoCompanyException("not staff"));
        mvc.perform(get(BASE + "/periods"))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("NO_COMPANY"));

        doThrow(new IllegalStateException("Order Manager unreachable"))
                .when(carrierCompanies).companyIdFor("token");
        mvc.perform(get(BASE + "/runs/" + RUN)).andExpect(status().isServiceUnavailable());
        verifyNoInteractions(payroll);
    }

    // --------------------------------------------------------------------------------- the run

    @Test
    @DisplayName("another company's run is not found, and an id that is no id asks nothing")
    void anotherCompanysRun() throws Exception {
        asCompanyStaff();
        when(payroll.run(COMPANY, RUN)).thenReturn(Optional.empty());
        when(payroll.approve(COMPANY, RUN, 1, false, STAFF))
                .thenThrow(new PayrollRefusal(404, "RUN_NOT_FOUND", "not yours"));

        mvc.perform(get(BASE + "/runs/" + RUN))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code").value("RUN_NOT_FOUND"));
        mvc.perform(json(post(BASE + "/runs/" + RUN + "/approve"), "{\"revision\":1}"))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code").value("RUN_NOT_FOUND"));
        mvc.perform(get(BASE + "/runs/not-a-run")).andExpect(status().isNotFound());
        mvc.perform(json(post(BASE + "/runs/not-a-run/approve"), "{\"revision\":1}"))
                .andExpect(status().isNotFound());

        verify(payroll, times(1)).run(any(), any());
        verify(payroll, times(1)).approve(any(), any(), anyInt(), eq(false), any());
    }

    @Test
    @DisplayName("a run goes on the wire in two-decimal strings, naming people and never their ids")
    void runWireShape() throws Exception {
        asCompanyStaff();
        RunView view = runView();
        when(payroll.run(COMPANY, view.run().getId())).thenReturn(Optional.of(view));

        mvc.perform(get(BASE + "/runs/" + view.run().getId()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("DRAFT"))
                .andExpect(jsonPath("$.revision").value(1))
                .andExpect(jsonPath("$.attendance").value("INCLUDED"))
                .andExpect(jsonPath("$.attendanceAt").value("2026-10-20T09:00:00Z"))
                .andExpect(jsonPath("$.deliveries").value("ORDERS"))
                .andExpect(jsonPath("$.deliveriesReason").doesNotExist())
                .andExpect(jsonPath("$.deliveriesAt").value("2026-10-20T09:00:00Z"))
                .andExpect(jsonPath("$.readBeforePeriodEnd").value(false))
                .andExpect(jsonPath("$.jobsSinceComputed").value(2))
                .andExpect(jsonPath("$.policy.perDeliveryRate").value("2.35"))
                .andExpect(jsonPath("$.policy.overtimeMultiplier").value("1.50"))
                .andExpect(jsonPath("$.policy.createdByName").value("Kamal M."))
                .andExpect(jsonPath("$.policy.createdBy").doesNotExist())
                .andExpect(jsonPath("$.totals.payable").value("36.95"))
                .andExpect(jsonPath("$.totals.bonuses").value("25.00"))
                .andExpect(jsonPath("$.totals.owedByRiders").value("0.00"))
                .andExpect(jsonPath("$.payslips[0].name").value("Youssef Kanaan"))
                .andExpect(jsonPath("$.payslips[0].deliveryPay").value("39.95"))
                .andExpect(jsonPath("$.payslips[0].net").value("36.95"))
                .andExpect(jsonPath("$.payslips[0].cashNetted").value("60.00"))
                .andExpect(jsonPath("$.payslips[0].tips").value("15.00"))
                .andExpect(jsonPath("$.payslips[0].workedSeconds").value(28800))
                .andExpect(jsonPath("$.payslips[0].lines[0].quantity").value("17"))
                .andExpect(jsonPath("$.payslips[0].lines[0].rate").value("2.35"))
                .andExpect(jsonPath("$.payslips[0].lines[1].quantity").value("8.00"))
                .andExpect(jsonPath("$.payslips[0].lines[1].rate").value("4.00"))
                .andExpect(jsonPath("$.payslips[0].lines[2].label").value("Eid bonus"))
                .andExpect(jsonPath("$.payslips[0].lines[2].createdByName").value("Kamal M."))
                .andExpect(jsonPath("$.payslips[0].lines[2].createdBy").doesNotExist())
                .andExpect(jsonPath("$.payslips[0].paidBy").doesNotExist());
    }

    @Test
    @DisplayName("an approval that did not happen says why, with the run as it now is")
    void approvalOutcomes() throws Exception {
        asCompanyStaff();
        RunView view = runView();
        String approve = BASE + "/runs/" + RUN + "/approve";
        when(payroll.approve(COMPANY, RUN, 1, false, STAFF))
                .thenReturn(new Approval(ApprovalOutcome.FIGURES_CHANGED, view));
        when(payroll.approve(COMPANY, RUN, 2, false, STAFF))
                .thenReturn(new Approval(ApprovalOutcome.NEEDS_ACKNOWLEDGEMENT, view));
        when(payroll.approve(COMPANY, RUN, 2, true, STAFF))
                .thenReturn(new Approval(ApprovalOutcome.APPROVED, view));
        when(payroll.approve(COMPANY, RUN, 3, false, STAFF))
                .thenThrow(new CashFloatService.AmountChangedException(new BigDecimal("75.00")));
        when(payroll.approve(COMPANY, RUN, 4, false, STAFF))
                .thenThrow(new PayrollRefusal(409, "RECOMPUTE_NEEDED", "read before it ended"));

        mvc.perform(json(post(approve), "{\"revision\":1}"))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("FIGURES_CHANGED"))
                .andExpect(jsonPath("$.run.revision").value(1));
        mvc.perform(json(post(approve), "{\"revision\":2}"))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("NEEDS_ACKNOWLEDGEMENT"));
        mvc.perform(json(post(approve), "{\"revision\":2,\"acknowledgeMissing\":true}"))
                .andExpect(status().isOk());
        mvc.perform(json(post(approve), "{\"revision\":3}"))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("CASH_CHANGED"));
        mvc.perform(json(post(approve), "{\"revision\":4}"))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("RECOMPUTE_NEEDED"));
    }

    @Test
    @DisplayName("paying everything at once says the current total when it moved")
    void payAllTotalChanged() throws Exception {
        asCompanyStaff();
        when(payroll.payAll(eq(COMPANY), eq(RUN), any(), eq(Method.CASH), isNull(), eq(STAFF)))
                .thenThrow(new PayrollRefusal(409, "TOTAL_CHANGED", "moved", new BigDecimal("4")));

        mvc.perform(json(post(BASE + "/runs/" + RUN + "/pay"),
                        "{\"expectedTotal\":\"6.00\",\"method\":\"CASH\"}"))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("TOTAL_CHANGED"))
                .andExpect(jsonPath("$.current").value("4.00"));

        ArgumentCaptor<BigDecimal> total = ArgumentCaptor.forClass(BigDecimal.class);
        verify(payroll).payAll(eq(COMPANY), eq(RUN), total.capture(), eq(Method.CASH), isNull(),
                eq(STAFF));
        assertThat(total.getValue()).isEqualByComparingTo("6.00");
    }

    @Test
    @DisplayName("a body that could not be right is refused before the payroll is asked anything")
    void badBodies() throws Exception {
        asCompanyStaff();
        String run = BASE + "/runs/" + RUN;
        for (MockHttpServletRequestBuilder request : List.of(
                json(post(BASE + "/policy"), "{\"effectiveFrom\":\"2026-10-16\"}"),
                json(post(BASE + "/policy"), "{\"effectiveFrom\":\"soon\",\"perDeliveryRate\":\"2.00\"}"),
                json(post(BASE + "/policy"), "{\"effectiveFrom\":\"2026-10-16\",\"perDeliveryRate\":\"2.00\",\"payCycle\":\"WEEKLY\"}"),
                json(post(BASE + "/runs"), "{}"),
                json(post(run + "/lines"), "{\"riderRef\":\"r\",\"kind\":\"TIP\",\"label\":\"x\",\"amount\":\"1.00\"}"),
                json(post(run + "/lines"), "{\"kind\":\"BONUS\",\"label\":\"x\",\"amount\":\"1.00\"}"),
                json(post(run + "/approve"), "{}"),
                // Only an approved pay run writes a payroll deduction; nobody pays a rider with one.
                json(post(run + "/payslips/" + SLIP + "/paid"), "{\"method\":\"PAYROLL_DEDUCTION\"}"),
                json(post(run + "/pay"), "{\"expectedTotal\":\"1.00\",\"method\":\"PAYROLL_DEDUCTION\"}"),
                json(post(run + "/corrections"), "{\"riderRef\":\"r\",\"kind\":\"CASH_HELD\",\"amount\":\"1.00\",\"reason\":\"x\"}"))) {
            mvc.perform(request).andExpect(status().isBadRequest());
        }
        verifyNoInteractions(payroll);
    }

    @Test
    @DisplayName("rules left unsaid take the defaults the owner has not overruled")
    void policyDefaults() throws Exception {
        asCompanyStaff();
        CarrierPayPolicy saved = CarrierPayPolicy.version(COMPANY, LocalDate.parse("2026-10-16"),
                new CarrierPayPolicy.Terms(PayCycle.SEMI_MONTHLY, new BigDecimal("2.50"), null,
                        true, new BigDecimal("1.00"), new BigDecimal("0.00"),
                        new BigDecimal("0.00")),
                "USD", STAFF, Instant.parse("2026-10-20T09:00:00Z"));
        when(payroll.setPolicy(eq(COMPANY), any(), any(), eq(STAFF)))
                .thenReturn(new CarrierPayrollService.PolicyView(saved, "Kamal M."));

        mvc.perform(json(post(BASE + "/policy"),
                        "{\"effectiveFrom\":\"2026-10-16\",\"perDeliveryRate\":\"2.50\","
                                + "\"createdBy\":\"somebody-else\"}"))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.perDeliveryRate").value("2.50"))
                .andExpect(jsonPath("$.hourlyRate").doesNotExist())
                .andExpect(jsonPath("$.createdByName").value("Kamal M."));

        ArgumentCaptor<CarrierPayPolicy.Terms> terms =
                ArgumentCaptor.forClass(CarrierPayPolicy.Terms.class);
        verify(payroll).setPolicy(eq(COMPANY), eq(LocalDate.parse("2026-10-16")), terms.capture(),
                eq(STAFF));
        assertThat(terms.getValue().cycle()).isEqualTo(PayCycle.SEMI_MONTHLY);
        assertThat(terms.getValue().hourlyRate()).isNull();
        assertThat(terms.getValue().payManualHours()).isTrue();
        assertThat(terms.getValue().overtimeMultiplier()).isEqualByComparingTo("1.00");
        assertThat(terms.getValue().lateDeduction()).isEqualByComparingTo("0.00");
        assertThat(terms.getValue().absenceDeduction()).isEqualByComparingTo("0.00");
    }

    @Test
    @DisplayName("whatever the body claims, the caller is who recorded it")
    void recordedByTheCaller() throws Exception {
        asCompanyStaff();
        RunView view = runView();
        String run = BASE + "/runs/" + RUN;
        when(payroll.markPaid(any(), any(), any(), any(), any(), any())).thenReturn(view);
        when(payroll.markFailed(any(), any(), any(), any(), any())).thenReturn(view);
        when(payroll.addLine(any(), any(), any(), any(), any(), any(), any())).thenReturn(view);
        when(payroll.addCorrection(any(), any(), any(), any(), any(), any(), any())).thenReturn(view);
        when(payroll.recompute(any(), any(), any(), any())).thenReturn(view);

        mvc.perform(json(post(run + "/payslips/" + SLIP + "/paid"),
                        "{\"method\":\"bank_deposit\",\"reference\":\"TRX-9\",\"paidBy\":\"somebody-else\"}"))
                .andExpect(status().isOk());
        mvc.perform(json(post(run + "/payslips/" + SLIP + "/failed"),
                        "{\"reason\":\"Wrong account\",\"failedBy\":\"somebody-else\"}"))
                .andExpect(status().isOk());
        mvc.perform(json(post(run + "/lines"),
                        "{\"riderRef\":\" rider-youssef \",\"kind\":\"bonus\",\"label\":\"Eid\","
                                + "\"amount\":\"25.00\",\"createdBy\":\"somebody-else\"}"))
                .andExpect(status().isOk());
        mvc.perform(json(post(run + "/corrections"),
                        "{\"riderRef\":\"rider-youssef\",\"kind\":\"DEDUCTION\",\"amount\":\"4.50\","
                                + "\"reason\":\"Counted twice\"}"))
                .andExpect(status().isOk());
        mvc.perform(post(run + "/recompute")).andExpect(status().isOk());
        mvc.perform(delete(run)).andExpect(status().isNoContent());

        verify(payroll).markPaid(COMPANY, RUN, SLIP, Method.BANK_DEPOSIT, "TRX-9", STAFF);
        verify(payroll).markFailed(COMPANY, RUN, SLIP, "Wrong account", STAFF);
        verify(payroll).addLine(COMPANY, RUN, RIDER, Kind.BONUS, "Eid", new BigDecimal("25.00"),
                STAFF);
        verify(payroll).addCorrection(COMPANY, RUN, RIDER, Kind.DEDUCTION, new BigDecimal("4.50"),
                "Counted twice", STAFF);
        verify(payroll).recompute(COMPANY, RUN, STAFF, "token");
        verify(payroll).discard(COMPANY, RUN, STAFF);
        verify(payroll, never()).markPaid(any(), any(), any(), any(), any(), eq("somebody-else"));
        verify(payroll, never()).start(anyString(), any(), anyString(), anyString());
    }
}
