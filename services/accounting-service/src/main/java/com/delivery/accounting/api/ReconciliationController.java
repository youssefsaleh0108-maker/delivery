package com.delivery.accounting.api;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.springframework.dao.DataIntegrityViolationException;
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
    private final CashFloatService cashFloat;
    private final CoreBankingSyncLogRepository syncLog;
    private final CarrierCashService carrierCash;
    private final com.delivery.accounting.service.SettlementFailures failures;
    private final com.delivery.accounting.service.SettlementRecovery recovery;

    public ReconciliationController(AccountingTransactionRepository transactions,
                                    CashFloatService cashFloat,
                                    CoreBankingSyncLogRepository syncLog,
                                    CarrierCashService carrierCash,
                                    com.delivery.accounting.service.SettlementFailures failures,
                                    com.delivery.accounting.service.SettlementRecovery recovery) {
        this.transactions = transactions;
        this.cashFloat = cashFloat;
        this.syncLog = syncLog;
        this.carrierCash = carrierCash;
        this.failures = failures;
        this.recovery = recovery;
    }

    /**
     * Records that a holder has banked everything they were carrying — a rider of the platform's own
     * fleet, a delivery company paying in what its riders handed it, or a shop paying in what its
     * counter took for pickup orders (V52).
     *
     * <p>BACKOFFICE only, and deliberately so: this is somebody at the platform confirming that
     * money physically arrived. A rider marking their own float clear would be the one party with
     * an incentive to get it wrong — and so would a company, and so would a shop.
     *
     * <p>The body is optional, so a caller written before it existed banks exactly as it always did.
     * With one, {@code expectedAmount} is the figure the operator counted against: a company's
     * balance grows with every hand-over at its hub, and if it moved since the page loaded nothing
     * is recorded and the answer is 409 with the current figure. {@code requestKey} makes a double
     * press harmless, and whoever is signed in is recorded as the person who confirmed it.
     *
     * <p><strong>A shop's till (V52)</strong> takes this route too, on its own terms: the shop keeps
     * its share and pays the platform only its commission, so {@code expectedAmount} is what the shop
     * owes — the {@code owed} figure the cash-on-hand list shows — and never the till, and it is
     * required (400 {@code AMOUNT_REQUIRED} without it). The answer carries {@code retained}, the
     * share the shop kept.
     *
     * <p>{@code holderKind} says which of the account's cash is being paid in. One account can be a
     * shop with a till and a rider with a bag, settled on different terms, so when it holds both and
     * the body does not say, nothing is recorded and the answer is 409 {@code HOLDER_KIND_REQUIRED}.
     *
     * <p><strong>Only what is owed to the platform (RECON-03).</strong> A rider's cash from a
     * delivery company's jobs is owed to that company, which records its own hand-over, so banking a
     * rider clears their platform-fleet cash and nothing else — and {@code expectedAmount} is checked
     * against that figure, the {@code owed} of the rider's platform line on {@code /float}.
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
        // The shape the carrier's hand-over route accepts too. Refused here, before anything is
        // written: the column holds 64 characters, and a longer key used to fail only at commit — a
        // 500 for a payment that was simply not recorded.
        // A pay run's key is refused here too: see Callers#requestKeyProblem.
        String keyProblem = Callers.requestKeyProblem(key);
        if (keyProblem != null) {
            return ResponseEntity.badRequest().body(Map.of("error", keyProblem));
        }
        // Which of the account's cash is being paid in, when the caller says (V52). Unsaid is still
        // allowed, and refused only when the account really does hold more than one kind.
        CashFloatEntry.HolderKind holderKind = null;
        if (body != null && body.holderKind() != null && !body.holderKind().isBlank()) {
            holderKind = holderKindOf(body.holderKind());
            if (holderKind == null) {
                return ResponseEntity.badRequest().body(Map.of(
                        "error", "holderKind must be one of RIDER, PROVIDER or MERCHANT"));
            }
        }

        try {
            return cashFloat.remit(holderRef, MDC.get(CorrelationIdFilter.MDC_KEY),
                            body == null ? null : body.expectedAmount(),
                            new CashFloatEntry.Recorded(Callers.jwt().getSubject(), method, note,
                                    key),
                            holderKind)
                    .<ResponseEntity<?>>map(r -> {
                        Map<String, Object> out = new LinkedHashMap<>();
                        out.put("remittanceId", r.id());
                        out.put("holderRef", r.holderRef());
                        out.put("amount", r.amount());
                        out.put("collections", r.collections());
                        out.put("replayed", r.replayed());
                        // A shop's payment: the share it kept of its till, beside what it paid.
                        // Absent for everybody else, whose answer reads exactly as it always did.
                        if (r.retained().signum() != 0) {
                            out.put("retained", r.retained());
                        }
                        return ResponseEntity.ok(out);
                    })
                    // Nothing outstanding is not an error — it is the answer to "have they banked it".
                    .orElseGet(() -> ResponseEntity.ok(Map.of(
                            "holderRef", holderRef,
                            "amount", java.math.BigDecimal.ZERO,
                            "collections", 0)));
        } catch (CashFloatService.AmountChangedException e) {
            Map<String, Object> out = new LinkedHashMap<>();
            // A shop is asked for what it owes out of its till, never for the till, so its figure is
            // said that way (V52).
            out.put("error", (holderKind == CashFloatEntry.HolderKind.MERCHANT
                    ? "The shop owes " : "They are holding ")
                    + Statement.money(e.current()).toPlainString()
                    + " now, not the amount you confirmed. Nothing was recorded.");
            out.put("code", "AMOUNT_CHANGED");
            out.put("current", Statement.money(e.current()).toPlainString());
            return ResponseEntity.status(409).body(out);
        } catch (CashFloatService.HolderKindRequiredException e) {
            // A shop that also delivers holds a till and a rider's bag, settled on different terms:
            // nothing was recorded, and the caller says which of the two is paying.
            return ResponseEntity.status(409).body(Map.of(
                    "error", e.getMessage(), "code", "HOLDER_KIND_REQUIRED"));
        } catch (CashFloatService.AmountRequiredException e) {
            return ResponseEntity.badRequest().body(Map.of(
                    "error", e.getMessage(), "code", "AMOUNT_REQUIRED"));
        } catch (CashFloatService.RequestKeyReusedException e) {
            return ResponseEntity.status(409).body(Map.of(
                    "error", e.getMessage(), "code", "REQUEST_KEY_REUSED"));
        } catch (DataIntegrityViolationException e) {
            // Two presses with one key racing past the replay check: the unique index refused the
            // second at commit, and the first was recorded. Saying so is the honest answer, as on
            // the carrier's hand-over route.
            return ResponseEntity.status(409).body(Map.of(
                    "error", "That has already been recorded. Reload to see it.",
                    "code", "ALREADY_RECORDED"));
        }
    }

    /** A holder kind named in a request, case aside; null for anything that is not one. */
    private static CashFloatEntry.HolderKind holderKindOf(String value) {
        for (CashFloatEntry.HolderKind kind : CashFloatEntry.HolderKind.values()) {
            if (kind.name().equalsIgnoreCase(value.trim())) {
                return kind;
            }
        }
        return null;
    }

    /**
     * {@code {"expectedAmount":"320.00","method":"BANK_DEPOSIT","note":"...","requestKey":"...",
     * "holderKind":"MERCHANT"}}.
     */
    public record RemitRequest(BigDecimal expectedAmount, String method, String note,
                               String requestKey, String holderKind) {
    }

    /**
     * Who is currently holding platform cash, largest first.
     *
     * <p>The collection list. Every row is money taken from a customer that has not reached a bank
     * account yet, and the age of the oldest entry is the part worth watching: a large balance
     * collected this morning is a working day, and the same balance collected three weeks ago is a
     * problem.
     *
     * <p>A delivery company appears here as a {@code PROVIDER} holder once its riders hand it cash,
     * and a shop as a {@code MERCHANT} holder once a pickup is paid at its counter (V52).
     * {@code overdue} is the server's call, by the limit for the cash each holder has: a day for a
     * rider of the platform's own fleet, as this list always flagged them, the carrier limit for
     * a company's custody — the one the company's own reconciliation page states, so the two cannot
     * disagree about what "late" means — and the shop limit for a shop's till. See
     * {@link CarrierCashService#cashOnHand()}.
     *
     * <p><strong>One line per debt (RECON-03).</strong> A rider carrying cash for a delivery company
     * as well as the platform's has a line for each: {@code carrierRef} names the company a line is
     * owed to, and is null on a line owed to the platform. Only a line owed to the platform carries
     * {@code owed}, the two-decimal string a payment through {@code /float/{ref}/remit} is recorded
     * against — the Back Office confirms that figure as {@code expectedAmount}. A company's line has
     * none, because it is not the platform's to record: the company takes that cash in at its hub,
     * and a remittance never clears it.
     *
     * <p>A shop's {@code owed} is not its till (V52): a shop keeps its share of its till and pays the
     * platform its commission, so {@code amount} is the cash it holds, {@code owed} is the platform's
     * part, and {@code retained} is the share it keeps.
     *
     * <p>The role is checked in the method as well as on the class, as on every cash route here: this
     * list names who holds the platform's money, and a standalone test can only prove a lock it can
     * see.
     */
    @GetMapping("/float")
    public ResponseEntity<?> outstandingFloat() {
        ResponseEntity<?> refusal = Callers.requireRole("BACKOFFICE");
        if (refusal != null) {
            return refusal;
        }
        List<CarrierCashService.OnHand> holders = carrierCash.cashOnHand();
        // Read only when a shop is on the list at all.
        Map<String, com.delivery.accounting.service.ShopTill> tills = holders.stream()
                .anyMatch(holder -> holder.holderKind() == CashFloatEntry.HolderKind.MERCHANT)
                ? cashFloat.shopTills()
                : Map.of();
        return ResponseEntity.ok(holders.stream()
                .map(holder -> {
                    Map<String, Object> out = new LinkedHashMap<String, Object>();
                    out.put("holderRef", holder.holderRef());
                    out.put("holderKind", holder.holderKind());
                    out.put("carrierRef", holder.carrierRef());
                    out.put("amount", holder.amount());
                    out.put("orders", holder.orders());
                    out.put("oldest", holder.oldest());
                    out.put("overdue", holder.overdue());
                    if (holder.holderKind() == CashFloatEntry.HolderKind.MERCHANT) {
                        var till = tills.get(holder.holderRef());
                        if (till != null) {
                            out.put("owed", Statement.money(till.owed()).toPlainString());
                            out.put("retained", Statement.money(till.retained()).toPlainString());
                        }
                    } else if (holder.owedToPlatform()) {
                        out.put("owed", Statement.money(holder.amount()).toPlainString());
                    }
                    return out;
                })
                .toList());
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
     * <p>{@code amountAtRisk} is the number that matters — value that has been debited from
     * customers but not yet paid out, or that failed on the way. A count of rows does not convey
     * that; an amount does.
     *
     * <p><strong>Debits are not added to credits (RECON-13).</strong> The two sides of an order are
     * the same money described twice — invariant I1 — so the old total counted every unfinished
     * settlement at double its worth: dev reported 331.26 at risk over two banked hand-overs worth
     * 331.26 between them, once as the collection and once as the payment. Each status now carries
     * its {@code debits} and {@code credits} apart, and the figure at risk is the larger of the two
     * across PENDING and FAILED: the money involved, counted once, whichever side of it is stuck.
     */
    @GetMapping("/summary")
    public Map<String, Object> summary() {
        Map<String, Map<String, Object>> byStatus = new LinkedHashMap<>();
        BigDecimal atRiskDebits = BigDecimal.ZERO;
        BigDecimal atRiskCredits = BigDecimal.ZERO;
        long unsettled = 0;

        for (Object[] row : transactions.summariseByStatusAndDirection()) {
            AccountingTransaction.Status status = (AccountingTransaction.Status) row[0];
            AccountingTransaction.Direction direction = (AccountingTransaction.Direction) row[1];
            long count = (Long) row[2];
            BigDecimal total = (BigDecimal) row[3];

            Map<String, Object> figures = byStatus.computeIfAbsent(status.name(), key -> {
                Map<String, Object> blank = new LinkedHashMap<>();
                blank.put("count", 0L);
                blank.put("debits", BigDecimal.ZERO);
                blank.put("credits", BigDecimal.ZERO);
                return blank;
            });
            boolean debit = direction == AccountingTransaction.Direction.DEBIT;
            figures.put("count", (Long) figures.get("count") + count);
            figures.put(debit ? "debits" : "credits",
                    ((BigDecimal) figures.get(debit ? "debits" : "credits")).add(total));

            if (status == AccountingTransaction.Status.PENDING
                    || status == AccountingTransaction.Status.FAILED) {
                if (debit) {
                    atRiskDebits = atRiskDebits.add(total);
                } else {
                    atRiskCredits = atRiskCredits.add(total);
                }
                unsettled += count;
            }
        }

        return Map.of(
                "byStatus", byStatus,
                "unsettledCount", unsettled,
                "amountAtRisk", atRiskDebits.max(atRiskCredits),
                // Both sides beside it, so nobody has to guess which one the figure above is.
                "atRiskDebits", atRiskDebits,
                "atRiskCredits", atRiskCredits);
    }

    /**
     * Settlements this service could not make and will not retry (RECON-04).
     *
     * <p>The other half of the work list, and the half that used to be invisible: a message that
     * cannot be settled is acknowledged, because one that comes back for ever blocks every good
     * one behind it, and what is left is a delivered order with no legs anywhere. Now each one is a
     * row here, with what stopped it and how many times it has arrived. The payload is deliberately
     * not returned — it carries a customer's address — and stays in the table for whoever needs it.
     */
    @GetMapping("/settlement-failures")
    public ResponseEntity<?> settlementFailures(@RequestParam(defaultValue = "50") int limit) {
        ResponseEntity<?> refusal = Callers.requireRole("BACKOFFICE");
        if (refusal != null) {
            return refusal;
        }
        return ResponseEntity.ok(Map.of(
                "open", failures.openCount(),
                "failures", failures.open(limit).stream().map(failure -> {
                    Map<String, Object> out = new LinkedHashMap<String, Object>();
                    out.put("id", failure.getId());
                    out.put("orderId", failure.getOrderId());
                    out.put("eventType", failure.getEventType());
                    out.put("reason", failure.getReason());
                    out.put("attempts", failure.getAttempts());
                    out.put("firstSeenAt", failure.getFirstSeenAt());
                    out.put("lastSeenAt", failure.getLastSeenAt());
                    return out;
                }).toList()));
    }

    /**
     * Delivered orders the ledger has never seen (RECON-04).
     *
     * <p>The check no view inside this service could make: a settlement lost on the bus leaves no
     * legs, and every reconciliation view reads legs. So Order Manager's delivered orders are
     * compared against the ledger, with the operator's own token — it is their right to read those
     * orders, not this service's standing one. Read-only; settling is the next call.
     */
    @GetMapping("/unsettled-deliveries")
    public ResponseEntity<?> unsettledDeliveries(@RequestParam(defaultValue = "100") int limit) {
        ResponseEntity<?> refusal = Callers.requireRole("BACKOFFICE");
        if (refusal != null) {
            return refusal;
        }
        try {
            return ResponseEntity.ok(recovery.unsettledDeliveries(
                    Callers.jwt().getTokenValue(), limit));
        } catch (com.delivery.accounting.service.OrderManagerOrdersClient.UnavailableException e) {
            // Deliberately not an empty list: "nothing is missing" and "nobody could be asked" are
            // different answers, and only one of them means there is nothing to do.
            return ResponseEntity.status(503).body(Map.of(
                    "error", "Order Manager could not be asked which orders were delivered.",
                    "code", "ORDER_MANAGER_UNAVAILABLE"));
        }
    }

    /**
     * Settles one delivered order from Order Manager's record of it (RECON-04).
     *
     * <p>The safe way to clear a settlement that was lost: the order is read back, shaped into the
     * event that went missing and settled through exactly the rules the listener applies — never a
     * second implementation of them, and never figures typed by an operator. Idempotent: an order
     * already in the ledger is left alone and answered as such.
     */
    @PostMapping("/orders/{orderId}/settle")
    public ResponseEntity<?> settleFromOrderManager(@PathVariable UUID orderId) {
        ResponseEntity<?> refusal = Callers.requireRole("BACKOFFICE");
        if (refusal != null) {
            return refusal;
        }
        try {
            var settled = recovery.settle(Callers.jwt().getTokenValue(), orderId,
                    Callers.jwt().getSubject());
            Map<String, Object> out = new LinkedHashMap<>();
            out.put("orderId", settled.orderId());
            out.put("settled", settled.settled());
            out.put("legs", settled.legs());
            if (settled.reason() != null) {
                out.put("reason", settled.reason());
            }
            return ResponseEntity.ok(out);
        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest().body(Map.of("error", e.getMessage()));
        } catch (com.delivery.accounting.service.OrderManagerOrdersClient.UnavailableException e) {
            return ResponseEntity.status(503).body(Map.of(
                    "error", "Order Manager could not be asked about that order.",
                    "code", "ORDER_MANAGER_UNAVAILABLE"));
        }
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
