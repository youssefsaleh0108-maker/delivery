package com.delivery.onboarding.process;

import java.util.UUID;

import org.camunda.bpm.engine.delegate.DelegateExecution;
import org.camunda.bpm.engine.delegate.JavaDelegate;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

import com.delivery.onboarding.client.PlatformClient;
import com.delivery.onboarding.domain.OnboardingApplication;
import com.delivery.onboarding.domain.OnboardingApplicationRepository;

/**
 * Tells the applicant what was decided.
 *
 * <p>Both outcomes, not just the good one. Silence after a rejection produces the phone call, the
 * reapplication, and the same review done twice — so the decline path runs through here as well.
 *
 * <p>This used to log and not send, because the notification layer could only address a Keycloak
 * user id and a rejected applicant never gets one. Notifications Manager now takes a raw address for
 * exactly this case, so the mail goes out — and the address is worth sending to precisely because it
 * was verified before the application was accepted.
 */
@Component("notifyApplicant")
public class NotifyApplicant implements JavaDelegate {

    private static final Logger log = LoggerFactory.getLogger(NotifyApplicant.class);

    private final OnboardingApplicationRepository applications;
    private final PlatformClient platform;

    public NotifyApplicant(OnboardingApplicationRepository applications, PlatformClient platform) {
        this.applications = applications;
        this.platform = platform;
    }

    @Override
    public void execute(DelegateExecution execution) {
        UUID applicationId = UUID.fromString((String) execution.getVariable("applicationId"));
        OnboardingApplication application = applications.findById(applicationId).orElse(null);
        if (application == null) {
            log.warn("Nothing to notify about: application {} is gone", applicationId);
            return;
        }

        boolean rejected = application.getStatus() == OnboardingApplication.Status.REJECTED;

        String subject = rejected ? "About your application" : "You are approved";

        // The approved text used to say "we have created your account, choose forgot password to
        // set one". That stopped being true when applicants started choosing a passcode at the end
        // of the form: they already have an account, and telling somebody to reset a password they
        // never set sends them round a loop for no reason.
        String body = rejected
                ? "Thank you for applying with " + application.getBusinessName() + "."
                + "\n\nWe are not able to take it forward this time: "
                + application.getRejectionReason()
                + "\n\nIf that changes, you are welcome to apply again."
                : "Good news — " + application.getBusinessName() + " is approved."
                + "\n\nSign in with the passcode you chose when you applied. Everything you could"
                + " look at before now works for real: "
                + (application.getKind() == OnboardingApplication.Kind.RIDER
                        ? "you can take deliveries from the board."
                        : "you can publish to the market.")
                + "\n\nYour reference is " + application.getReference() + ".";

        try {
            platform.notifyDirect("EMAIL", application.getContactEmail(), subject, body,
                    "onboarding.decision");
        } catch (Exception e) {
            // Logged, not rethrown. The decision has already been made and recorded, and failing
            // the process step here would leave a decided application stuck mid-workflow over an
            // email — the applicant can still see the outcome against their reference, which is
            // worse than being told but far better than being un-decided.
            log.error("Could not email the decision on application {} — it stands regardless",
                    application.getReference(), e);
        }

        // And a push, because they are holding the app. An email about a decision they have been
        // waiting on can sit unread for a day; the phone in their hand cannot.
        //
        // Only when they signed up with a passcode — an older applicant has no account to address,
        // and somebody who applied from a browser has no device on file. Both are quiet no-ops.
        String applicantRef = application.getApplicantUserRef();
        if (applicantRef != null) {
            try {
                platform.notifyDirectPush(applicantRef, subject,
                        rejected
                                ? "We could not take your application forward. Open the app for the reason."
                                : "You are approved. Open the app — you can start straight away.",
                        "onboarding.decision");
            } catch (Exception e) {
                // Same reasoning as the email above, and more so: this is the second of two ways
                // they are being told.
                log.error("Could not push the decision on application {} — it stands regardless",
                        application.getReference(), e);
            }
        }
    }
}
