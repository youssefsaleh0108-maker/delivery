package com.delivery.onboarding.process;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.camunda.bpm.engine.delegate.DelegateExecution;
import org.camunda.bpm.model.bpmn.Bpmn;
import org.camunda.bpm.model.bpmn.BpmnModelInstance;
import org.camunda.bpm.model.bpmn.instance.FlowNode;
import org.camunda.bpm.model.bpmn.instance.ServiceTask;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.InOrder;

import com.delivery.onboarding.client.KeycloakAdminClient;
import com.delivery.onboarding.client.PlatformClient;
import com.delivery.onboarding.domain.OnboardingApplication;
import com.delivery.onboarding.domain.OnboardingApplication.Kind;
import com.delivery.onboarding.domain.OnboardingApplicationRepository;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.inOrder;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

/**
 * Approval takes APPLICANT away last: after the account has its role and the shop or the fleet
 * exists, and before anybody is told.
 *
 * <p>The approval's steps run in the reviewer's transaction, so a step that fails rolls the decision
 * back — but not Keycloak. Taking APPLICANT used to be part of creating the account, before a rider
 * was attached to their company, so an attach that failed left an application back in the queue on
 * an account that could already claim deliveries. The real definition is read here, so the order is
 * the one the engine runs.
 */
class ApplicantReleasedLastTest {

    private static final String SAM = "kc-sam";

    private OnboardingApplicationRepository applications;
    private KeycloakAdminClient keycloak;
    private PlatformClient platform;

    @BeforeEach
    void setUp() {
        applications = mock(OnboardingApplicationRepository.class);
        keycloak = mock(KeycloakAdminClient.class);
        platform = mock(PlatformClient.class);
    }

    private static BpmnModelInstance deployed() {
        return Bpmn.readModelFromStream(
                ApplicantReleasedLastTest.class.getResourceAsStream("/processes/partner-onboarding.bpmn"));
    }

    /** The definition as it was before the release step, which instances started then still run. */
    private static BpmnModelInstance before() {
        return Bpmn.createExecutableProcess("partner-onboarding")
                .startEvent("submitted").userTask("review")
                .serviceTask("provision").serviceTask("create-entity").serviceTask("welcome")
                .endEvent("live").done();
    }

    /** Sam's rider application, approved, with the sign-in Sam chose a passcode for. */
    private OnboardingApplication approvedRider(String applicantRef) {
        OnboardingApplication application = new OnboardingApplication(Kind.RIDER, "Sam Salem",
                "Sam Salem", "sam@example.test", Instant.now(), null, null, null, null,
                UUID.randomUUID());
        if (applicantRef != null) {
            application.applicantAccountCreated(applicantRef);
        }
        application.approve("reviewer-1");
        when(applications.findById(application.getId())).thenReturn(Optional.of(application));
        return application;
    }

    private static DelegateExecution running(OnboardingApplication application,
                                             BpmnModelInstance definition) {
        DelegateExecution execution = mock(DelegateExecution.class);
        when(execution.getVariable("applicationId")).thenReturn(application.getId().toString());
        when(execution.getBpmnModelInstance()).thenReturn(definition);
        return execution;
    }

    @Test
    @DisplayName("the approved branch runs: account, shop or fleet, let them act, tell them")
    void the_release_is_the_last_step_that_can_fail() {
        BpmnModelInstance definition = deployed();

        List<String> approvedBranch = new ArrayList<>();
        FlowNode node = definition.getModelElementById("provision");
        while (node != null) {
            approvedBranch.add(node.getId());
            node = node.getOutgoing().isEmpty() ? null : node.getOutgoing().iterator().next().getTarget();
        }

        assertThat(approvedBranch).containsExactly("provision", "create-entity", "release", "welcome", "live");
        assertThat(definition.<ServiceTask>getModelElementById("release").getCamundaDelegateExpression())
                .isEqualTo("${releaseApplicant}");
    }

    @Test
    @DisplayName("creating the account grants the live role and leaves APPLICANT on")
    void provisioning_leaves_applicant_on() {
        OnboardingApplication sam = approvedRider(SAM);
        DelegateExecution execution = running(sam, deployed());

        new ProvisionAccount(applications, keycloak).execute(execution);

        verify(keycloak).grantRealmRole(SAM, "DELIVERY");
        verify(keycloak, never()).revokeRealmRole(any(), any());
        verify(execution).setVariable("userRef", SAM);
    }

    @Test
    @DisplayName("an attach that fails leaves APPLICANT where it was")
    void a_failed_attach_leaves_the_account_held_back() {
        OnboardingApplication sam = approvedRider(SAM);
        DelegateExecution execution = running(sam, deployed());
        when(execution.getVariable("userRef")).thenReturn(SAM);
        doThrow(new IllegalStateException("order-manager refused to attach the rider"))
                .when(platform).attachRider(any(), any());

        new ProvisionAccount(applications, keycloak).execute(execution);
        assertThatThrownBy(() -> new CreatePartnerRecord(applications, platform, UUID.randomUUID())
                .execute(execution)).hasMessageContaining("refused to attach");

        verify(keycloak, never()).revokeRealmRole(any(), any());
    }

    @Test
    @DisplayName("once the rider is attached, the release takes APPLICANT away — the only thing it does")
    void the_release_lets_them_act() {
        OnboardingApplication sam = approvedRider(SAM);
        DelegateExecution execution = running(sam, deployed());
        when(execution.getVariable("userRef")).thenReturn(SAM);

        new ProvisionAccount(applications, keycloak).execute(execution);
        new CreatePartnerRecord(applications, platform, UUID.randomUUID()).execute(execution);
        new ReleaseApplicant(applications, keycloak).execute(execution);

        InOrder order = inOrder(keycloak, platform);
        order.verify(keycloak).grantRealmRole(SAM, "DELIVERY");
        order.verify(platform).attachRider(sam.getTargetProviderId(), SAM);
        order.verify(keycloak).revokeRealmRole(SAM, "APPLICANT");
    }

    @Test
    @DisplayName("a partner with no applicant account has nothing held back to release")
    void nothing_to_release_without_an_applicant_account() {
        OnboardingApplication oldWay = approvedRider(null);

        new ReleaseApplicant(applications, keycloak).execute(running(oldWay, deployed()));

        verifyNoInteractions(keycloak);
    }

    @Test
    @DisplayName("an instance still on the definition from before the release step takes APPLICANT "
            + "when the account is made, as it always did")
    void an_older_definition_still_lets_them_act() {
        OnboardingApplication sam = approvedRider(SAM);

        new ProvisionAccount(applications, keycloak).execute(running(sam, before()));

        InOrder order = inOrder(keycloak);
        order.verify(keycloak).grantRealmRole(SAM, "DELIVERY");
        order.verify(keycloak).revokeRealmRole(SAM, "APPLICANT");
    }
}
