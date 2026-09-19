package com.delivery.onboarding.process;

import java.util.UUID;

import org.camunda.bpm.engine.delegate.DelegateExecution;
import org.camunda.bpm.engine.delegate.JavaDelegate;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

import com.delivery.onboarding.client.KeycloakAdminClient;
import com.delivery.onboarding.domain.OnboardingApplication;
import com.delivery.onboarding.domain.OnboardingApplicationRepository;

/**
 * Lets an approved partner act: takes APPLICANT off the account they applied with.
 *
 * <p>The last step of an approval that can fail, after the account has its role and the shop or the
 * fleet exists — a rider attached to their company — and before anybody is told they are in. The
 * order is the point. The approval's steps run in the reviewer's transaction, so a step that fails
 * rolls the decision back; Keycloak is outside that transaction and keeps whatever was done to it.
 * This used to happen in {@link ProvisionAccount}, before the attach, and an attach that failed then
 * left an application back in the queue on an account that had already lost APPLICANT: undecided,
 * and able to claim deliveries. Now every step that can fail has succeeded before APPLICANT goes.
 * Telling them comes after, and it never fails a decision (see {@link NotifyApplicant}).
 *
 * <p>Nothing to do for a partner provisioned the old way, who never had an applicant account: their
 * account was made with the role and never held APPLICANT. Taking away a role the account does not
 * hold is a no-op in Keycloak, so a retry of this step is harmless.
 */
@Component("releaseApplicant")
public class ReleaseApplicant implements JavaDelegate {

    /** This step's id in {@code partner-onboarding.bpmn}. */
    static final String STEP = "release";

    private static final Logger log = LoggerFactory.getLogger(ReleaseApplicant.class);

    private final OnboardingApplicationRepository applications;
    private final KeycloakAdminClient keycloak;

    public ReleaseApplicant(OnboardingApplicationRepository applications,
                            KeycloakAdminClient keycloak) {
        this.applications = applications;
        this.keycloak = keycloak;
    }

    /**
     * Whether the definition this execution runs has this step still to come.
     *
     * <p>Camunda keeps an instance on the definition it started with. One that was waiting for review
     * when this step was added finishes on the older definition, which has no release — so
     * {@link ProvisionAccount} has to take APPLICANT away itself there, as it always did, or that
     * partner would be approved and never able to act.
     */
    static boolean comesLater(DelegateExecution execution) {
        return execution.getBpmnModelInstance() != null
                && execution.getBpmnModelInstance().getModelElementById(STEP) != null;
    }

    @Override
    public void execute(DelegateExecution execution) {
        UUID applicationId = UUID.fromString((String) execution.getVariable("applicationId"));
        OnboardingApplication application = applications.findById(applicationId)
                .orElseThrow(() -> new IllegalStateException(
                        "Application " + applicationId + " vanished mid-process"));

        String applicantRef = application.getApplicantUserRef();
        if (applicantRef == null) {
            log.info("Application {} has no applicant account; nothing held back to release",
                    applicationId);
            return;
        }
        keycloak.revokeRealmRole(applicantRef, "APPLICANT");
        log.info("Application {} is set up; {} can now act, not just explore",
                applicationId, applicantRef);
    }
}
