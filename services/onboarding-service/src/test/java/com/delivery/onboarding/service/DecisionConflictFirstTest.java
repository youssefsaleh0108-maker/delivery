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
import org.springframework.dao.OptimisticLockingFailureException;
import org.springframework.orm.ObjectOptimisticLockingFailureException;

import com.delivery.onboarding.client.KeycloakAdminClient;
import com.delivery.onboarding.domain.AutoApprovalAuditRepository;
import com.delivery.onboarding.domain.AutoApprovalDecisionRepository;
import com.delivery.onboarding.domain.OnboardingApplication;
import com.delivery.onboarding.domain.OnboardingApplication.Kind;
import com.delivery.onboarding.domain.OnboardingApplicationRepository;
import com.delivery.onboarding.domain.PartnerEditEntryRepository;

import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyMap;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.RETURNS_DEEP_STUBS;
import static org.mockito.Mockito.inOrder;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

/**
 * A decision that loses a race changes nothing outside this service.
 *
 * <p>The application's version is checked by the UPDATE that writes the decision. That UPDATE used
 * to wait for the commit, which came after the engine had granted roles in Keycloak, attached a
 * rider to their company in Order Manager, taken APPLICANT away and told the applicant — so a
 * reviewer who lost to a sign-in being recorded, or to another reviewer, got a 409 for a decision
 * whose side effects had all happened. Both decisions now flush first, and a conflict stops them
 * before anything remote is touched. The real version check is proved against PostgreSQL in
 * {@code ApplicationVersionDatabaseTest}.
 */
class DecisionConflictFirstTest {

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
        sam.applicantAccountCreated("kc-sam");
        when(applications.findById(sam.getId())).thenReturn(Optional.of(sam));
        when(keycloak.realmRolesOf("kc-sam")).thenReturn(List.of("APPLICANT", "DELIVERY"));
    }

    /** What the database says when another write reached the row first. */
    private void somebodyWroteTheRowMeanwhile() {
        when(applications.saveAndFlush(sam)).thenThrow(
                new ObjectOptimisticLockingFailureException(OnboardingApplication.class, sam.getId()));
    }

    @Test
    @DisplayName("an approval is written and flushed before the engine is told")
    void an_approval_is_flushed_before_the_engine_runs() {
        onboarding.approve(sam.getId(), "reviewer-1");

        InOrder order = inOrder(applications, tasks);
        order.verify(applications).saveAndFlush(sam);
        order.verify(tasks).complete(any(), eq(Map.of("approved", true)));
        verify(applications, never()).save(any());
    }

    @Test
    @DisplayName("an approval that lost the race fails before any role, attach or message")
    void a_conflicting_approval_touches_nothing_remote() {
        somebodyWroteTheRowMeanwhile();

        assertThatThrownBy(() -> onboarding.approve(sam.getId(), "reviewer-1"))
                .isInstanceOf(OptimisticLockingFailureException.class);

        // The engine is what grants the role, attaches the rider, takes APPLICANT and tells them.
        verify(tasks, never()).complete(any(), anyMap());
        verifyNoInteractions(keycloak);
    }

    @Test
    @DisplayName("a rejection is written and flushed before Keycloak or the engine hears of it")
    void a_rejection_is_flushed_before_keycloak_and_the_engine() {
        onboarding.reject(sam.getId(), "reviewer-1", "We are not taking riders in that area");

        InOrder order = inOrder(applications, keycloak, tasks);
        order.verify(applications).saveAndFlush(sam);
        order.verify(keycloak).revokeRealmRole("kc-sam", "DELIVERY");
        order.verify(tasks).complete(any(), eq(Map.of("approved", false)));
        verify(applications, never()).save(any());
    }

    @Test
    @DisplayName("a rejection that lost the race leaves the role where it was and tells nobody")
    void a_conflicting_rejection_touches_nothing_remote() {
        somebodyWroteTheRowMeanwhile();

        assertThatThrownBy(() -> onboarding.reject(sam.getId(), "reviewer-1", "Not in that area"))
                .isInstanceOf(OptimisticLockingFailureException.class);

        verifyNoInteractions(keycloak);
        verify(tasks, never()).complete(any(), anyMap());
    }
}
