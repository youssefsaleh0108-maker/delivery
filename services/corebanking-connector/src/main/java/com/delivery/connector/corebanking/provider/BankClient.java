package com.delivery.connector.corebanking.provider;

import com.delivery.connector.corebanking.BankPostingCommand;
import com.delivery.platform.notifications.DeliveryOutcome;

/**
 * One core banking system this connector can talk to.
 *
 * <p>Two implementations from Phase 4: the dev simulator and the real bank. Which is live is a
 * Backoffice setting, exactly like the SMS vendor choice — so pointing staging at the real system
 * is a dropdown, not a release (Sections 7 and 8).
 *
 * <p>The interface is narrow on purpose. When the bank's real published spec arrives — Section 12
 * open decision #5 leaves ownership of that unassigned — the blast radius of matching it is one
 * implementation class.
 */
public interface BankClient {

    /** SIMULATOR or REAL. Must match the {@code CORE_BANKING} provider list in Connector Settings. */
    String name();

    /**
     * Posts the movement.
     *
     * <p>{@code command.transactionId()} must be passed to the bank as the client reference. That
     * is what makes a retried debit one debit rather than two, and it is the single most important
     * obligation on any implementation of this interface.
     */
    Response post(BankPostingCommand command);

    /**
     * The outcome plus the raw payloads either side of it.
     *
     * <p>The payloads exist so the accounting service can write them to
     * {@code core_banking_sync_log} — reconstructing "what did we actually send" from a status code
     * after the fact is not possible, and that is the first question in any dispute.
     */
    record Response(DeliveryOutcome outcome, String requestPayload, String responsePayload) {
    }

    /**
     * Asks whether an account exists and could be paid.
     *
     * <p>A question, not a command — which is why this one is allowed to be synchronous while
     * {@link #post} is not. Postings stay on a queue so a slow bank never holds up an order; a
     * lookup moves no money, has nothing to make idempotent, and answers a caller who is standing
     * there waiting for it.
     *
     * <p>Implementations must not report a bank they could not reach as a bad account. Those are
     * different answers and only one of them is the account holder's problem — see {@link Verdict}.
     */
    AccountCheck lookup(String accountRef);

    /**
     * What the bank said about an account.
     *
     * <p>Three-valued on purpose. Collapsing {@link #UNKNOWN} into {@link #REFUSED} would mean a
     * bank outage rejecting legitimate carriers; collapsing it into {@link #USABLE} would mean the
     * check silently passing exactly when it cannot be performed. Neither is honest, so the caller
     * is made to decide what an unanswerable question is worth.
     */
    enum Verdict {
        /** The account exists and can receive money. */
        USABLE,
        /** The bank is certain: no such account, or one that cannot be paid into. */
        REFUSED,
        /** The bank could not be asked. Says nothing about the account. */
        UNKNOWN
    }

    /**
     * @param holderName whoever the bank has on the account — worth showing back to an operator, who
     *                   is the only one who can spot a valid account belonging to the wrong company
     */
    record AccountCheck(Verdict verdict, String accountRef, String holderName, String detail) {

        public static AccountCheck usable(String accountRef, String holderName) {
            return new AccountCheck(Verdict.USABLE, accountRef, holderName, null);
        }

        public static AccountCheck refused(String accountRef, String detail) {
            return new AccountCheck(Verdict.REFUSED, accountRef, null, detail);
        }

        public static AccountCheck unknown(String accountRef, String detail) {
            return new AccountCheck(Verdict.UNKNOWN, accountRef, null, detail);
        }
    }
}
