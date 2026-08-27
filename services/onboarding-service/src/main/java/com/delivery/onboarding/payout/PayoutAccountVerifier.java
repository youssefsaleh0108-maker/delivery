package com.delivery.onboarding.payout;

import com.delivery.onboarding.domain.Iban;
import com.delivery.onboarding.domain.PayoutDetails.VerificationState;

/**
 * Whatever can be asked about a bank account beyond the arithmetic.
 *
 * <p>The mod-97 check in {@link Iban} proves a number is well formed and was not mistyped. It
 * cannot prove the account exists, is open, or belongs to the name on the application — the only
 * thing that can is a bank, reached through a payment processor. This interface is the seam where
 * that lives, following the same shape as {@code ProviderClient} in the SMS connector: one
 * implementation per vendor, selected by name at runtime, so switching processor is configuration
 * rather than a development project.
 *
 * <p><strong>There is exactly one implementation today and it is the dev one.</strong>
 * {@link DevChecksumOnlyPayoutVerifier} contacts nothing and says so, in its name, in its logs and
 * in the {@link VerificationState#CHECKSUM_ONLY} it records. A real implementation needs a merchant
 * account with a processor that offers account verification, which nobody has provisioned — see the
 * handover notes. Until one exists, no payout account on this platform has been confirmed to
 * belong to anybody, and the state column is what keeps that fact visible rather than assumed.
 */
public interface PayoutAccountVerifier {

    /**
     * The name this verifier is selected by, and the name written into
     * {@code payout_details.verified_by}. Stable: it ends up in stored rows, so renaming one makes
     * historical rows unattributable.
     */
    String name();

    /**
     * What can be established about this account.
     *
     * @param accountHolder the name the applicant gave. A real processor compares it against the
     *                      name the bank holds, which is the check that actually catches a
     *                      well-formed IBAN belonging to somebody else
     * @param iban          already parsed and checksum-valid; a verifier is never handed raw input
     */
    Outcome verify(String accountHolder, Iban iban);

    /**
     * @param state  what to record against the account
     * @param detail why, in words a reviewer can act on. Never contains the account number — this
     *               string reaches logs and API responses
     */
    record Outcome(VerificationState state, String detail) {

        public static Outcome checksumOnly(String detail) {
            return new Outcome(VerificationState.CHECKSUM_ONLY, detail);
        }

        public static Outcome verified(String detail) {
            return new Outcome(VerificationState.VERIFIED, detail);
        }

        public static Outcome failed(String detail) {
            return new Outcome(VerificationState.FAILED, detail);
        }
    }
}
