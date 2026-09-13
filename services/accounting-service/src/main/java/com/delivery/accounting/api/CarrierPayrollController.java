package com.delivery.accounting.api;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.Instant;
import java.time.LocalDate;
import java.time.format.DateTimeParseException;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.function.BiFunction;
import java.util.function.Function;

import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.delivery.accounting.domain.CarrierPayAdjustment;
import com.delivery.accounting.domain.CarrierPayLine;
import com.delivery.accounting.domain.CarrierPayPolicy;
import com.delivery.accounting.domain.CarrierPayRun;
import com.delivery.accounting.domain.CarrierPayslip;
import com.delivery.accounting.domain.CashFloatEntry;
import com.delivery.accounting.service.CarrierCompanyClient;
import com.delivery.accounting.service.CarrierPayrollService;
import com.delivery.accounting.service.CashFloatService;
import com.delivery.accounting.service.Statement;

/**
 * A delivery company's payroll for the riders it employs: its pay rules, its pay runs, and the
 * payments it records. CARRIER only.
 *
 * <p><strong>The company is never a parameter.</strong> Every route resolves it from the caller's own
 * token through Order Manager ({@link CarrierCompanyClient}), as the company's cash routes do, and
 * every run, payslip and line is looked up within that company. A run of another company's is the
 * same 404 as a run that does not exist, and a rider can only be named on a run they already have a
 * payslip on — so no value on any request reaches another company's riders or pay.
 *
 * <p><strong>The role check is written twice</strong>, as on the cash routes: {@code @PreAuthorize} is
 * the enforcement, {@link Callers#requireRole} the lock that still holds without the proxy and the
 * one a standalone test proves. Who did something is always the token's subject, never a body field;
 * and a person's account id never leaves the server, only their name.
 *
 * <p>Money is on the wire as a string with two decimals. A refusal is
 * {@code {"error": "...", "code": "..."}}: the code is what a page words, the error what a log reads.
 */
@RestController
@RequestMapping("/api/accounting/carrier/payroll")
@PreAuthorize("hasRole('CARRIER')")
public class CarrierPayrollController {

    private final CarrierPayrollService payroll;
    private final CarrierCompanyClient carrierCompanies;

    public CarrierPayrollController(CarrierPayrollService payroll,
                                    CarrierCompanyClient carrierCompanies) {
        this.payroll = payroll;
        this.carrierCompanies = carrierCompanies;
    }

    // --------------------------------------------------------------------------------- rules

    /** The rules in force, the ones scheduled, their history, and the days new ones could start. */
    @GetMapping("/policy")
    public ResponseEntity<?> policy() {
        return asCarrier(caller -> ResponseEntity.ok(policyPage(payroll.policy(caller.company()))));
    }

    /**
     * Saves a new version of the rules. Anything left out takes the default the owner has not yet
     * overruled: twice a month, office-typed hours paid, overtime at 1.00, no lateness or absence
     * deductions. The pay per delivery has no default — the company must say it, 0 included.
     */
    @PostMapping("/policy")
    public ResponseEntity<?> setPolicy(@RequestBody(required = false) PolicyRequest body) {
        return asCarrier(caller -> {
            if (body == null || body.perDeliveryRate() == null) {
                return badRequest("BAD_POLICY",
                        "Say the pay per delivery, as perDeliveryRate (0 for none).");
            }
            Optional<LocalDate> from = date(body.effectiveFrom());
            if (from.isEmpty()) {
                return badRequest("BAD_DATE", "effectiveFrom must be an ISO date, like 2026-10-16.");
            }
            CarrierPayPolicy.PayCycle cycle = blank(body.payCycle())
                    ? CarrierPayPolicy.DEFAULT_CYCLE
                    : CarrierPayPolicy.PayCycle.parse(body.payCycle());
            if (cycle == null) {
                return badRequest("BAD_POLICY", "payCycle must be SEMI_MONTHLY or MONTHLY.");
            }
            CarrierPayPolicy.Terms terms = new CarrierPayPolicy.Terms(cycle,
                    body.perDeliveryRate(),
                    body.hourlyRate(),
                    body.payManualHours() == null
                            ? CarrierPayPolicy.DEFAULT_PAY_MANUAL_HOURS
                            : body.payManualHours(),
                    body.overtimeMultiplier() == null
                            ? CarrierPayPolicy.DEFAULT_OVERTIME_MULTIPLIER
                            : body.overtimeMultiplier(),
                    body.lateDeduction() == null
                            ? CarrierPayPolicy.DEFAULT_LATE_DEDUCTION
                            : body.lateDeduction(),
                    body.absenceDeduction() == null
                            ? CarrierPayPolicy.DEFAULT_ABSENCE_DEDUCTION
                            : body.absenceDeduction());
            return ResponseEntity.status(201).body(policyPayload(
                    payroll.setPolicy(caller.company(), from.get(), terms, caller.subject())));
        });
    }

    // ------------------------------------------------------------------------------- periods

    /** The current pay period and the ones before it, each with its run if it has one. */
    @GetMapping("/periods")
    public ResponseEntity<?> periods() {
        return asCarrier(caller -> ResponseEntity.ok(periodsPayload(payroll.periods(caller.company()))));
    }

    // ---------------------------------------------------------------------------------- runs

    /** Starts and computes the draft for the period beginning on {@code periodFrom}. */
    @PostMapping("/runs")
    public ResponseEntity<?> start(@RequestBody(required = false) StartRequest body) {
        return asCarrier(caller -> {
            Optional<LocalDate> from = date(body == null ? null : body.periodFrom());
            if (from.isEmpty()) {
                return badRequest("BAD_DATE",
                        "periodFrom must be the period's first day, as an ISO date.");
            }
            return ResponseEntity.status(201).body(runPayload(payroll.start(caller.company(),
                    from.get(), caller.subject(), caller.token())));
        });
    }

    @GetMapping("/runs/{runId}")
    public ResponseEntity<?> run(@PathVariable String runId) {
        return asCarrier(caller -> uuid(runId)
                .flatMap(id -> payroll.run(caller.company(), id))
                .<ResponseEntity<?>>map(view -> ResponseEntity.ok(runPayload(view)))
                .orElseGet(CarrierPayrollController::runNotFound));
    }

    /** Computes a draft again, reading hours afresh. */
    @PostMapping("/runs/{runId}/recompute")
    public ResponseEntity<?> recompute(@PathVariable String runId) {
        return asCarrierRun(runId, (caller, id) -> ResponseEntity.ok(runPayload(
                payroll.recompute(caller.company(), id, caller.subject(), caller.token()))));
    }

    /** Throws a draft away. An approved run is never deleted. */
    @DeleteMapping("/runs/{runId}")
    public ResponseEntity<?> discard(@PathVariable String runId) {
        return asCarrierRun(runId, (caller, id) -> {
            payroll.discard(caller.company(), id, caller.subject());
            return ResponseEntity.noContent().build();
        });
    }

    /** {@code {"riderRef","kind":"BONUS|DEDUCTION","label","amount"}} on a draft's payslip. */
    @PostMapping("/runs/{runId}/lines")
    public ResponseEntity<?> addLine(@PathVariable String runId,
                                     @RequestBody(required = false) LineRequest body) {
        return asCarrierRun(runId, (caller, id) -> {
            if (body == null || blank(body.riderRef())) {
                return badRequest("BAD_RIDER", "Say which rider, as riderRef.");
            }
            CarrierPayLine.Kind kind = CarrierPayLine.Kind.parseNamed(body.kind());
            if (kind == null) {
                return badRequest("BAD_KIND", "kind must be BONUS or DEDUCTION.");
            }
            return ResponseEntity.ok(runPayload(payroll.addLine(caller.company(), id,
                    body.riderRef().trim(), kind, body.label(), body.amount(), caller.subject())));
        });
    }

    @DeleteMapping("/runs/{runId}/lines/{lineId}")
    public ResponseEntity<?> removeLine(@PathVariable String runId, @PathVariable String lineId) {
        return asCarrierRun(runId, (caller, id) -> uuid(lineId)
                .<ResponseEntity<?>>map(line -> ResponseEntity.ok(runPayload(
                        payroll.removeLine(caller.company(), id, line, caller.subject()))))
                .orElseGet(() -> refused(404, "LINE_NOT_FOUND", "That line is not on this pay run.")));
    }

    /**
     * {@code {"revision": 3, "acknowledgeMissing": false}}.
     *
     * <p>200 with the approved run. 409 {@code FIGURES_CHANGED} with the run as it now is, when what
     * the approver looked at is no longer true; 409 {@code NEEDS_ACKNOWLEDGEMENT} when hours are
     * missing or deliveries were counted from the ledger, and the body did not say to go ahead
     * anyway; 409 {@code RECOMPUTE_NEEDED} when the figures were read before the period ended; 409
     * {@code CASH_CHANGED} when a rider's cash moved at the last moment. Nothing is approved in any
     * of them.
     */
    @PostMapping("/runs/{runId}/approve")
    public ResponseEntity<?> approve(@PathVariable String runId,
                                     @RequestBody(required = false) ApproveRequest body) {
        return asCarrierRun(runId, (caller, id) -> {
            if (body == null || body.revision() == null) {
                return badRequest("BAD_REVISION",
                        "Say which revision of the figures you are approving, as revision.");
            }
            CarrierPayrollService.Approval approval = payroll.approve(caller.company(), id,
                    body.revision(), Boolean.TRUE.equals(body.acknowledgeMissing()),
                    caller.subject());
            return switch (approval.outcome()) {
                case APPROVED, ALREADY_APPROVED -> ResponseEntity.ok(runPayload(approval.run()));
                case FIGURES_CHANGED -> conflictWithRun("FIGURES_CHANGED",
                        "The figures changed since you looked. Check them and approve again.",
                        approval.run());
                case NEEDS_ACKNOWLEDGEMENT -> conflictWithRun("NEEDS_ACKNOWLEDGEMENT",
                        "Hours or deliveries are missing from this pay run. Approve saying so to "
                                + "go ahead without them.", approval.run());
            };
        });
    }

    /** {@code {"method":"CASH|BANK_DEPOSIT|WALLET","reference":"..."}} — recorded, never moved. */
    @PostMapping("/runs/{runId}/payslips/{payslipId}/paid")
    public ResponseEntity<?> paid(@PathVariable String runId, @PathVariable String payslipId,
                                  @RequestBody(required = false) PaidRequest body) {
        return asCarrierRun(runId, (caller, id) -> {
            CashFloatEntry.Method method = CashFloatEntry.Method.parse(body == null ? null : body.method());
            if (method == null) {
                return badRequest("BAD_METHOD", "method must be CASH, BANK_DEPOSIT or WALLET.");
            }
            return uuid(payslipId)
                    .<ResponseEntity<?>>map(slip -> ResponseEntity.ok(runPayload(payroll.markPaid(
                            caller.company(), id, slip, method, body.reference(),
                            caller.subject()))))
                    .orElseGet(CarrierPayrollController::payslipNotFound);
        });
    }

    /** {@code {"reason":"..."}}: a payment that did not go through. The pay stays owed. */
    @PostMapping("/runs/{runId}/payslips/{payslipId}/failed")
    public ResponseEntity<?> failed(@PathVariable String runId, @PathVariable String payslipId,
                                    @RequestBody(required = false) FailedRequest body) {
        return asCarrierRun(runId, (caller, id) -> uuid(payslipId)
                .<ResponseEntity<?>>map(slip -> ResponseEntity.ok(runPayload(payroll.markFailed(
                        caller.company(), id, slip, body == null ? null : body.reason(),
                        caller.subject()))))
                .orElseGet(CarrierPayrollController::payslipNotFound));
    }

    /**
     * {@code {"expectedTotal":"1234.50","method":"CASH","reference":"..."}}: every payslip waiting,
     * paid at once. 409 {@code TOTAL_CHANGED} with {@code current} when what is waiting is not the
     * total confirmed.
     */
    @PostMapping("/runs/{runId}/pay")
    public ResponseEntity<?> payAll(@PathVariable String runId,
                                    @RequestBody(required = false) PayAllRequest body) {
        return asCarrierRun(runId, (caller, id) -> {
            CashFloatEntry.Method method = CashFloatEntry.Method.parse(body == null ? null : body.method());
            if (method == null) {
                return badRequest("BAD_METHOD", "method must be CASH, BANK_DEPOSIT or WALLET.");
            }
            return ResponseEntity.ok(runPayload(payroll.payAll(caller.company(), id,
                    body.expectedTotal(), method, body.reference(), caller.subject())));
        });
    }

    /** {@code {"riderRef","kind":"BONUS|DEDUCTION","amount","reason"}} against an approved run. */
    @PostMapping("/runs/{runId}/corrections")
    public ResponseEntity<?> addCorrection(@PathVariable String runId,
                                           @RequestBody(required = false) CorrectionRequest body) {
        return asCarrierRun(runId, (caller, id) -> {
            if (body == null || blank(body.riderRef())) {
                return badRequest("BAD_RIDER", "Say which rider, as riderRef.");
            }
            CarrierPayLine.Kind kind = CarrierPayLine.Kind.parseNamed(body.kind());
            if (kind == null) {
                return badRequest("BAD_KIND", "kind must be BONUS or DEDUCTION.");
            }
            return ResponseEntity.ok(runPayload(payroll.addCorrection(caller.company(), id,
                    body.riderRef().trim(), kind, body.amount(), body.reason(),
                    caller.subject())));
        });
    }

    // ------------------------------------------------------------------------------- bodies

    public record PolicyRequest(String effectiveFrom, String payCycle, BigDecimal perDeliveryRate,
                                BigDecimal hourlyRate, Boolean payManualHours,
                                BigDecimal overtimeMultiplier, BigDecimal lateDeduction,
                                BigDecimal absenceDeduction) {
    }

    public record StartRequest(String periodFrom) {
    }

    public record LineRequest(String riderRef, String kind, String label, BigDecimal amount) {
    }

    public record ApproveRequest(Integer revision, Boolean acknowledgeMissing) {
    }

    public record PaidRequest(String method, String reference) {
    }

    public record FailedRequest(String reason) {
    }

    public record PayAllRequest(BigDecimal expectedTotal, String method, String reference) {
    }

    public record CorrectionRequest(String riderRef, String kind, BigDecimal amount,
                                    String reason) {
    }

    // ----------------------------------------------------------------------------- plumbing

    /** The caller, as far as every route here needs to know them. */
    private record Caller(String company, String subject, String token) {
    }

    /**
     * Runs {@code action} for the caller's company, or answers why it cannot: 401 unsigned, 403 for
     * another role or {@code NO_COMPANY}, 503 when Order Manager could not be asked — never an empty
     * payroll, which a company would read as "nobody is owed anything".
     */
    private ResponseEntity<?> asCarrier(Function<Caller, ResponseEntity<?>> action) {
        ResponseEntity<?> refusal = Callers.requireRole("CARRIER");
        if (refusal != null) {
            return refusal;
        }
        Jwt jwt = Callers.jwt();
        String company;
        try {
            company = carrierCompanies.companyIdFor(jwt.getTokenValue());
        } catch (CarrierCompanyClient.NoCompanyException e) {
            return refused(403, "NO_COMPANY", "This account is not staff of a delivery company. "
                    + "Ask whoever runs the company to add you to it.");
        } catch (IllegalStateException e) {
            return refused(503, "UNAVAILABLE",
                    "Your company's payroll could not be read just now. Please try again.");
        }

        try {
            return action.apply(new Caller(company, jwt.getSubject(), jwt.getTokenValue()));
        } catch (CarrierPayrollService.PayrollRefusal e) {
            Map<String, Object> payload = new LinkedHashMap<>();
            payload.put("error", e.getMessage());
            payload.put("code", e.code());
            if (e.detail() instanceof UUID run) {
                payload.put("runId", run.toString());
            } else if (e.detail() instanceof BigDecimal current) {
                payload.put("current", money(current));
            }
            return ResponseEntity.status(e.status()).body(payload);
        } catch (CashFloatService.AmountChangedException e) {
            return refused(409, "CASH_CHANGED", "A rider's cash changed since these figures were "
                    + "computed. Nothing was approved; recompute and approve again.");
        } catch (CashFloatService.RequestKeyReusedException | DataIntegrityViolationException e) {
            return refused(409, "CONFLICT", "This pay run was changed at the same moment. "
                    + "Reload it and try again.");
        }
    }

    private ResponseEntity<?> asCarrierRun(String runId,
                                           BiFunction<Caller, UUID, ResponseEntity<?>> action) {
        return asCarrier(caller -> uuid(runId)
                .<ResponseEntity<?>>map(id -> action.apply(caller, id))
                .orElseGet(CarrierPayrollController::runNotFound));
    }

    private static ResponseEntity<?> runNotFound() {
        return refused(404, "RUN_NOT_FOUND", "That pay run is not one of your company's.");
    }

    private static ResponseEntity<?> payslipNotFound() {
        return refused(404, "PAYSLIP_NOT_FOUND", "That payslip is not on this pay run.");
    }

    private static ResponseEntity<?> badRequest(String code, String message) {
        return refused(400, code, message);
    }

    private static ResponseEntity<?> refused(int status, String code, String message) {
        return ResponseEntity.status(status).body(Map.of("error", message, "code", code));
    }

    private static ResponseEntity<?> conflictWithRun(String code, String message,
                                                     CarrierPayrollService.RunView run) {
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("error", message);
        payload.put("code", code);
        payload.put("run", runPayload(run));
        return ResponseEntity.status(409).body(payload);
    }

    /** An id that is not a UUID names no run of anybody's: the same 404, and nothing is asked. */
    private static Optional<UUID> uuid(String value) {
        try {
            return value == null ? Optional.empty() : Optional.of(UUID.fromString(value.trim()));
        } catch (IllegalArgumentException e) {
            return Optional.empty();
        }
    }

    private static Optional<LocalDate> date(String value) {
        if (blank(value)) {
            return Optional.empty();
        }
        try {
            return Optional.of(LocalDate.parse(value.trim()));
        } catch (DateTimeParseException e) {
            return Optional.empty();
        }
    }

    private static boolean blank(String value) {
        return value == null || value.isBlank();
    }

    // ------------------------------------------------------------------------------ payloads

    private static Map<String, Object> policyPage(CarrierPayrollService.PolicyPage page) {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("zone", page.zone());
        out.put("currency", page.currency());
        out.put("today", page.today().toString());
        out.put("current", page.current() == null ? null : policyPayload(page.current()));
        out.put("scheduled", page.scheduled().stream()
                .map(CarrierPayrollController::policyPayload)
                .toList());
        out.put("history", page.history().stream()
                .map(CarrierPayrollController::policyPayload)
                .toList());

        Map<String, Object> defaults = new LinkedHashMap<>();
        defaults.put("payCycle", CarrierPayPolicy.DEFAULT_CYCLE.name());
        // No default: the company says what a delivery is worth to it.
        defaults.put("perDeliveryRate", null);
        defaults.put("hourlyRate", null);
        defaults.put("payManualHours", CarrierPayPolicy.DEFAULT_PAY_MANUAL_HOURS);
        defaults.put("overtimeMultiplier", money(CarrierPayPolicy.DEFAULT_OVERTIME_MULTIPLIER));
        defaults.put("lateDeduction", money(CarrierPayPolicy.DEFAULT_LATE_DEDUCTION));
        defaults.put("absenceDeduction", money(CarrierPayPolicy.DEFAULT_ABSENCE_DEDUCTION));
        out.put("defaults", defaults);

        Map<String, Object> starts = new LinkedHashMap<>();
        page.startOptions().forEach((cycle, days) ->
                starts.put(cycle.name(), days.stream().map(LocalDate::toString).toList()));
        out.put("startOptions", starts);
        return out;
    }

    private static Map<String, Object> policyPayload(CarrierPayrollService.PolicyView view) {
        CarrierPayPolicy policy = view.policy();
        CarrierPayPolicy.Terms terms = policy.terms();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("id", policy.getId().toString());
        out.put("effectiveFrom", policy.getEffectiveFrom().toString());
        out.put("payCycle", terms.cycle().name());
        out.put("currency", policy.getCurrency());
        out.put("perDeliveryRate", money(terms.perDeliveryRate()));
        out.put("hourlyRate", terms.hourlyRate() == null ? null : money(terms.hourlyRate()));
        out.put("payManualHours", terms.payManualHours());
        out.put("overtimeMultiplier", money(terms.overtimeMultiplier()));
        out.put("lateDeduction", money(terms.lateDeduction()));
        out.put("absenceDeduction", money(terms.absenceDeduction()));
        out.put("needsAttendance", terms.needsAttendance());
        out.put("createdByName", view.createdByName());
        out.put("createdAt", iso(policy.getCreatedAt()));
        return out;
    }

    private static Map<String, Object> periodsPayload(CarrierPayrollService.PeriodsPage page) {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("zone", page.zone());
        out.put("currency", page.currency());
        out.put("today", page.today().toString());
        out.put("hasPolicy", page.hasPolicy());
        out.put("periods", page.periods().stream().map(row -> {
            CarrierPayRun run = row.run();
            Map<String, Object> period = new LinkedHashMap<>();
            period.put("from", row.from().toString());
            period.put("to", row.to().toString());
            period.put("over", row.over());
            period.put("aligned", row.aligned());
            period.put("runId", run == null ? null : run.getId().toString());
            period.put("status", run == null ? null : run.getStatus().name());
            period.put("revision", run == null ? null : run.getRevision());
            period.put("riders", row.riders());
            period.put("payable", row.payable() == null ? null : money(row.payable()));
            return period;
        }).toList());
        return out;
    }

    private static Map<String, Object> runPayload(CarrierPayrollService.RunView view) {
        CarrierPayRun run = view.run();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("id", run.getId().toString());
        out.put("from", run.getPeriodFrom().toString());
        out.put("to", run.getPeriodTo().toString());
        out.put("status", run.getStatus().name());
        out.put("revision", run.getRevision());
        out.put("currency", run.getCurrency());
        out.put("computedAt", iso(run.getComputedAt()));
        out.put("approvedAt", iso(run.getApprovedAt()));
        out.put("approvedByName", view.approvedByName());
        out.put("paidAt", iso(run.getPaidAt()));
        out.put("attendance", run.getAttendance().name());
        out.put("attendanceReason", run.getAttendanceNote());
        out.put("attendanceAt", iso(run.getAttendanceAt()));
        out.put("deliveries", run.getDeliveries().name());
        out.put("deliveriesReason", run.getDeliveriesNote());
        out.put("deliveriesAt", iso(run.getDeliveriesAt()));
        out.put("readBeforePeriodEnd", view.readBeforePeriodEnd());
        out.put("periodOver", view.periodOver());
        out.put("jobsSinceComputed", view.jobsSinceComputed());
        out.put("needsAcknowledgement", view.needsAcknowledgement());
        out.put("periodChanged", view.periodChanged());
        out.put("policy", policyPayload(view.policy()));

        CarrierPayrollService.Totals t = view.totals();
        Map<String, Object> totals = new LinkedHashMap<>();
        totals.put("riders", t.riders());
        totals.put("payable", money(t.payable()));
        totals.put("average", t.average() == null ? null : money(t.average()));
        totals.put("gross", money(t.gross()));
        totals.put("bonuses", money(t.bonuses()));
        totals.put("deductions", money(t.deductions()));
        totals.put("owedByRiders", money(t.owedByRiders()));
        totals.put("tips", money(t.tips()));
        totals.put("cashNetted", money(t.cashNetted()));
        totals.put("paid", money(t.paid()));
        totals.put("outstanding", money(t.outstanding()));
        totals.put("due", t.due());
        totals.put("failed", t.failed());
        totals.put("paidCount", t.paidCount());
        out.put("totals", totals);

        out.put("payslips", view.payslips().stream()
                .map(CarrierPayrollController::payslipPayload)
                .toList());
        out.put("corrections", view.corrections().stream().map(c -> {
            CarrierPayAdjustment a = c.adjustment();
            Map<String, Object> row = new LinkedHashMap<>();
            row.put("id", a.getId().toString());
            row.put("riderRef", a.getRiderRef());
            row.put("riderName", c.riderName());
            row.put("kind", a.getKind().name());
            row.put("amount", money(a.getAmount()));
            row.put("reason", a.getReason());
            row.put("createdByName", c.createdByName());
            row.put("createdAt", iso(a.getCreatedAt()));
            row.put("appliedRunId", a.getAppliedRunId() == null ? null : a.getAppliedRunId().toString());
            return row;
        }).toList());
        out.put("history", view.history().stream().map(e -> {
            Map<String, Object> row = new LinkedHashMap<>();
            row.put("action", e.event().getAction().name());
            row.put("riderRef", e.event().getRiderRef());
            row.put("riderName", e.riderName());
            row.put("actorName", e.actorName());
            row.put("detail", e.event().getDetail());
            row.put("at", iso(e.event().getOccurredAt()));
            return row;
        }).toList());
        return out;
    }

    private static Map<String, Object> payslipPayload(CarrierPayrollService.PayslipView view) {
        CarrierPayslip slip = view.slip();
        CarrierPayslip.Figures f = slip.figures();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("id", slip.getId().toString());
        out.put("riderRef", slip.getRiderRef());
        out.put("name", view.name());
        out.put("status", slip.getStatus().name());
        out.put("deliveries", f.deliveries());
        out.put("workedSeconds", f.workedSeconds());
        out.put("manualSeconds", f.manualSeconds());
        out.put("overtimeSeconds", f.overtimeSeconds());
        out.put("lates", f.lates());
        out.put("absences", f.absences());
        out.put("hoursUnknown", view.hoursUnknown());
        out.put("basePay", money(f.basePay()));
        out.put("deliveryPay", money(f.deliveryPay()));
        out.put("bonuses", money(f.bonuses()));
        out.put("deductions", money(f.deductions()));
        out.put("gross", money(f.gross()));
        out.put("net", money(f.net()));
        out.put("tips", money(f.tips()));
        out.put("cashHeld", money(f.cashHeld()));
        out.put("cashNetted", money(f.cashNetted()));
        out.put("paidMethod", slip.getPaidMethod() == null ? null : slip.getPaidMethod().name());
        out.put("paidReference", slip.getPaidReference());
        out.put("paidAt", iso(slip.getPaidAt()));
        out.put("paidByName", view.paidByName());
        out.put("failureReason", slip.getFailureReason());
        out.put("failedAt", iso(slip.getFailedAt()));
        out.put("failedByName", view.failedByName());
        out.put("lines", view.lines().stream().map(l -> {
            CarrierPayLine line = l.line();
            Map<String, Object> row = new LinkedHashMap<>();
            row.put("id", line.getId().toString());
            row.put("kind", line.getKind().name());
            row.put("source", line.getSource().name());
            row.put("label", line.getLabel());
            row.put("quantity", quantity(line));
            row.put("rate", rate(line.getRate()));
            row.put("amount", money(line.getAmount()));
            row.put("createdByName", l.createdByName());
            return row;
        }).toList());
        return out;
    }

    /** Hours to two places for reading; counts as whole numbers. Display only. */
    private static String quantity(CarrierPayLine line) {
        BigDecimal quantity = line.getQuantity();
        if (quantity == null) {
            return null;
        }
        return switch (line.getKind()) {
            case HOURS, OVERTIME, MANUAL_HOURS ->
                    quantity.setScale(2, RoundingMode.HALF_UP).toPlainString();
            default -> quantity.stripTrailingZeros().toPlainString();
        };
    }

    /** A rate with at least two places, and all it really has: 4.1625 an overtime hour stays so. */
    private static String rate(BigDecimal rate) {
        if (rate == null) {
            return null;
        }
        BigDecimal stripped = rate.stripTrailingZeros();
        return (stripped.scale() < 2 ? rate.setScale(2, RoundingMode.HALF_UP) : stripped)
                .toPlainString();
    }

    /** Money on the wire is a string with exactly two decimals. Never a JSON number. */
    private static String money(BigDecimal amount) {
        return Statement.money(amount).toPlainString();
    }

    private static String iso(Instant at) {
        return at == null ? null : at.toString();
    }
}
