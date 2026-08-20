package com.delivery.corebanking.simulator.service;

import java.util.Optional;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.corebanking.simulator.domain.BankAccount;
import com.delivery.corebanking.simulator.domain.BankAccountRepository;
import com.delivery.corebanking.simulator.domain.BankPosting;
import com.delivery.corebanking.simulator.domain.BankPostingRepository;

/**
 * The simulator's ledger.
 *
 * <p>Rejections are classified the way a real bank's are, because the connector's retry behaviour
 * is driven off that classification and getting it wrong is expensive in both directions. An
 * unknown account or a frozen one will never succeed however many times it is retried. Insufficient
 * funds might, once the account is topped up — but retrying it in a tight loop is pointless, so it
 * is reported as a business rejection rather than a transient fault and the saga decides.
 */
@Service
public class LedgerService {

    private static final Logger log = LoggerFactory.getLogger(LedgerService.class);

    private final BankAccountRepository accounts;
    private final BankPostingRepository postings;

    public LedgerService(BankAccountRepository accounts, BankPostingRepository postings) {
        this.accounts = accounts;
        this.postings = postings;
    }

    @Transactional(readOnly = true)
    public Optional<BankAccount> account(String accountRef) {
        return accounts.findById(accountRef);
    }

    @Transactional(readOnly = true)
    public Optional<BankPosting> posting(String clientReference) {
        return postings.findByClientReference(clientReference);
    }

    @Transactional(readOnly = true)
    public java.util.List<BankAccount> allAccounts() {
        return accounts.findAll();
    }

    /**
     * Moves money, or explains why it did not.
     *
     * @return the posting, and whether it is a replay of one already made
     */
    @Transactional
    public Result post(String clientReference, String accountRef, BankPosting.Direction direction,
                       long amountMinor, String currency, String narrative) {

        // Idempotency, checked first. A retried debit must return the ORIGINAL posting rather than
        // move money again - this is the single most important behaviour in this service, and the
        // reason it is a real service with a real unique constraint rather than a mock.
        Optional<BankPosting> existing = postings.findByClientReference(clientReference);
        if (existing.isPresent()) {
            log.info("Replaying posting {} for client reference {}",
                    existing.get().getId(), clientReference);
            return new Result(existing.get(), true);
        }

        if (amountMinor <= 0) {
            return new Result(reject(clientReference, accountRef, direction, amountMinor, currency,
                    narrative, "AMOUNT_NOT_POSITIVE", "Amount must be greater than zero"), false);
        }

        Optional<BankAccount> found = accounts.findByIdForUpdate(accountRef);
        if (found.isEmpty()) {
            // Not persisted, unlike every other rejection: bank_postings has a foreign key to
            // bank_accounts, so recording a posting against an account that does not exist is
            // impossible by construction. Keeping the key is right — a ledger row pointing at
            // nothing is worse than an unrecorded refusal — so this one case answers without
            // writing.
            log.info("Rejecting {} of {} on unknown account {}", direction, amountMinor, accountRef);
            return new Result(BankPosting.rejected(clientReference, accountRef, direction,
                    amountMinor, currency, narrative, "UNKNOWN_ACCOUNT: No such account"), false);
        }

        BankAccount account = found.get();

        if (!account.canPost()) {
            return new Result(reject(clientReference, accountRef, direction, amountMinor, currency,
                    narrative, "ACCOUNT_" + account.getStatus(),
                    "Account is " + account.getStatus()), false);
        }

        if (!account.getCurrency().equals(currency)) {
            return new Result(reject(clientReference, accountRef, direction, amountMinor, currency,
                    narrative, "CURRENCY_MISMATCH",
                    "Account is held in " + account.getCurrency()), false);
        }

        if (direction == BankPosting.Direction.DEBIT && !account.hasFunds(amountMinor)) {
            return new Result(reject(clientReference, accountRef, direction, amountMinor, currency,
                    narrative, "INSUFFICIENT_FUNDS", "Balance is below the requested amount"), false);
        }

        if (direction == BankPosting.Direction.DEBIT) {
            account.debit(amountMinor);
        } else {
            account.credit(amountMinor);
        }

        try {
            BankPosting posted = postings.save(BankPosting.posted(clientReference, accountRef,
                    direction, amountMinor, currency, narrative, account.getBalanceMinor()));
            return new Result(posted, false);

        } catch (DataIntegrityViolationException e) {
            // The unique constraint fired, which means a concurrent retry of this same call won
            // the race between the check above and this insert. Correct outcome: one posting.
            // Rethrown so the transaction rolls back and the caller can read the winner.
            log.info("Concurrent replay of client reference {}", clientReference);
            throw new ConcurrentReplayException(clientReference);
        }
    }

    private BankPosting reject(String clientReference, String accountRef,
                               BankPosting.Direction direction, long amountMinor, String currency,
                               String narrative, String code, String reason) {
        log.info("Rejecting {} of {} on {}: {}", direction, amountMinor, accountRef, code);
        // Recorded, not discarded: a bank with no trace of a refused posting makes "we sent it,
        // they say they never got it" unanswerable.
        return postings.save(BankPosting.rejected(clientReference, accountRef, direction,
                amountMinor, currency, narrative, code + ": " + reason));
    }

    public record Result(BankPosting posting, boolean replayed) {
    }

    /** Signals that a concurrent caller already created this posting; read it back and return it. */
    public static class ConcurrentReplayException extends RuntimeException {
        public ConcurrentReplayException(String clientReference) {
            super("Posting already exists for client reference " + clientReference);
        }
    }
}
