package com.delivery.onboarding.service;

import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.function.Function;
import java.util.stream.Collectors;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.onboarding.domain.Iban;
import com.delivery.onboarding.domain.OnboardingApplication;
import com.delivery.onboarding.domain.PayoutDetails;
import com.delivery.onboarding.domain.PayoutDetailsRepository;
import com.delivery.onboarding.payout.PayoutAccountVerifier;
import com.delivery.onboarding.payout.PayoutVerifierRegistry;

/**
 * Where an approved applicant gets paid, and how much is actually known about that account.
 *
 * <p>Two things happen on every write, in this order and never the other way round. The number is
 * parsed and its check digits verified by {@link Iban} — if that fails nothing is stored, because a
 * mistyped IBAN in the database is a payout that bounces weeks later rather than a form error the
 * applicant can fix while they are still looking at the field. Then whatever verifier is configured
 * is asked what else can be established, and its answer is recorded with its name against it.
 *
 * <p>Today that verifier contacts no bank — see {@link PayoutAccountVerifier}. That is a fact about
 * the platform's vendor arrangements, not about this code, and the {@code verification_state}
 * column exists so it stays visible instead of being assumed away.
 *
 * <p>Nothing in this class logs an account number. The masked form is available on both
 * {@link Iban#toString()} and {@link PayoutDetails#toString()}, so the careless thing is already the
 * safe thing; the log lines below still name neither, because an account holder's name is personal
 * data that adds nothing to an operational log.
 */
@Service
public class PayoutDetailsService {

    private static final Logger log = LoggerFactory.getLogger(PayoutDetailsService.class);

    private final PayoutDetailsRepository payouts;
    private final PayoutVerifierRegistry verifiers;

    public PayoutDetailsService(PayoutDetailsRepository payouts, PayoutVerifierRegistry verifiers) {
        this.payouts = payouts;
        this.verifiers = verifiers;
    }

    /**
     * Sets or replaces an application's payout details.
     *
     * <p>Idempotent by application: there is one set of details per application, so submitting the
     * bank step twice corrects the first attempt rather than creating a second account nobody could
     * choose between at payout time.
     *
     * @param application the applicant's own, resolved from their token by the caller
     * @throws Iban.InvalidIbanException with a message safe to show whoever typed it
     */
    @Transactional
    public PayoutDetails save(OnboardingApplication application, String accountHolder, String rawIban) {
        requireOpenForEditing(application);

        Iban iban = Iban.parse(rawIban);
        String holder = accountHolder == null ? "" : accountHolder.trim();
        if (holder.isEmpty()) {
            throw new OnboardingService.ApplicationRuleException(
                    "The name on the account is required");
        }

        PayoutDetails details = payouts.findByApplicationId(application.getId())
                .map(existing -> {
                    existing.replaceWith(holder, iban);
                    return existing;
                })
                .orElseGet(() -> new PayoutDetails(application.getId(), holder, iban));

        PayoutAccountVerifier verifier = verifiers.active();
        PayoutAccountVerifier.Outcome outcome = verifier.verify(holder, iban);
        details.verifiedBy(verifier.name(), outcome.state());

        payouts.save(details);
        // Neither the number nor the holder's name. The application reference is enough to find the
        // row, and whoever can find the row is already entitled to read it.
        log.info("Payout details recorded for application {} ({} per {})",
                application.getReference(), outcome.state(), verifier.name());
        return details;
    }

    /**
     * The full details for one application.
     *
     * <p>Callers: the applicant reading back their own, and a reviewer looking at that one
     * application. Both of those checks live in the controller, because both are about who is
     * asking rather than about the payout row — but the audiences are worth naming here, because
     * this is the only method that returns an unmasked account number.
     */
    @Transactional(readOnly = true)
    public Optional<PayoutDetails> forApplication(UUID applicationId) {
        return payouts.findByApplicationId(applicationId);
    }

    /**
     * The masked details for a list of applications, keyed by application id.
     *
     * <p>One query rather than one per row: a queue of fifty applications should not be fifty round
     * trips to render "•••• 0002" fifty times. The caller only ever reads the masked form off these
     * — see {@code PayoutSummary}, which is the shape every listing uses.
     */
    @Transactional(readOnly = true)
    public Map<UUID, PayoutDetails> forApplications(List<UUID> applicationIds) {
        if (applicationIds.isEmpty()) {
            return Map.of();
        }
        return payouts.findByApplicationIdIn(applicationIds).stream()
                .collect(Collectors.toMap(PayoutDetails::getApplicationId, Function.identity()));
    }

    /**
     * An applicant may correct their bank details only while somebody is still deciding.
     *
     * <p>After approval the account is what the platform is about to pay, and changing it through
     * the applicant-facing onboarding endpoint would be a route to redirecting somebody's payouts
     * that bypasses whatever the payments side of the platform requires to do the same thing.
     */
    private void requireOpenForEditing(OnboardingApplication application) {
        if (application.isDecided()) {
            throw new OnboardingService.ApplicationRuleException(
                    "This application has already been decided; change payout details from your "
                            + "account settings instead");
        }
    }
}
