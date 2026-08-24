package com.delivery.onboarding.process;

import java.util.UUID;

import org.camunda.bpm.engine.delegate.DelegateExecution;
import org.camunda.bpm.engine.delegate.JavaDelegate;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import com.delivery.onboarding.client.PlatformClient;
import com.delivery.onboarding.domain.OnboardingApplication;
import com.delivery.onboarding.domain.OnboardingApplicationRepository;

/**
 * Creates the shop or the fleet behind the new account.
 *
 * <p>Asymmetric, and deliberately so — the two partner kinds genuinely need different things:
 *
 * <ul>
 *   <li>A <strong>delivery company</strong> is a real record in Order Manager, with a payout
 *       account the bank is asked about on the way in. It has to exist before the company can be
 *       dispatched any work at all, so it is created here.
 *   <li>A <strong>merchant</strong> gets nothing extra. Product Service provisions a shop the
 *       moment they add their first product, and every store endpoint is scoped to the caller — so
 *       an empty store created here would be a row nobody asked for, named from a form rather than
 *       by the person who has to trade from it. The account with the MERCHANT role is the whole of
 *       what they need.
 * </ul>
 *
 * <p>Doing nothing for merchants is a decision, not an omission, which is why it is written down
 * rather than left as an empty branch.
 */
@Component("createPartnerRecord")
public class CreatePartnerRecord implements JavaDelegate {

    private static final Logger log = LoggerFactory.getLogger(CreatePartnerRecord.class);

    private final OnboardingApplicationRepository applications;
    private final PlatformClient platform;

    /**
     * MyDelivery's own fleet, for riders who applied to the platform rather than to a company.
     *
     * <p>Seeded by order-manager's V16 as the 'in-house' provider. Configurable rather than
     * inlined, because a deployment that runs no fleet of its own needs to point this somewhere
     * else — or find out at the first approval that it cannot.
     */
    private final UUID houseFleetId;

    public CreatePartnerRecord(OnboardingApplicationRepository applications,
                               PlatformClient platform,
                               @Value("${delivery.onboarding.house-fleet-id:00000000-0000-4000-8000-00000000d001}")
                               UUID houseFleetId) {
        this.applications = applications;
        this.platform = platform;
        this.houseFleetId = houseFleetId;
    }

    @Override
    public void execute(DelegateExecution execution) {
        UUID applicationId = UUID.fromString((String) execution.getVariable("applicationId"));
        OnboardingApplication application = applications.findById(applicationId)
                .orElseThrow(() -> new IllegalStateException(
                        "Application " + applicationId + " vanished mid-process"));

        String userRef = (String) execution.getVariable("userRef");
        if (userRef == null) {
            throw new IllegalStateException(
                    "No account was created, so there is nobody to attach a company to");
        }

        if (application.getProvisionedEntityId() != null) {
            // A retry after a timeout that had in fact succeeded. Registering a second company
            // would leave the platform paying two fleets for one applicant.
            log.info("Application {} already has a partner record", applicationId);
            return;
        }

        UUID entityId = null;
        switch (application.getKind()) {
            case CARRIER -> entityId = platform.registerCarrier(
                    application.getBusinessName(),
                    application.getContactName(),
                    application.getContactPhone(),
                    userRef);

            // A rider joins a fleet that already exists. They are attached as a RIDER, not as
            // staff: staff run the company and get the portal, riders carry for it and get the job
            // board. Only the rider list is consulted by dispatch and by a claim, so attaching a
            // rider as staff produces an account that looks attached and is offered no work.
            //
            // No company named means they applied to MyDelivery itself, so they join the house
            // fleet. Modelling it as an ordinary provider is what keeps this to one line: dispatch,
            // the job board and claims all work off the rider list and never learn the difference.
            case RIDER -> {
                entityId = application.getTargetProviderId() == null
                        ? houseFleetId
                        : application.getTargetProviderId();
                platform.attachRider(entityId, userRef);
            }

            case MERCHANT -> log.info(
                    "Application {} is a merchant; their shop appears with their first product",
                    applicationId);
        }

        application.provisionedAs(userRef, entityId);
        applications.save(application);
        execution.setVariable("entityId", entityId == null ? null : entityId.toString());
    }
}
