package com.delivery.accounting.api;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.springframework.data.domain.PageRequest;
import org.springframework.security.access.prepost.PreAuthorize;
import org.slf4j.MDC;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import org.springframework.web.bind.annotation.RequestBody;

import com.delivery.accounting.domain.AccountingTransaction;
import com.delivery.accounting.domain.AccountingTransactionRepository;
import com.delivery.accounting.domain.CashFloatEntry;
import com.delivery.accounting.domain.CashFloatRepository;
import com.delivery.accounting.service.CarrierCashService;
import com.delivery.accounting.service.CashFloatService;
import com.delivery.accounting.service.Statement;
import com.delivery.platform.observability.CorrelationIdFilter;
import com.delivery.accounting.domain.CoreBankingSyncLogRepository;

/**
 * The reconciliation API (Section 4, Phase 4). BACKOFFICE only.
 *
 * <p>Built around one question — <em>what has not settled</em> — rather than around browsing every
 * transaction. A finance view that lists everything makes the handful of stuck rows the hardest
 * thing on screen to find, which is the opposite of what it is for.
 *
 * <p>The whole controller is BACKOFFICE-gated. Unlike the notification log there is no self-service
 * view: a customer has no business reading ledger rows, and their own record of what they paid is
 * the order.
 */
@RestController
@RequestMapping("/api/accounting")
@PreAuthorize("hasRole('BACKOFFICE')")
public class ReconciliationController {

    private static final int MAX_PAGE = 200;

    private final AccountingTransactionRepository transactions;
    private final CashFloatRepository floatEntries;
    private final CashFloatService cashFloat;
    private final CoreBankingSyncLogRepository syncLog;
    private final CarrierCashService carrierCash;

    public ReconciliationController(AccountingTransactionRepository transactions,
                                    CashFloatRepository floatEntries,
                                    CashFloatService cashFloat,
                                    CoreBankingSyncLogRepository syncLog,
                                    CarrierCashService carrierCash) {
        this.transactions = transactions;
        this.floatEntries = floatEntries;
        this.cashFloat = cashFloat;
        this.syncLog = syncLog;
        this.carrierCash = carrierCash;
    }

    /**
     * Records that a holder has banked everything they were carrying — a rider of the platform's own
     * fleet, or a delivery company paying in what its riders handed it.
     *
     * <p>BACKOFFICE only, and deliberately so: this is somebody at the platform confirming that
     * money physically arrived. A rider marking their own float clear would be the one party with
     * an incentive to get it wrong — and so would a company.
     *
     * <p>The body is optional, so a caller written before it existed banks exactly as it always did.
     * With one, {@code expectedAmount} is the figure the operator counted against: a company's
     * balance grows with every hand-over at its hub, and if it moved since the page loaded nothing
     * is recorded and the answer is 409 with the current figure. {@code requestKey} makes a double
     * press harmless, and whoever is signed in is recorded as the person who confirmed it.
     */
    @PostMapping("/float/{holderRef}/remit")
    public ResponseEntity<?> remit(@PathVariable String holderRef,
                                   @RequestBody(required = false) RemitRequest body) {
        ResponseEntity<?> refusal = Callers.requireRole("BACKOFFICE");
        if (refusal != null) {
            return refusal;
        }
        CashFloatEntry.Method method = null;
        if (body != null && body.method() != null && !body.method().isBlank()) {
            method = CashFloatEntry.Method.parse(body.method());
            if (method == null) {
                return ResponseEntity.badRequest().body(Map.of(
                        "error", "method must be one of CASH, BANK_DEPOSIT or WALLET"));
            }
        }
        String note = body == null || body.note() == null || body.note().isBlank()
                ? null
                : body.note().trim().substring(0, Math.min(body.note().trim().length(), 500));
        String key = body == null || body.requestKey() == null || body.requestKey().isBlank()
                ? null
                : body.requestKey().trim();

        try {
            return cashFloat.remit(holderRef, MDC.get(CorrelationIdFilter.MDC_KEY),
                            body == null ? null : body.expectedAmount(),
                            new CashFloatEntry.Recorded(Callers.jwt().getSubject(), method, note,
                                    key))
                    .<ResponseEntity<?>>map(r -> {
                        Map<String, Object> out = new LinkedHashMap<>();
                        out.put("remittanceId", r.id());
                        out.put("holderRef", r.holderRef());
                        out.put("amount", r.amount());
                        out.put("collections", r.collections());
                        out.put("replayed", r.replayed());
                        return ResponseEntity.ok(out);
                    })
                    // Nothing outstanding is not an error — it is the answer to "have they banked it".
                    .orElseGet(() -> ResponseEntity.ok(Map.of(
                            "holderRef", holderRef,
                            "amount", java.math.BigDecimal.ZERO,
                            "collections", 0)));
        } catch (CashFloatService.AmountChangedException e) {
            Map<String, Object> out = new LinkedHashMap<>();
            out.put("error", "They are holding " + Statement.money(e.current()).toPlainString()
                    + " now, not the amount you confirmed. Nothing was recorded.");
            out.put("code", "AMOUNT_CHANGED");
            out.put("current", Statement.money(e.current()).toPlainString());
            return ResponseEntity.status(409).body(out);
        } catch (CashFloatService.RequestKeyReusedException e) {
            return ResponseEntity.status(409).body(Map.of(
                    "error", e.getMessage(), "code", "REQUEST_KEY_REUSED"));
        }
    }

    /** {@code {"expectedAmount":"320.00","method":"BANK_DEPOSIT","note":"...","requestKey":"..."}}. */
    public record RemitRequest(BigDecimal expectedAmount, String method, String note,
                               String requestKey) {
    }

    /**
     * Who is currently holding platform cash, largest first.
     *
     * <p>The collection list. Every row is money taken from a customer that has not reached a bank
     * account yet, and the age of the oldest entry is the part worth watching: a large balance
     * collected this morning is a working day, and the same balance collected three weeks ago is a
     * problem.
     *
     * <p>A delivery company appears here as a {@code PROVIDER} holder once its riders hand it cash.
     * {@code overdue} is decided by the server's configured limit, so this list and the carrier's own
     * reconciliation page cannot disagree about what "late" means.
     */
    @GetMapping("/float")
    public List<Map<String, Object>> outstandingFloat() {
        return floatEntries.outstandingByHolder().stream()
                .map(row -> {
                    Map<String, Object> out = new LinkedHashMap<String, Object>();
                    out.put("holderRef", row.getHolderRef());
                    out.put("holderKind", row.getHolderKind());
                    out.put("amount", row.getAmount());
                    out.put("orders", row.getOrders());
                    out.put("oldest", row.getOldest());
                    out.put("overdue", carrierCash.isOverdue(row.getOldest()));
                    return out;
                })
                .toList();
    }

    /**
     * Cash held by delivery companies: what each holds and owes the platform now, and what its
     * riders still hold for it.
     *
     * <p>The Back Office half of the custody model. A company's own balance is what an operator
     * records a payment against (through {@code /float/{ref}/remit}, as for any holder); its riders'
     * balance is reported beside it and never added to it, because that cash is owed to the company
     * until the company records the hand-over. Money as two-decimal strings.
     */
    @GetMapping("/float/carriers")
    public ResponseEntity<?> carriers() {
        ResponseEntity<?> refusal = Callers.requireRole("BACKOFFICE");
        if (refusal != null) {
            return refusal;
        }
        return ResponseEntity.ok(Map.of(
                "overdueAfterHours", carrierCash.overdueAfterHours(),
                "carriers", carrierCash.carriers().stream().map(c -> {
                    Map<String, Object> out = new LinkedHashMap<>();
                    out.put("carrierRef", c.carrierRef());
                    out.put("held", Statement.money(c.held()).toPlainString());
                    out.put("orders", c.orders());
                    out.put("oldest", c.oldest() == null ? null : c.oldest().toString());
                    out.put("overdue", c.overdue());
                    out.put("withRiders", Statement.money(c.withRiders()).toPlainString());
                    out.put("ridersHolding", c.ridersHolding());
                    out.put("ridersOldest",
                            c.ridersOldest() == null ? null : c.ridersOldest().toString());
                    out.put("lastPaidAt",
                            c.lastPaidAt() == null ? null : c.lastPaidAt().toString());
                    return out;
                }).toList()));
    }

    /**
     * The landing view: totals by status, and how much money is in an unresolved state.
     *
     * <p>{@code atRisk} is the number that matters — value that has been debited from customers but
     * not yet paid out, or that failed on the way. A count of rows does not convey that; an amount
     * does.
     */
    @GetMapping("/summary")
    public Map<String, Object> summary() {
        Map<String, Object> byStatus = new LinkedHashMap<>();
        BigDecimal atRisk = BigDecimal.ZERO;
        long unsettled = 0;

        for (Object[] row : transactions.summariseByStatus()) {
            AccountingTransaction.Status status = (AccountingTransaction.Status) row[0];
            long count = (Long) row[1];
            BigDecimal total = (BigDecimal) row[2];

            byStatus.put(status.name(), Map.of("count", count, "amount", total));

            if (status == AccountingTransaction.Status.PENDING
                    || status == AccountingTransaction.Status.FAILED) {
                atRisk = atRisk.add(total);
                unsettled += count;
            }
        }

        return Map.of(
                "byStatus", byStatus,
                "unsettledCount", unsettled,
                "amountAtRisk", atRisk);
    }

    /** Everything not in a terminal state — the work list. */
    @GetMapping("/unsettled")
    public List<TransactionResponse> unsettled(@RequestParam(defaultValue = "100") int limit) {
        return transactions.findUnsettled(PageRequest.of(0, capped(limit))).stream()
                .map(ReconciliationController::toResponse)
                .toList();
    }

    @GetMapping("/transactions")
    public List<TransactionResponse> byStatus(@RequestParam AccountingTransaction.Status status,
                                              @RequestParam(defaultValue = "100") int limit) {
        return transactions.findByStatusOrderByCreatedAtDesc(status, PageRequest.of(0, capped(limit)))
                .stream()
                .map(ReconciliationController::toResponse)
                .toList();
    }

    /** Every leg of one order's settlement, which is how a single dispute gets investigated. */
    @GetMapping("/orders/{orderId}")
    public List<TransactionResponse> forOrder(@PathVariable UUID orderId) {
        return transactions.findByOrderIdOrderByCreatedAt(orderId).stream()
                .map(ReconciliationController::toResponse)
                .toList();
    }

    /**
     * What was actually sent to the bank and what came back, for one leg.
     *
     * <p>The end of the trail: after "it says FAILED", this is the only thing that answers why.
     */
    @GetMapping("/transactions/{transactionId}/sync-log")
    public List<SyncLogResponse> syncLogFor(@PathVariable UUID transactionId) {
        return syncLog.findByTransactionIdOrderBySyncedAtDesc(transactionId).stream()
                .map(entry -> new SyncLogResponse(
                        entry.getId(),
                        entry.getProvider(),
                        entry.getOutcome().name(),
                        entry.getRequestPayload(),
                        entry.getResponsePayload(),
                        entry.getSyncedAt()))
                .toList();
    }

    private static int capped(int limit) {
        return Math.max(1, Math.min(limit, MAX_PAGE));
    }

    private static TransactionResponse toResponse(AccountingTransaction t) {
        return new TransactionResponse(
                t.getId(), t.getOrderId(), t.getLeg().name(), t.getAccountRef(),
                t.getAmount(), t.getCurrency(), t.getDirection().name(), t.getStatus().name(),
                t.getCoreBankingRef(), t.getFailureReason(), t.getAttempts(),
                t.getCreatedAt(), t.getPostedAt());
    }

    public record TransactionResponse(
            UUID id,
            UUID orderId,
            String leg,
            String accountRef,
            BigDecimal amount,
            String currency,
            String direction,
            String status,
            String coreBankingRef,
            String failureReason,
            int attempts,
            Instant createdAt,
            Instant postedAt) {
    }

    public record SyncLogResponse(
            UUID id,
            String provider,
            String outcome,
            String requestPayload,
            String responsePayload,
            Instant syncedAt) {
    }
}
