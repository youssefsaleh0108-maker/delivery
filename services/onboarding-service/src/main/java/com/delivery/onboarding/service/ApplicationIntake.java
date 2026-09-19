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
 *
 * <p><strong>Nothing in here waits on another service.</strong> Both front doors come through here,
 * and an application to offer services may only be recorded with an open category and a live area.
 * That check reads two lists from Product Service, and it used to be made in here, inside the write
 * transaction — which holds a pooled connection from the moment it begins. The pool is twelve,
 * shared with the workflow engine, and the check ran before any proof was spent, on a door open to
 * anybody: a slow Product Service and a stream of made-up applications could empty the pool in
 * seconds and take every endpoint of this service with it. So the front doors make the check first,
 * with no transaction open ({@link OnboardingService#submit}, {@link AccountApplicationService#apply}),
 * and this class takes only {@link ServiceProviderAnswers.Checked} details, which nothing but that
 * check can make. The rule still lives in one place; the compiler keeps it there instead of a call.
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
     *
     * @param details checked before this transaction began, so an answer the applicant has to change
     *                — or a Product Service outage — has cost them no proof
     */
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public OnboardingApplication record(OnboardingApplication.Kind kind, String businessName,
                                        String contactName, String contactEmail,
                                        String emailVerificationToken, String contactPhone,
                                        String phoneVerificationToken, String notes,
                                        ServiceProviderAnswers.Checked details,
                                        java.util.UUID targetProviderId) {

        Instant emailVerifiedAt = verifications.consume(
                emailVerificationToken, Channel.EMAIL, contactEmail);

        String phone = contactPhone == null || contactPhone.isBlank() ? null : contactPhone;
        Instant phoneVerifiedAt = phone == null
                ? null
                : verifications.consume(phoneVerificationToken, Channel.PHONE, phone);

        OnboardingApplication application = new OnboardingApplication(
                kind, businessName.trim(), contactName.trim(),
                verifications.normalise(Channel.EMAIL, contactEmail), emailVerifiedAt,
                phone == null ? null : verifications.normalise(Channel.PHONE, phone),
                phoneVerifiedAt, notes, details.details(), targetProviderId);

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

    /**
     * Records an application made by an account that already exists, all or nothing.
     *
     * <p>The signed-in twin of {@link #record}, for somebody who came in through Google and then
     * said they want to ride or to sell. Two things differ, and both follow from there being an
     * account already:
     *
     * <ul>
     *   <li><strong>No email token is spent.</strong> The address is the account's own, read from
     *       the caller's token, and the caller has already checked that the identity provider
     *       vouched for it. {@code emailVerifiedAt} is that moment. Asking for a one-time code on
     *       top would be proving the same inbox twice.
     *   <li><strong>The account is attached here, in the same insert.</strong> The open path
     *       attaches it later, when the applicant chooses a passcode. Doing it in the same
     *       transaction means there is no moment at which a committed row exists that the caller's
     *       own {@code /applications/mine} cannot find — which is what makes a retry idempotent
     *       rather than a second application.
     * </ul>
     *
     * <p>A phone number, when one is given, is still proved by its own code and the proof is spent
     * here, for the reason {@link #record} spends its proofs in the same transaction as the insert.
     *
     * @param emailVerifiedAt when the identity provider's word on the address was taken — never null
     * @param details         checked before this transaction began, as for {@link #record}
     */
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public OnboardingApplication recordForAccount(String userRef,
                                                  OnboardingApplication.Kind kind,
                                                  String businessName, String contactName,
                                                  String contactEmail, Instant emailVerifiedAt,
                                                  String contactPhone,
                                                  String phoneVerificationToken, String notes,
                                                  ServiceProviderAnswers.Checked details,
                                                  java.util.UUID targetProviderId) {

        String phone = contactPhone == null || contactPhone.isBlank() ? null : contactPhone;
        Instant phoneVerifiedAt = phone == null
                ? null
                : verifications.consume(phoneVerificationToken, Channel.PHONE, phone);

        OnboardingApplication application = new OnboardingApplication(
                kind, businessName.trim(), contactName.trim(),
                verifications.normalise(Channel.EMAIL, contactEmail), emailVerifiedAt,
                phone == null ? null : verifications.normalise(Channel.PHONE, phone),
                phoneVerifiedAt, notes, details.details(), targetProviderId);
        application.applicantAccountCreated(userRef);

        try {
            applications.saveAndFlush(application);
        } catch (DataIntegrityViolationException e) {
            // Either index can refuse this: one open application per email per kind, or one
            // application per account. Both mean the same thing to the person asking.
            throw new OnboardingService.ApplicationRuleException(
                    "You already have an application in progress for this business");
        }
        return application;
    }

    /**
     * Records the sign-in an applicant just chose against their application, and commits it.
     *
     * <p>The open path's counterpart of the attach {@link #recordForAccount} makes in its insert, and
     * REQUIRES_NEW for the reason this class exists: it commits on its own, before anything is tried
     * on top of it. What is tried next is auto-approval, and an approval that fails must never take
     * the sign-in with it. It used to, when both were one transaction: the applicant was told their
     * sign-in could not be set up while Keycloak kept the account (see
     * {@link OnboardingService#createApplicantAccount}).
     *
     * <p>The same account arriving twice is not a second sign-in — two taps racing both bring the
     * account the first one made or took up. Any other account on the row is.
     */
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public OnboardingApplication attachApplicantAccount(java.util.UUID applicationId, String userRef) {
        OnboardingApplication application = applications.findById(applicationId)
                .orElseThrow(() -> new OnboardingService.ApplicationRuleException(
                        "No application with that reference"));
        if (userRef.equals(application.getApplicantUserRef())) {
            return application;
        }
        if (application.getApplicantUserRef() != null) {
            throw OnboardingService.signInExists();
        }
        application.applicantAccountCreated(userRef);
        try {
            applications.saveAndFlush(application);
        } catch (DataIntegrityViolationException e) {
            // One application per account: applicant_user_ref is unique. The caller checked before it
            // took an existing account up, so this is another application getting there first — and
            // to the applicant it means what that check means: the address has an account already.
            // The caller takes back what its take-up granted (OnboardingService.createApplicantAccount).
            throw OnboardingService.accountExists();
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
