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

import com.delivery.accounting.domain.AccountingTransaction;
import com.delivery.accounting.domain.AccountingTransactionRepository;
import com.delivery.accounting.domain.CashFloatRepository;
import com.delivery.accounting.service.CashFloatService;
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

    public ReconciliationController(AccountingTransactionRepository transactions,
                                    CashFloatRepository floatEntries,
                                    CashFloatService cashFloat,
                                    CoreBankingSyncLogRepository syncLog) {
        this.transactions = transactions;
        this.floatEntries = floatEntries;
        this.cashFloat = cashFloat;
        this.syncLog = syncLog;
    }

    /**
     * Records that a holder has banked everything they were carrying.
     *
     * <p>BACKOFFICE only, and deliberately so: this is somebody at the platform confirming that
     * money physically arrived. A rider marking their own float clear would be the one party with
     * an incentive to get it wrong.
     */
    @PostMapping("/float/{holderRef}/remit")
    public ResponseEntity<Map<String, Object>> remit(@PathVariable String holderRef) {
        return cashFloat.remitAll(holderRef, MDC.get(CorrelationIdFilter.MDC_KEY))
                .<ResponseEntity<Map<String, Object>>>map(r -> ResponseEntity.ok(Map.of(
                        "remittanceId", r.id(),
                        "holderRef", r.holderRef(),
                        "amount", r.amount(),
                        "collections", r.collections())))
                // Nothing outstanding is not an error — it is the answer to "have they banked it".
                .orElseGet(() -> ResponseEntity.ok(Map.of(
                        "holderRef", holderRef,
                        "amount", java.math.BigDecimal.ZERO,
                        "collections", 0)));
    }

    /**
     * Who is currently holding platform cash, largest first.
     *
     * <p>The collection list. Every row is money taken from a customer that has not reached a bank
     * account yet, and the age of the oldest entry is the part worth watching: a large balance
     * collected this morning is a working day, and the same balance collected three weeks ago is a
     * problem.
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
                    return out;
                })
                .toList();
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
