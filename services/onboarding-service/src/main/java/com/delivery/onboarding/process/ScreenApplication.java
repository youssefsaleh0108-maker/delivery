package com.delivery.onboarding.process;

import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import org.camunda.bpm.engine.delegate.DelegateExecution;
import org.camunda.bpm.engine.delegate.JavaDelegate;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

import com.delivery.onboarding.domain.OnboardingApplication;
import com.delivery.onboarding.domain.OnboardingApplicationRepository;

/**
 * The cheap checks, before a person spends time on the application.
 *
 * <p>Deliberately annotates rather than decides. Nothing here rejects anybody: a duplicate name
 * might be a franchise, and a strange-looking phone number might be correct in a country the regex
 * author did not think about. What it does is put the problem in front of the reviewer so they see
 * it while deciding, instead of discovering it when provisioning fails half an hour later.
 */
@Component("screenApplication")
public class ScreenApplication implements JavaDelegate {

    private static final Logger log = LoggerFactory.getLogger(ScreenApplication.class);

    private final OnboardingApplicationRepository applications;

    public ScreenApplication(OnboardingApplicationRepository applications) {
        this.applications = applications;
    }

    @Override
    public void execute(DelegateExecution execution) {
        UUID applicationId = UUID.fromString((String) execution.getVariable("applicationId"));
        OnboardingApplication application = applications.findById(applicationId).orElse(null);
        if (application == null) {
            // The row is written before the process starts, so this cannot happen from the normal
            // path. Recorded rather than thrown: failing the process would leave a live application
            // no reviewer can reach.
            log.error("Screening asked about application {}, which does not exist", applicationId);
            execution.setVariable("flags", List.of("application record missing"));
            return;
        }

        List<String> flags = new ArrayList<>();

        if (applications.existsByBusinessNameIgnoreCaseAndStatusIn(
                application.getBusinessName(),
                List.of(OnboardingApplication.Status.APPROVED,
                        OnboardingApplication.Status.PROVISIONED))) {
            // Not fatal: a second branch of a chain is a real thing, and so is somebody reapplying
            // after a rename. The reviewer decides which of those this is.
            flags.add("A partner with this name is already live");
        }

        if (!application.getContactEmail().contains("@")) {
            flags.add("The contact email does not look like an address");
        }

        // Deliberately loose. Numbers in this market are written half a dozen ways, and a strict
        // pattern would flag more correct numbers than wrong ones.
        //
        // Absent is not a flag. A phone number is optional and one that was given has already been
        // proved by a code, so the only thing left to catch here is a proved number that is somehow
        // too short to dial.
        if (application.getContactPhone() != null) {
            String digits = application.getContactPhone().replaceAll("\\D", "");
            if (digits.length() < 7) {
                flags.add("The contact phone looks too short to dial");
            }
        }

        execution.setVariable("flags", flags);
        execution.setVariable("kind", application.getKind().name());
        log.info("Screened application {} ({}): {} flag(s)",
                applicationId, application.getBusinessName(), flags.size());
    }
}
