package com.delivery.onboarding.service;

import java.time.Instant;

import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.onboarding.domain.ContactVerification.Channel;
import com.delivery.onboarding.domain.OnboardingApplication;
import com.delivery.onboarding.domain.OnboardingApplicationRepository;

/**
 * Writing down the application, and nothing else.
 *
 * <p>Its own bean purely so that the write commits on its own, before the workflow engine is
 * touched. That is not tidiness — it is the difference between the intended behaviour and what
 * actually happened.
 *
 * <p>The intent was always that a failure to start the review process should leave a recorded
 * application a reviewer can decide by hand, because an applicant who filled in a form and was
 * given a reference must never find that the reference means nothing. Catching the engine's
 * exception inside the same transaction cannot deliver that: Spring has already marked the
 * transaction rollback-only, so swallowing the exception only defers the failure to commit time,
 * where it surfaces as UnexpectedRollbackException and takes the application with it. The applicant
 * gets an error, the row is gone, and the log says the process merely did not start.
 *
 * <p>A separate bean rather than a second method on the caller, because Spring's transactions are
 * applied by a proxy: {@code this.record(...)} from inside the same class goes straight to the
 * method and gets no transaction at all.
 */
@Service
public class ApplicationIntake {

    private final OnboardingApplicationRepository applications;
    private final VerificationService verifications;

    public ApplicationIntake(OnboardingApplicationRepository applications,
                             VerificationService verifications) {
        this.applications = applications;
        this.verifications = verifications;
    }

    /**
     * Spends the proofs and records the application, all or nothing.
     *
     * <p>REQUIRES_NEW so this commits by itself even if a caller ever wraps it. The proofs are spent
     * in the same transaction as the insert deliberately: a token consumed against an application
     * that then failed to save would be a proof somebody can no longer use and cannot get back.
     */
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public OnboardingApplication record(OnboardingApplication.Kind kind, String businessName,
                                        String contactName, String contactEmail,
                                        String emailVerificationToken, String contactPhone,
                                        String phoneVerificationToken, String notes,
                                        java.util.Map<String, Object> details,
                                        java.util.UUID targetProviderId) {

        Instant emailVerifiedAt = verifications.consume(
                emailVerificationToken, Channel.EMAIL, contactEmail);

        String phone = contactPhone == null || contactPhone.isBlank() ? null : contactPhone;
        Instant phoneVerifiedAt = phone == null
                ? null
                : verifications.consume(phoneVerificationToken, Channel.PHONE, phone);

        OnboardingApplication application = new OnboardingApplication(
                kind, businessName.trim(), contactName.trim(),
                VerificationService.normalise(Channel.EMAIL, contactEmail), emailVerifiedAt,
                phone == null ? null : VerificationService.normalise(Channel.PHONE, phone),
                phoneVerifiedAt, notes, details, targetProviderId);

        try {
            applications.saveAndFlush(application);
        } catch (DataIntegrityViolationException e) {
            // The partial unique index: one live application per email per kind. Somebody applying
            // twice while the first is still being read is not two shops, and letting it through
            // means two reviewers doing the same work and possibly disagreeing.
            throw new OnboardingService.ApplicationRuleException(
                    "You already have an application in progress for this business");
        }
        return application;
    }

    /** Records the process instance against an application that is already committed. */
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void attachProcess(java.util.UUID applicationId, String processInstanceId) {
        applications.findById(applicationId).ifPresent(application -> {
            application.startedAs(processInstanceId);
            applications.save(application);
        });
    }
}
