package com.delivery.accounting.api;

import java.math.BigDecimal;
import java.time.ZoneId;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.delivery.accounting.domain.RiderCashOut;
import com.delivery.accounting.domain.RiderLedgerEntry;
import com.delivery.accounting.service.RiderEarningsService;

/**
 * The rider's Earnings screen, and the operator's side of a cash-out.
 *
 * <p><strong>Whose earnings you see is decided by your token, never by a path parameter.</strong>
 * Every self-service endpoint below reads {@code jwt.getSubject()} and there is no rider id to
 * tamper with, so a rider asking for a balance can only ever be asking for their own. The same rule
 * the points API follows, and for the stronger reason here: this is money somebody can request.
 *
 * <p>The Backoffice endpoints are role-gated separately and are the only ones that name a rider,
 * because paying somebody is by definition an operator acting on another person's behalf.
 */
@RestController
@RequestMapping("/api/rider")
public class RiderEarningsController {

    /** Enough for a fortnight's chart. A rider asking for a year of days is asking for a report. */
    private static final int MAX_SERIES_DAYS = 90;
    private static final int MAX_JOBS = 100;

    private final RiderEarningsService earnings;

    public RiderEarningsController(RiderEarningsService earnings) {
        this.earnings = earnings;
    }

    /**
     * Everything the Earnings screen needs in one call: today, this week, the balance, and whether
     * a cash-out is already on its way.
     *
     * <p>One endpoint rather than four, because the screen renders them together and four calls
     * would let it paint a balance from one moment beside a total from another — which reads as the
     * arithmetic not adding up.
     */
    @GetMapping("/earnings")
    @PreAuthorize("hasRole('DELIVERY')")
    public ResponseEntity<?> myEarnings(@AuthenticationPrincipal Jwt jwt,
                                        @RequestParam(defaultValue = "7") int days,
                                        @RequestParam(required = false) String zone) {
        ZoneId at;
        try {
            at = zoneOf(zone);
        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest().body(Map.of("error", e.getMessage()));
        }

        String rider = jwt.getSubject();
        RiderEarningsService.Statement statement =
                earnings.statement(rider, at, Math.min(Math.max(days, 1), MAX_SERIES_DAYS));

        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("currency", earnings.currency());
        payload.put("zone", at.getId());
        payload.put("today", totalPayload(statement.today()));
        payload.put("thisWeek", totalPayload(statement.thisWeek()));
        payload.put("series", seriesPayload(statement.series()));
        payload.put("balance", balancePayload(rider));
        return ResponseEntity.ok(payload);
    }

    /** Just the day-by-day series, for a screen that only draws the chart. */
    @GetMapping("/earnings/series")
    @PreAuthorize("hasRole('DELIVERY')")
    public ResponseEntity<?> mySeries(@AuthenticationPrincipal Jwt jwt,
                                      @RequestParam(defaultValue = "7") int days,
                                      @RequestParam(required = false) String zone) {
        ZoneId at;
        try {
            at = zoneOf(zone);
        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest().body(Map.of("error", e.getMessage()));
        }
        return ResponseEntity.ok(seriesPayload(earnings
                .statement(jwt.getSubject(), at, Math.min(Math.max(days, 1), MAX_SERIES_DAYS))
                .series()));
    }

    /** The recent jobs and what each one paid. */
    @GetMapping("/earnings/jobs")
    @PreAuthorize("hasRole('DELIVERY')")
    public List<Map<String, Object>> myJobs(@AuthenticationPrincipal Jwt jwt,
                                            @RequestParam(defaultValue = "20") int limit) {
        return earnings.recentJobs(jwt.getSubject(), Math.min(Math.max(limit, 1), MAX_JOBS))
                .stream()
                .map(RiderEarningsController::jobPayload)
                .toList();
    }

    /** What the platform owes, what can be taken out, and any request already in flight. */
    @GetMapping("/balance")
    @PreAuthorize("hasRole('DELIVERY')")
    public Map<String, Object> myBalance(@AuthenticationPrincipal Jwt jwt) {
        return balancePayload(jwt.getSubject());
    }

    // ---------------------------------------------------------------------------- cash out

    /**
     * Asking for the balance in money. The money is held the moment this succeeds.
     *
     * <p>A 409 rather than a 400 when a request is already open: the caller did nothing wrong, the
     * resource is in a state that refuses it, and an app that treats "already on its way" as a
     * validation error shows the rider a form error for something that is really good news.
     */
    @PostMapping("/cash-outs")
    @PreAuthorize("hasRole('DELIVERY')")
    public ResponseEntity<?> requestCashOut(@AuthenticationPrincipal Jwt jwt,
                                            @RequestBody CashOutRequest body) {
        try {
            RiderCashOut request = earnings.requestCashOut(
                    jwt.getSubject(), body.amount(), body.payoutNote());
            return ResponseEntity.ok(cashOutPayload(request));
        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest().body(Map.of("error", e.getMessage()));
        } catch (IllegalStateException e) {
            return ResponseEntity.status(409).body(Map.of("error", e.getMessage()));
        }
    }

    @GetMapping("/cash-outs")
    @PreAuthorize("hasRole('DELIVERY')")
    public List<Map<String, Object>> myCashOuts(@AuthenticationPrincipal Jwt jwt,
                                                @RequestParam(defaultValue = "20") int limit) {
        return earnings.cashOutsFor(jwt.getSubject(), Math.min(Math.max(limit, 1), MAX_JOBS))
                .stream()
                .map(RiderEarningsController::cashOutPayload)
                .toList();
    }

    // ---------------------------------------------------------------------------- tips

    /**
     * A customer tipping the rider who delivered their order.
     *
     * <p>CUSTOMER-gated, and gated again inside the service on the customer who actually paid for
     * that order — the role alone would let anybody tip anybody's job. The rider is never named by
     * the caller: it is read from the job earning written when the order was delivered, so this
     * cannot be used to move money towards a rider of the caller's choosing.
     */
    @PostMapping("/tips")
    @PreAuthorize("hasRole('CUSTOMER')")
    public ResponseEntity<?> tip(@AuthenticationPrincipal Jwt jwt, @RequestBody TipRequest body) {
        if (body == null || body.orderId() == null) {
            return ResponseEntity.badRequest().body(Map.of("error", "Which order?"));
        }
        try {
            RiderLedgerEntry entry = earnings.tip(body.orderId(), jwt.getSubject(), body.amount(),
                    body.method() == null ? RiderEarningsService.TipMethod.CASH : body.method());
            // The rider is NOT named in the response. The customer knows who they tipped; echoing
            // the subject back would hand every customer a way to read a rider's identifier.
            return ResponseEntity.ok(Map.of(
                    "orderId", entry.getOrderId(),
                    "amount", entry.getAmount(),
                    "currency", entry.getCurrency(),
                    "tippedAt", entry.getEarnedAt()));
        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest().body(Map.of("error", e.getMessage()));
        } catch (IllegalStateException e) {
            return ResponseEntity.status(409).body(Map.of("error", e.getMessage()));
        }
    }

    // ---------------------------------------------------------------------------- Backoffice

    /** Everything waiting on a payout, oldest first — the operator has been keeping somebody waiting. */
    @GetMapping("/cash-outs/queue")
    @PreAuthorize("hasRole('BACKOFFICE')")
    public List<Map<String, Object>> queue(@RequestParam(defaultValue = "50") int limit) {
        return earnings.cashOutQueue(Math.min(Math.max(limit, 1), MAX_JOBS)).stream()
                .map(RiderEarningsController::cashOutPayload)
                .toList();
    }

    /**
     * Records that the money was handed over.
     *
     * <p>BACKOFFICE only, and for the same reason marking a cash float remitted is: this is somebody
     * at the platform confirming money physically moved, and the rider is the one party with an
     * incentive to confirm it early.
     */
    @PostMapping("/cash-outs/{id}/pay")
    @PreAuthorize("hasRole('BACKOFFICE')")
    public ResponseEntity<?> pay(@PathVariable UUID id, @AuthenticationPrincipal Jwt jwt,
                                 @RequestBody(required = false) Decision body) {
        return decide(() -> earnings.payCashOut(id, jwt.getSubject(), noteOf(body)));
    }

    @PostMapping("/cash-outs/{id}/reject")
    @PreAuthorize("hasRole('BACKOFFICE')")
    public ResponseEntity<?> reject(@PathVariable UUID id, @AuthenticationPrincipal Jwt jwt,
                                    @RequestBody(required = false) Decision body) {
        return decide(() -> earnings.rejectCashOut(id, jwt.getSubject(), noteOf(body)));
    }

    // ---------------------------------------------------------------------------- plumbing

    public record CashOutRequest(BigDecimal amount, String payoutNote) {
    }

    public record TipRequest(UUID orderId, BigDecimal amount,
                             RiderEarningsService.TipMethod method) {
    }

    public record Decision(String note) {
    }

    private static String noteOf(Decision body) {
        return body == null ? null : body.note();
    }

    private ResponseEntity<?> decide(java.util.function.Supplier<RiderCashOut> action) {
        try {
            return ResponseEntity.ok(cashOutPayload(action.get()));
        } catch (IllegalArgumentException | IllegalStateException e) {
            return ResponseEntity.badRequest().body(Map.of("error", e.getMessage()));
        }
    }

    /**
     * The zone the rider's calendar runs on.
     *
     * <p>Caller-supplied and therefore validated rather than trusted: {@code ZoneId.of} on an
     * arbitrary string throws, and an unhandled one would be a 500 for a typo.
     */
    private ZoneId zoneOf(String zone) {
        if (zone == null || zone.isBlank()) {
            return earnings.defaultZone();
        }
        try {
            return ZoneId.of(zone.trim());
        } catch (java.time.DateTimeException e) {
            throw new IllegalArgumentException("Not a timezone this server knows");
        }
    }

    private Map<String, Object> balancePayload(String riderRef) {
        BigDecimal balance = earnings.balanceOf(riderRef);
        BigDecimal available = earnings.availableFor(riderRef);

        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("currency", earnings.currency());
        // What the platform owes before anything is netted off.
        payload.put("balance", balance);
        // What can actually be asked for, after cash the rider is still carrying. Negative means
        // they are holding more of the platform's money than it owes them, and it is shown that way
        // rather than clamped: a zero would read as having earned nothing.
        payload.put("available", available);
        payload.put("cashFloatHeld", balance.subtract(available));
        payload.put("minimumCashOut", earnings.minimumCashOut());
        // So the app can promise the right thing. Nothing pays automatically today, and a screen
        // that implies an instant transfer is a support ticket an hour later.
        payload.put("payoutIsAutomated", earnings.payoutIsAutomated());
        payload.put("openCashOut", earnings.openCashOutFor(riderRef)
                .map(RiderEarningsController::cashOutPayload)
                .orElse(null));
        return payload;
    }

    /**
     * The day-by-day series.
     *
     * <p>Built by hand rather than serialising the record, so the day is an ISO string on both
     * endpoints that return it. A chart that has to handle two date encodings depending on which
     * call it made is a chart that will one day handle one of them wrongly.
     */
    private static List<Map<String, Object>> seriesPayload(
            List<RiderEarningsService.DayTotal> series) {
        return series.stream().map(d -> {
            Map<String, Object> day = new LinkedHashMap<>();
            day.put("day", d.day().toString());
            day.put("earnings", d.earnings());
            day.put("tips", d.tips());
            day.put("total", d.total());
            day.put("jobs", d.jobs());
            return day;
        }).toList();
    }

    private static Map<String, Object> totalPayload(RiderEarningsService.Total total) {
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("earnings", total.earnings());
        payload.put("tips", total.tips());
        payload.put("total", total.total());
        payload.put("jobs", total.jobs());
        return payload;
    }

    private static Map<String, Object> jobPayload(RiderEarningsService.Job job) {
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("orderId", job.orderId());
        payload.put("earned", job.earned());
        payload.put("tip", job.tip());
        payload.put("reimbursement", job.reimbursement());
        payload.put("fleet", job.fleet());
        // CARRIER here means the rider's own company owes this, not the platform. The app has to be
        // able to say so — showing a rider a figure the platform will never hand over, with nothing
        // to distinguish it, is the one way this screen can be actively misleading.
        payload.put("payableBy", job.payableBy());
        payload.put("deliveredAt", job.deliveredAt());
        return payload;
    }

    private static Map<String, Object> cashOutPayload(RiderCashOut request) {
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("id", request.getId());
        payload.put("riderRef", request.getRiderRef());
        payload.put("amount", request.getAmount());
        payload.put("currency", request.getCurrency());
        payload.put("status", request.getStatus());
        payload.put("payoutNote", request.getPayoutNote());
        payload.put("requestedAt", request.getRequestedAt());
        payload.put("decidedBy", request.getDecidedBy());
        payload.put("decidedAt", request.getDecidedAt());
        payload.put("decisionNote", request.getDecisionNote());
        payload.put("paymentRef", request.getPaymentRef());
        payload.put("paidVia", request.getPaidVia());
        return payload;
    }
}
