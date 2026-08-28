package com.delivery.onboarding.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.onboarding.client.KeycloakAdminClient;
import com.delivery.onboarding.domain.ContactVerification.Channel;
import com.delivery.onboarding.domain.ContactVerification.Purpose;

/**
 * The sign-in screen's "Forgot password", made of parts that already exist.
 *
 * <p>The proof is the same one-time-code machinery every other flow uses — same cooldown, same
 * daily cap, same wrong-guess limit — under a purpose of its own, {@link Purpose#PASSWORD_RESET},
 * so a reset code cannot confirm a sign-up and a sign-up code cannot reset a passcode. The
 * replacement itself is Keycloak's reset-password admin call, so the passcode never touches this
 * service's storage in any form.
 *
 * <p><strong>The endpoint must not become a directory of who has an account.</strong> Everything
 * here is shaped by that: the request answers 202 for every well-formed address; the challenge row
 * and the rate limits are recorded whether or not the account exists, so a cooldown refusal cannot
 * distinguish the two; and even a relay failure — which for a sign-up code is reported honestly —
 * is swallowed here, because it can only happen for addresses that do have an account.
 */
@Service
public class PasswordResetService {

    private static final Logger log = LoggerFactory.getLogger(PasswordResetService.class);

    private final VerificationService verifications;
    private final KeycloakAdminClient keycloak;

    public PasswordResetService(VerificationService verifications, KeycloakAdminClient keycloak) {
        this.verifications = verifications;
        this.keycloak = keycloak;
    }

    /**
     * Asks for a reset code. Nothing about the outcome says whether the account exists.
     *
     * <p>The account lookup happens inside the supplier, which VerificationService evaluates only
     * after the abuse limits have passed — so a spray of requests hits the limits, not Keycloak.
     * A failed lookup (Keycloak unreachable) is treated as "no account": no code goes out, the
     * caller still gets a 202, and the operator gets the error line. Sending a code that the
     * confirm step could not act on anyway would only promise something the platform cannot
     * currently deliver.
     */
    public void request(String email) {
        try {
            verifications.requestPasswordReset(email, () -> {
                try {
                    return keycloak.findUserIdByEmail(
                            VerificationService.normalise(Channel.EMAIL, email)).isPresent();
                } catch (Exception e) {
                    log.error("Could not look an account up for a password reset", e);
                    return false;
                }
            });
        } catch (VerificationService.CodeSendFailedException e) {
            // Swallowed deliberately, and only this subtype. A send can only fail for an address
            // that has an account — no send is attempted otherwise — so reporting it would answer
            // exactly the question this endpoint exists to not answer. The person retries off the
            // same 202 screen; the operator has the error line from the send itself.
            log.error("A password-reset code could not be sent; the caller was told nothing");
        }
    }

    /**
     * Answers the code and replaces the passcode.
     *
     * <p>The order is the same as sign-up and for the same reason. The proof is confirmed and
     * spent first, inside this transaction, so one code cannot underwrite two resets by racing;
     * Keycloak is called second, and if it refuses the transaction rolls back and the proof is
     * returned — the person can retry with the code they still hold rather than requesting a new
     * one into the cooldown they just started.
     *
     * <p>An address that answers its code correctly but has no account gets the wrong-code
     * wording. It is the honest refusal that reveals nothing: reaching this state requires the
     * code from a challenge that was recorded but never sent, so a caller who lands here is
     * guessing, and a distinct message would tell them what they were probing for.
     */
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void confirm(String email, String code, String newPassword) {
        VerificationService.Confirmed confirmed = verifications.confirm(
                Channel.EMAIL, email, code, Purpose.PASSWORD_RESET);
        verifications.consume(confirmed.token(), Channel.EMAIL, confirmed.destination(),
                Purpose.PASSWORD_RESET);

        String userRef = keycloak.findUserIdByEmail(confirmed.destination())
                .orElseThrow(() -> new VerificationService.VerificationException(
                        "That code is not right, or it has expired. Ask for a new one."));

        keycloak.resetPassword(userRef, newPassword);
        // The address is not logged beside the outcome: "who reset their passcode when" is
        // answerable from Keycloak's own event log, which is where credential history belongs.
        log.info("A passcode was reset through the forgot-password flow");
    }
}
