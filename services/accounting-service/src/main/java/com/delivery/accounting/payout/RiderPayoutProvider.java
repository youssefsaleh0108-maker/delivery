package com.delivery.accounting.payout;

import java.math.BigDecimal;
import java.util.UUID;

/**
 * Whatever actually moves money to a rider.
 *
 * <p>Same shape as the notification connectors' {@code ProviderClient}: an interface, an
 * implementation that is obviously not an automated payment rail, and a runtime switch. It exists
 * here for the same reason it exists there — the commercial decision has not been made, and the
 * rest of the system should be finished and exercised before it is.
 *
 * <p><strong>There is no real implementation of this interface in the repository.</strong> Paying a
 * rider needs a payment processor account (a mobile wallet, a Stripe Connect account, a bank's
 * disbursement API) with credentials the owner has not supplied, and writing something that looked
 * like one would be worse than not having it: a cash-out that silently "succeeded" is a rider who
 * thinks they were paid. {@link ManualPayoutProvider} is what ships, and it says out loud that a
 * human moved the money.
 *
 * <p>Implementations must be idempotent on {@link PayoutRequest#cashOutId()}. This is called at
 * most once per cash-out today, but a retry after a timeout is the obvious next requirement, and a
 * provider that pays twice for one id is the expensive kind of bug.
 */
public interface RiderPayoutProvider {

    /**
     * The name recorded on the paid row, and the value {@code delivery.rider-payout.provider} takes.
     */
    String name();

    /** Hands the money over. */
    Payout pay(PayoutRequest request);

    /**
     * One payout to make.
     *
     * @param cashOutId         the request being paid; the idempotency key
     * @param riderRef          who is being paid
     * @param amount            how much, in {@code currency}
     * @param riderNote         the rider's own free-text instruction — which wallet, who to hand it
     *                          to. Untrusted text typed by the rider: never logged, never rendered
     *                          without escaping, and never parsed into an account number
     * @param operatorReference what the operator says identifies the payment they made, on the
     *                          manual path. Null when a provider generates its own reference
     */
    record PayoutRequest(UUID cashOutId, String riderRef, BigDecimal amount, String currency,
                         String riderNote, String operatorReference) {
    }

    /**
     * What a provider says happened.
     *
     * <p>{@code reference} is the number quoted in a dispute. {@code settled} being false is a
     * refusal, not an exception: a provider declining a payout is an ordinary outcome the caller
     * has to record, and throwing would make it indistinguishable from the provider being down.
     */
    record Payout(boolean settled, String provider, String reference, String failureReason) {

        public static Payout settled(String provider, String reference) {
            return new Payout(true, provider, reference, null);
        }

        public static Payout refused(String provider, String reason) {
            return new Payout(false, provider, null, reason);
        }
    }
}
