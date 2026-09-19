package com.delivery.onboarding.service;

import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import org.camunda.bpm.engine.RuntimeService;
import org.camunda.bpm.engine.TaskService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.InOrder;
import org.springframework.web.client.ResourceAccessException;

import com.delivery.onboarding.client.KeycloakAdminClient;
import com.delivery.onboarding.domain.AutoApprovalAuditRepository;
import com.delivery.onboarding.domain.AutoApprovalDecisionRepository;
import com.delivery.onboarding.domain.OnboardingApplication;
import com.delivery.onboarding.domain.OnboardingApplication.Kind;
import com.delivery.onboarding.domain.OnboardingApplicationRepository;
import com.delivery.onboarding.domain.PartnerEditEntryRepository;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyMap;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.RETURNS_DEEP_STUBS;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.inOrder;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

/**
 * A declined applicant stops exploring as what they applied to be.
 *
 * <p>Their account holds the live role from the moment they chose a passcode, APPLICANT beside it,
 * so they can look around while they wait. {@code reject} used to leave Keycloak alone, so a rider
 * turned down kept reading the job board for good. The role now goes with the decision, inside its
 * transaction and before the engine tells them — a Keycloak failure fails the rejection instead of
 * announcing one whose access change never happened.
 */
class DeclinedApplicantAccessTest {

    private OnboardingApplicationRepository applications;
    private TaskService tasks;
    private KeycloakAdminClient keycloak;
    private OnboardingService onboarding;

    private OnboardingApplication sam;

    @BeforeEach
    void setUp() {
        applications = mock(OnboardingApplicationRepository.class);
        tasks = mock(TaskService.class, RETURNS_DEEP_STUBS);
        keycloak = mock(KeycloakAdminClient.class);
        onboarding = new OnboardingService(applications, mock(ApplicationIntake.class),
                mock(VerificationService.class), mock(ServiceProviderAnswers.class),
                mock(RuntimeService.class), tasks, keycloak, mock(ApplicantDocumentService.class),
                new AutoApprovalPolicy(false, false, false,
                        mock(AutoApprovalDecisionRepository.class),
                        mock(AutoApprovalAuditRepository.class)),
                mock(org.springframework.transaction.PlatformTransactionManager.class),
                mock(PartnerEditEntryRepository.class));

        sam = new OnboardingApplication(Kind.RIDER, "Sam Salem", "Sam Salem", "sam@example.test",
                Instant.now(), null, null, null, null, null);
        sam.startedAs("process-sam");
        when(applications.findById(sam.getId())).thenReturn(Optional.of(sam));
    }

    @Test
    @DisplayName("the account loses the role applied for, before the engine tells them; APPLICANT stays")
    void the_live_role_goes_with_the_decision() {
        sam.applicantAccountCreated("kc-sam");
        when(keycloak.realmRolesOf("kc-sam")).thenReturn(List.of("APPLICANT", "DELIVERY"));

        onboarding.reject(sam.getId(), "reviewer-1", "We are not taking riders in that area");

        InOrder order = inOrder(keycloak, tasks);
        order.verify(keycloak).revokeRealmRole("kc-sam", "DELIVERY");
        order.verify(tasks).complete(any(), eq(Map.of("approved", false)));
        verify(keycloak, never()).revokeRealmRole("kc-sam", "APPLICANT");
        assertThat(sam.getStatus()).isEqualTo(OnboardingApplication.Status.REJECTED);
    }

    @Test
    @DisplayName("an account that does not hold the role is left as it is")
    void no_role_nothing_to_take() {
        sam.applicantAccountCreated("kc-sam");
        when(keycloak.realmRolesOf("kc-sam")).thenReturn(List.of("APPLICANT"));

        onboarding.reject(sam.getId(), "reviewer-1", "We are not taking riders in that area");

        verify(keycloak, never()).revokeRealmRole(any(), any());
    }

    @Test
    @DisplayName("an application nobody chose a passcode for has no account to change")
    void no_sign_in_no_account() {
        onboarding.reject(sam.getId(), "reviewer-1", "We are not taking riders in that area");

        verifyNoInteractions(keycloak);
    }

    @Test
    @DisplayName("Keycloak refusing fails the rejection, and nobody is told of it")
    void keycloak_refusing_fails_the_rejection() {
        sam.applicantAccountCreated("kc-sam");
        when(keycloak.realmRolesOf("kc-sam")).thenReturn(List.of("APPLICANT", "DELIVERY"));
        doThrow(new ResourceAccessException("Connection refused"))
                .when(keycloak).revokeRealmRole("kc-sam", "DELIVERY");

        assertThatThrownBy(() -> onboarding.reject(sam.getId(), "reviewer-1", "Not in that area"))
                .isInstanceOf(ResourceAccessException.class);
        verify(tasks, never()).complete(any(), anyMap());
    }
}
