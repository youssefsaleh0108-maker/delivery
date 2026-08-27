package com.delivery.onboarding.payout;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

import com.delivery.onboarding.domain.Iban;

/**
 * The dev verifier: it checks the arithmetic and tells you plainly that it checked nothing else.
 *
 * <p>It exists so the whole payout chain — the wizard's bank step, the validation, the storage, the
 * masked listing, the reviewer's view — can be built and exercised before the platform has a
 * payment-processor account. That is the same reason {@code DevPassthroughSmsClient} exists in the
 * SMS connector, and this follows it deliberately.
 *
 * <p><strong>What it does not do.</strong> It does not contact a bank, because there is no bank to
 * contact. It therefore never returns {@code VERIFIED} and never returns {@code FAILED}: an
 * unconfigured verifier that silently reported success would be worse than no verifier at all,
 * because the state column exists precisely so that "we have never confirmed this account" stays
 * visible on the payout screen. Every row it touches is stamped {@code CHECKSUM_ONLY} and
 * attributed to {@link #NAME}, so when a real processor arrives it is one query to find every
 * account that was only ever arithmetic-checked.
 *
 * <p>It logs at INFO on every call, on purpose. This is a dev implementation running in front of
 * something that moves money; it should be impossible to look at a production log and believe an
 * account was verified.
 */
@Component
public class DevChecksumOnlyPayoutVerifier implements PayoutAccountVerifier {

    /** Written into {@code payout_details.verified_by}. Do not rename: stored rows point at it. */
    public static final String NAME = "DEV_CHECKSUM_ONLY";

    private static final Logger log = LoggerFactory.getLogger(DevChecksumOnlyPayoutVerifier.class);

    @Override
    public String name() {
        return NAME;
    }

    @Override
    public Outcome verify(String accountHolder, Iban iban) {
        // The masked form, from Iban.toString(). The account holder's name is not logged either:
        // it is applicant-supplied personal data and adds nothing to this line.
        log.info("Payout account {} passed its check digits. No bank was contacted — {} cannot "
                        + "confirm the account exists or who it belongs to.",
                iban, NAME);

        return Outcome.checksumOnly(
                "The account number is well formed and its check digits hold. It has not been "
                        + "confirmed with a bank.");
    }
}
