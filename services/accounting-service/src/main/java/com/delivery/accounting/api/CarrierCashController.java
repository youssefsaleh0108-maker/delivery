package com.delivery.accounting.api;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;
import java.time.format.DateTimeParseException;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.function.Function;

import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.delivery.accounting.domain.CashFloatEntry;
import com.delivery.accounting.service.CarrierCashService;
import com.delivery.accounting.service.CarrierCompanyClient;
import com.delivery.accounting.service.CashFloatService;
import com.delivery.accounting.service.Statement;

/**
 * A delivery company's own cash: what its riders hold for it, the hand-overs at its hub, and what
 * it owes the platform. CARRIER only.
 *
 * <p><strong>The company is never a parameter.</strong> Every route resolves it from the caller's
 * own token through Order Manager ({@link CarrierCompanyClient}), exactly as the carrier's statement
 * does, so there is no value on any of these requests a company could change to read or clear
 * another company's cash. A rider in the path is only ever looked up WITHIN that company: one who
 * has never carried cash for it is a 404, the same answer as a rider who does not exist, because
 * whether a stranger rides for a rival is not this company's to learn.
 *
 * <p><strong>The role check is written twice</strong>, as on the statements controller:
 * {@code @PreAuthorize} is the enforcement, and {@link Callers#requireRole} is the lock that still
 * holds without the proxy — and the one a standalone test can prove.
 *
 * <p>Money is on the wire as a string with two decimals, never a JSON number.
 */
@RestController
@RequestMapping("/api/accounting/carrier/cash")
@PreAuthorize("hasRole('CARRIER')")
public class CarrierCashController {

    /** More than any real hub note; a paragraph somebody pasted by mistake is not kept whole. */
    private static final int MAX_NOTE = 500;

    private final CarrierCashService cash;
    private final CashFloatService cashFloat;
    private final CarrierCompanyClient carrierCompanies;

    public CarrierCashController(CarrierCashService cash, CashFloatService cashFloat,
                                 CarrierCompanyClient carrierCompanies) {
        this.cash = cash;
        this.cashFloat = cashFloat;
        this.carrierCompanies = carrierCompanies;
    }

    /**
     * The reconciliation page: headline figures and one line per rider.
     *
     * @param day the day the collected, earned and handed-over figures cover; today by default.
     *            Balances are always as of now
     */
    @GetMapping
    public ResponseEntity<?> overview(@RequestParam(required = false) String day) {
        return asCarrier(company -> {
            LocalDate on;
            try {
                on = day == null || day.isBlank() ? cash.today() : LocalDate.parse(day.trim());
            } catch (DateTimeParseException e) {
                return badRequest("day must be an ISO date, like 2026-10-24");
            }
            return ResponseEntity.ok(overviewPayload(cash.overview(company, on)));
        });
    }

    /** One rider's settlement page. 404 for a rider who has never carried cash for this company. */
    @GetMapping("/riders/{riderRef}")
    public ResponseEntity<?> rider(@PathVariable String riderRef) {
        return asCarrier(company -> cash.rider(company, riderRef)
                .<ResponseEntity<?>>map(s -> ResponseEntity.ok(settlementPayload(s)))
                .orElseGet(CarrierCashController::unknownRider));
    }

    /**
     * Records that a rider handed the company everything they were holding for it.
     *
     * <p>The body's {@code expectedAmount} is the figure the hub manager counted against. If the
     * rider's balance is anything else — they collected more since the page loaded, or somebody
     * recorded this already — nothing is recorded and the answer is 409 with the current figure, so
     * the manager counts again rather than signing for notes nobody counted.
     *
     * <p>Safe to press twice: send the same {@code requestKey} and the second answer is the first
     * hand-over, marked {@code replayed}. Who recorded it is the caller's token subject, never a
     * name in the body.
     */
    @PostMapping("/riders/{riderRef}/handovers")
    public ResponseEntity<?> handOver(@PathVariable String riderRef,
                                      @RequestBody(required = false) HandoverRequest body) {
        return asCarrier(company -> {
            if (body == null || body.expectedAmount() == null) {
                return badRequest("Say how much was handed over, as expectedAmount");
            }
            CashFloatEntry.Method method = body.method() == null || body.method().isBlank()
                    ? CashFloatEntry.Method.CASH
                    : CashFloatEntry.Method.parse(body.method());
            if (method == null) {
                return badRequest("method must be one of CASH, BANK_DEPOSIT or WALLET");
            }
            String key = body.requestKey() == null || body.requestKey().isBlank()
                    ? null
                    : body.requestKey().trim();
            String keyProblem = Callers.requestKeyProblem(key);
            if (keyProblem != null) {
                return badRequest(keyProblem);
            }
            if (!cash.carriesFor(company, riderRef)) {
                return unknownRider();
            }

            Jwt caller = Callers.jwt();
            try {
                CashFloatService.Handover handover = cashFloat.handOver(company, riderRef,
                        body.expectedAmount(),
                        new CashFloatEntry.Recorded(caller.getSubject(), method,
                                noteOf(body.note()), key));
                return ResponseEntity.ok(handoverPayload(handover));

            } catch (CashFloatService.AmountChangedException e) {
                Map<String, Object> payload = new LinkedHashMap<>();
                payload.put("error", "This rider is holding " + money(e.current())
                        + " for your company now, not the amount you confirmed. Nothing was "
                        + "recorded; count it again.");
                payload.put("code", "AMOUNT_CHANGED");
                payload.put("current", money(e.current()));
                return ResponseEntity.status(409).body(payload);

            } catch (CashFloatService.RequestKeyReusedException e) {
                return ResponseEntity.status(409).body(Map.of(
                        "error", e.getMessage(), "code", "REQUEST_KEY_REUSED"));

            } catch (IllegalArgumentException e) {
                return badRequest(e.getMessage());

            } catch (DataIntegrityViolationException e) {
                // Two presses racing past every guard above: the unique indexes refused the second.
                // The first was recorded, and saying so is the honest answer.
                return ResponseEntity.status(409).body(Map.of(
                        "error", "That hand-over has already been recorded. Reload to see it.",
                        "code", "ALREADY_RECORDED"));
            }
        });
    }

    /** The company's hand-overs from every rider, newest first. */
    @GetMapping("/handovers")
    public ResponseEntity<?> history(@RequestParam(defaultValue = "50") int limit) {
        return asCarrier(company -> ResponseEntity.ok(Map.of(
                "currency", cash.currency(),
                "handovers", cash.history(company, limit).stream()
                        .map(CarrierCashController::handoverView)
                        .toList())));
    }

    /** What the company owes the platform now, what its riders still hold, and what it has paid. */
    @GetMapping("/owed")
    public ResponseEntity<?> owed() {
        return asCarrier(company -> {
            CarrierCashService.Owed owed = cash.owed(company);
            Map<String, Object> payload = new LinkedHashMap<>();
            payload.put("currency", owed.currency());
            payload.put("overdueAfterHours", owed.overdueAfterHours());
            payload.put("held", money(owed.held()));
            payload.put("orders", owed.orders());
            payload.put("oldest", iso(owed.oldest()));
            payload.put("overdue", owed.overdue());
            payload.put("withRiders", money(owed.withRiders()));
            payload.put("ridersHolding", owed.ridersHolding());
            payload.put("payments", owed.payments().stream().map(p -> {
                Map<String, Object> row = new LinkedHashMap<>();
                row.put("id", p.id().toString());
                row.put("amount", money(p.amount()));
                row.put("collections", p.collections());
                row.put("method", p.method() == null ? null : p.method().name());
                row.put("at", iso(p.at()));
                return row;
            }).toList());
            return ResponseEntity.ok(payload);
        });
    }

    /**
     * {@code {"expectedAmount":"485.00","method":"CASH","note":"...","requestKey":"..."}}.
     *
     * <p>The amount as a string is preferred and a number is accepted; either way it becomes a
     * {@link BigDecimal} and never passes through a double.
     */
    public record HandoverRequest(BigDecimal expectedAmount, String method, String note,
                                  String requestKey) {
    }

    // -------------------------------------------------------------------------------- plumbing

    /**
     * Runs {@code action} for the caller's company, or answers why it cannot.
     *
     * <p>403 with {@code NO_COMPANY} for carrier staff attached to no company — a fact they can act
     * on, and a different one from "you owe nothing". 503 when Order Manager could not be asked,
     * never an empty page: a company reading "nobody is holding cash" during an outage is exactly
     * the failure this must not produce.
     */
    private ResponseEntity<?> asCarrier(Function<String, ResponseEntity<?>> action) {
        ResponseEntity<?> refusal = Callers.requireRole("CARRIER");
        if (refusal != null) {
            return refusal;
        }
        String company;
        try {
            company = carrierCompanies.companyIdFor(Callers.jwt().getTokenValue());
        } catch (CarrierCompanyClient.NoCompanyException e) {
            return ResponseEntity.status(403).body(Map.of(
                    "error", "This account is not staff of a delivery company. Ask whoever runs "
                            + "the company to add you to it.",
                    "code", "NO_COMPANY"));
        } catch (IllegalStateException e) {
            return ResponseEntity.status(503).body(Map.of(
                    "error", "Your company's cash could not be read just now. Please try again."));
        }
        return action.apply(company);
    }

    private static ResponseEntity<?> unknownRider() {
        return ResponseEntity.status(404).body(Map.of(
                "error", "That rider has never worked for your company."));
    }

    private static ResponseEntity<?> badRequest(String message) {
        return ResponseEntity.badRequest().body(Map.of("error", message));
    }

    private static String noteOf(String note) {
        if (note == null || note.isBlank()) {
            return null;
        }
        String trimmed = note.trim();
        return trimmed.length() > MAX_NOTE ? trimmed.substring(0, MAX_NOTE) : trimmed;
    }

    private static Map<String, Object> overviewPayload(CarrierCashService.Overview o) {
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("day", o.day().toString());
        payload.put("currency", o.currency());
        payload.put("overdueAfterHours", o.overdueAfterHours());

        CarrierCashService.Totals t = o.totals();
        Map<String, Object> totals = new LinkedHashMap<>();
        totals.put("withRiders", money(t.withRiders()));
        totals.put("ridersHolding", t.ridersHolding());
        totals.put("handedOver", money(t.handedOver()));
        totals.put("handovers", t.handovers());
        totals.put("held", money(t.held()));
        totals.put("heldOrders", t.heldOrders());
        totals.put("overdue", money(t.overdue()));
        totals.put("overdueRiders", t.overdueRiders());
        payload.put("totals", totals);

        payload.put("riders", o.riders().stream().map(r -> {
            Map<String, Object> row = new LinkedHashMap<>();
            row.put("riderRef", r.riderRef());
            row.put("name", r.name());
            row.put("collected", money(r.collected()));
            row.put("collections", r.collections());
            row.put("earned", money(r.earned()));
            row.put("jobs", r.jobs());
            row.put("holding", money(r.holding()));
            row.put("orders", r.orders());
            row.put("oldest", iso(r.oldest()));
            row.put("lastHandoverAt", iso(r.lastHandoverAt()));
            row.put("standing", r.standing().name());
            row.put("overdueHours", r.overdueHours());
            return row;
        }).toList());
        return payload;
    }

    private static Map<String, Object> settlementPayload(CarrierCashService.RiderSettlement s) {
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("riderRef", s.riderRef());
        payload.put("name", s.name());
        payload.put("currency", s.currency());
        payload.put("overdueAfterHours", s.overdueAfterHours());
        payload.put("holding", money(s.holding()));
        payload.put("earnedOnHeld", money(s.earnedOnHeld()));
        payload.put("standing", s.standing().name());
        payload.put("overdueHours", s.overdueHours());
        payload.put("firstSeenAt", iso(s.firstSeenAt()));
        payload.put("held", s.held().stream().map(h -> {
            Map<String, Object> row = new LinkedHashMap<>();
            row.put("orderId", h.orderId() == null ? null : h.orderId().toString());
            row.put("amount", money(h.amount()));
            row.put("collectedAt", iso(h.collectedAt()));
            row.put("earned", h.earned() == null ? null : money(h.earned()));
            row.put("overdue", h.overdue());
            return row;
        }).toList());
        payload.put("handovers", s.handovers().stream()
                .map(CarrierCashController::handoverView)
                .toList());
        return payload;
    }

    private static Map<String, Object> handoverView(CarrierCashService.HandoverView h) {
        Map<String, Object> row = new LinkedHashMap<>();
        row.put("id", h.id().toString());
        row.put("riderRef", h.riderRef());
        row.put("riderName", h.riderName());
        row.put("amount", money(h.amount()));
        row.put("collections", h.collections());
        row.put("method", h.method() == null ? null : h.method().name());
        row.put("note", h.note());
        row.put("recordedByName", h.recordedByName());
        row.put("at", iso(h.at()));
        return row;
    }

    private static Map<String, Object> handoverPayload(CashFloatService.Handover h) {
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("handoverId", h.id().toString());
        payload.put("riderRef", h.riderRef());
        payload.put("amount", money(h.amount()));
        payload.put("collections", h.collections());
        payload.put("method", h.method() == null ? null : h.method().name());
        payload.put("note", h.note());
        payload.put("recordedAt", iso(h.at()));
        payload.put("replayed", h.replayed());
        return payload;
    }

    /** Money on the wire is a string with exactly two decimals. Never a JSON number. */
    private static String money(BigDecimal amount) {
        return Statement.money(amount).toPlainString();
    }

    private static String iso(Instant at) {
        return at == null ? null : at.toString();
    }
}
