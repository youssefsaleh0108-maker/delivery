package com.delivery.corebanking.simulator.api;

import java.time.Instant;
import java.util.List;
import java.util.Optional;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Positive;

import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.delivery.corebanking.simulator.domain.BankAccount;
import com.delivery.corebanking.simulator.domain.BankPosting;
import com.delivery.corebanking.simulator.service.FaultInjector;
import com.delivery.corebanking.simulator.service.LedgerService;

/**
 * The bank's contract, as far as this platform is concerned: look up an account, debit it, credit
 * it, and ask what happened to a posting.
 *
 * <p><strong>This shape is a placeholder for the real bank's published spec.</strong> Section 12
 * open decision #5 leaves ownership of keeping the two in step unassigned, and until the real spec
 * is in hand every field name here is a guess. That is exactly why the connector talks to a narrow
 * client interface: when the real contract arrives, it changes one implementation class.
 *
 * <p>Errors are returned as HTTP statuses a real bank would use, because those statuses drive the
 * connector's retry classification. A rejection the bank is certain about is a 422, and retrying it
 * is pointless; a 503 says come back later.
 */
@RestController
@RequestMapping("/api/core-banking")
public class CoreBankingController {

    private final LedgerService ledger;
    private final FaultInjector faults;

    public CoreBankingController(LedgerService ledger, FaultInjector faults) {
        this.ledger = ledger;
        this.faults = faults;
    }

    @GetMapping("/accounts/{accountRef}")
    public ResponseEntity<AccountResponse> account(@PathVariable String accountRef) {
        faults.maybeFail();
        return ledger.account(accountRef)
                .map(CoreBankingController::toResponse)
                .map(ResponseEntity::ok)
                .orElseGet(() -> ResponseEntity.notFound().build());
    }

    @PostMapping("/postings")
    public ResponseEntity<PostingResponse> post(@Valid @RequestBody PostingRequest request) {
        // Injected before anything is written, so an injected outage looks to the connector exactly
        // like a real one: no posting made, safe to retry.
        faults.maybeFail();

        LedgerService.Result result;
        try {
            result = ledger.post(
                    request.clientReference(),
                    request.accountRef(),
                    request.direction(),
                    request.amountMinor(),
                    request.currency() == null ? "USD" : request.currency(),
                    request.narrative());

        } catch (LedgerService.ConcurrentReplayException e) {
            // A concurrent retry won the race. Read back the winner and answer with it — from the
            // caller's point of view this is indistinguishable from the ordinary replay path,
            // which is the point.
            BankPosting winner = ledger.posting(request.clientReference()).orElseThrow();
            return ResponseEntity.ok(toResponse(winner, true));
        }

        BankPosting posting = result.posting();
        if (posting.getStatus() == BankPosting.Status.REJECTED) {
            // 422, not 400: the request was well-formed, the bank simply refused it. The connector
            // reads this as permanent and does not burn its retry budget.
            return ResponseEntity.unprocessableEntity().body(toResponse(posting, false));
        }
        // 200 rather than 201 on a replay, so a caller can tell a fresh posting from an echo.
        return result.replayed()
                ? ResponseEntity.ok(toResponse(posting, true))
                : ResponseEntity.status(HttpStatus.CREATED).body(toResponse(posting, false));
    }

    /** "Did that posting go through?" — the reconciliation path, keyed on the caller's own reference. */
    @GetMapping("/postings/{clientReference}")
    public ResponseEntity<PostingResponse> status(@PathVariable String clientReference) {
        faults.maybeFail();
        Optional<BankPosting> posting = ledger.posting(clientReference);
        return posting
                .map(p -> ResponseEntity.ok(toResponse(p, true)))
                .orElseGet(() -> ResponseEntity.notFound().build());
    }

    private static AccountResponse toResponse(BankAccount account) {
        return new AccountResponse(
                account.getAccountRef(),
                account.getHolderName(),
                account.getBalanceMinor(),
                account.getCurrency(),
                account.getStatus().name());
    }

    private static PostingResponse toResponse(BankPosting posting, boolean replayed) {
        return new PostingResponse(
                posting.getId().toString(),
                posting.getClientReference(),
                posting.getAccountRef(),
                posting.getDirection().name(),
                posting.getAmountMinor(),
                posting.getCurrency(),
                posting.getStatus().name(),
                posting.getBalanceAfterMinor(),
                posting.getRejectionReason(),
                replayed,
                posting.getPostedAt());
    }

    public record PostingRequest(
            /* The caller's idempotency key. Required: without one this endpoint cannot be safely
               retried, and every caller of a bank retries. */
            @NotBlank String clientReference,
            @NotBlank String accountRef,
            BankPosting.Direction direction,
            @Positive long amountMinor,
            String currency,
            String narrative) {
    }

    public record AccountResponse(
            String accountRef,
            String holderName,
            long balanceMinor,
            String currency,
            String status) {
    }

    public record PostingResponse(
            String postingId,
            String clientReference,
            String accountRef,
            String direction,
            long amountMinor,
            String currency,
            String status,
            Long balanceAfterMinor,
            String rejectionReason,
            boolean replayed,
            Instant postedAt) {
    }

    /**
     * Injected faults surface as 503, the status a real bank returns when it is unavailable — so
     * the connector treats them as retryable without knowing they were injected.
     */
    @ExceptionHandler(FaultInjector.InjectedFaultException.class)
    public ProblemDetail onInjectedFault(FaultInjector.InjectedFaultException e) {
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(
                HttpStatus.SERVICE_UNAVAILABLE, e.getMessage());
        problem.setTitle("Core banking unavailable");
        return problem;
    }

    @ExceptionHandler(IllegalArgumentException.class)
    public ProblemDetail onInvalid(IllegalArgumentException e) {
        return ProblemDetail.forStatusAndDetail(HttpStatus.BAD_REQUEST, e.getMessage());
    }

    /** Exposed so an operator (or a smoke test) can see the fake accounts without a psql session. */
    @GetMapping("/accounts")
    public List<AccountResponse> accounts() {
        return ledger.allAccounts().stream().map(CoreBankingController::toResponse).toList();
    }
}
