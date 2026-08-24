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
 * Creates the account the new partner signs in with.
 *
 * <p>Its own step, separate from creating their shop or fleet, because the two fail for unrelated
 * reasons. A Keycloak outage should not roll back a perfectly good domain record, and the engine
 * resuming at the step that failed is the whole reason this is a process rather than a method.
 *
 * <p>Idempotent by inspection: an account already recorded on the application is not created twice.
 * Camunda retries a failed job three times by default, and the second attempt after a timeout that
 * actually succeeded would otherwise fail on a duplicate username and strand the application.
 */
@Component("provisionAccount")
public class ProvisionAccount implements JavaDelegate {

    private static final Logger log = LoggerFactory.getLogger(ProvisionAccount.class);

    private final OnboardingApplicationRepository applications;
    private final KeycloakAdminClient keycloak;

    public ProvisionAccount(OnboardingApplicationRepository applications,
                            KeycloakAdminClient keycloak) {
        this.applications = applications;
        this.keycloak = keycloak;
    }

    @Override
    public void execute(DelegateExecution execution) {
        UUID applicationId = UUID.fromString((String) execution.getVariable("applicationId"));
        OnboardingApplication application = applications.findById(applicationId)
                .orElseThrow(() -> new IllegalStateException(
                        "Application " + applicationId + " vanished mid-process"));

        if (application.getProvisionedUserRef() != null) {
            log.info("Application {} already has an account; not creating a second", applicationId);
            execution.setVariable("userRef", application.getProvisionedUserRef());
            return;
        }

        // The role their surface requires. All three are realm roles that already exist — this is
        // not the place to invent one, because a role nothing checks grants nothing.
        //
        // A rider gets DELIVERY, not CARRIER: DELIVERY is what the job board, the claim and the
        // pick-up endpoints check. CARRIER runs a company and opens the carrier portal, which is
        // the person doing the hiring rather than the person being hired.
        String role = switch (application.getKind()) {
            case MERCHANT -> "MERCHANT";
            case CARRIER -> "CARRIER";
            case RIDER -> "DELIVERY";
        };

        // They may already have signed in. An applicant who chose a passcode at the end of the form
        // has an account holding APPLICANT and nothing else, so approval GRANTS the real role to
        // that account rather than making a second one — otherwise the passcode they have been
        // using since they applied would stop working the moment they were accepted, which is the
        // worst possible time to hand somebody a new set of credentials.
        String applicantRef = application.getApplicantUserRef();
        if (applicantRef != null) {
            keycloak.grantRealmRole(applicantRef, role);
            execution.setVariable("userRef", applicantRef);
            log.info("Application {} approved; granted {} to existing account {}",
                    applicationId, role, applicantRef);
            return;
        }

        String userRef = keycloak.createPartner(
                application.getContactEmail(),
                firstNameOf(application.getContactName()),
                lastNameOf(application.getContactName()),
                role);

        execution.setVariable("userRef", userRef);
        log.info("Application {} provisioned account {} with role {}",
                applicationId, userRef, role);
    }

    /**
     * Splits a name somebody typed into one box.
     *
     * <p>Crude on purpose. Keycloak wants two fields and the form asks for one, so this is a
     * presentation guess rather than a fact — which is why nothing downstream uses these for
     * identity. Everything that matters keys on the subject id.
     */
    private static String firstNameOf(String contactName) {
        if (contactName == null || contactName.isBlank()) {
            return "";
        }
        int space = contactName.trim().indexOf(' ');
        return space < 0 ? contactName.trim() : contactName.trim().substring(0, space);
    }

    private static String lastNameOf(String contactName) {
        if (contactName == null) {
            return "";
        }
        int space = contactName.trim().indexOf(' ');
        return space < 0 ? "" : contactName.trim().substring(space + 1);
    }
}
