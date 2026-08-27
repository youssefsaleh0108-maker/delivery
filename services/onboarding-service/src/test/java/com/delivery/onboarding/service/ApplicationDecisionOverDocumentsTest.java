package com.delivery.onboarding.service;

import java.time.Instant;
import java.util.Optional;
import java.util.UUID;

import org.camunda.bpm.engine.RuntimeService;
import org.camunda.bpm.engine.TaskService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import com.delivery.onboarding.client.KeycloakAdminClient;
import com.delivery.onboarding.domain.OnboardingApplication;
import com.delivery.onboarding.domain.OnboardingApplication.Kind;
import com.delivery.onboarding.domain.OnboardingApplicationRepository;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatExceptionOfType;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * An application's decision and its documents are separate, and going past one is recorded.
 *
 * <p>The behaviour being pinned is a compromise and worth naming as one. Blocking the approval
 * outright would leave a reviewer holding a commercial registration on paper with only one way to
 * record the decision they have actually made — approve the document they have not verified — and a
 * falsified document verdict is a worse record than an honest approval with a note on it. Allowing
 * it silently would mean nobody could ever tell, afterwards, that anything had been outstanding.
 * So: refused until the caller says they mean it, and then written down.
 */
class ApplicationDecisionOverDocumentsTest {

    private OnboardingApplicationRepository applications;
    private ApplicantDocumentService documents;
    private OnboardingService onboarding;

    private OnboardingApplication application;

    @BeforeEach
    void setUp() {
        applications = mock(OnboardingApplicationRepository.class);
        documents = mock(ApplicantDocumentService.class);
        onboarding = new OnboardingService(applications, mock(ApplicationIntake.class),
                mock(RuntimeService.class), mock(TaskService.class),
                mock(KeycloakAdminClient.class), documents);

        application = new OnboardingApplication(Kind.RIDER, "Sam Salem", "Sam Salem",
                "sam@example.test", Instant.now(), null, null, null, null, null);
        when(applications.findById(application.getId())).thenReturn(Optional.of(application));
    }

    @Test
    @DisplayName("approving goes straight through when every document was approved")
    void goes_straight_through_when_the_documents_are_clean() {
        when(documents.outstandingSummary(application.getId())).thenReturn(null);

        OnboardingApplication decided = onboarding.approve(application.getId(), "reviewer-1");

        assertThat(decided.getStatus()).isEqualTo(OnboardingApplication.Status.APPROVED);
        assertThat(decided.getDocumentIssueOverride()).isNull();
    }

    @Test
    @DisplayName("approving is refused, naming the documents, when a reviewer has not said they mean it")
    void is_refused_until_the_reviewer_says_they_mean_it() {
        when(documents.outstandingSummary(application.getId()))
                .thenReturn("DRIVING_LICENCE=REJECTED, VEHICLE_REGISTRATION=PENDING");

        assertThatExceptionOfType(OnboardingService.DocumentIssuesOutstandingException.class)
                .isThrownBy(() -> onboarding.approve(application.getId(), "reviewer-1"))
                .satisfies(e -> assertThat(e.getOutstanding())
                        .isEqualTo("DRIVING_LICENCE=REJECTED, VEHICLE_REGISTRATION=PENDING"))
                .withMessageContaining("DRIVING_LICENCE=REJECTED");

        // Nothing was decided, so a reviewer who dismisses the prompt has changed nothing.
        assertThat(application.getStatus()).isEqualTo(OnboardingApplication.Status.SUBMITTED);
        verify(applications, org.mockito.Mockito.never()).save(any());
    }

    @Test
    @DisplayName("approving anyway is allowed, and writes down what was outstanding at that moment")
    void is_allowed_when_acknowledged_and_records_what_was_overridden() {
        when(documents.outstandingSummary(application.getId()))
                .thenReturn("NATIONAL_ID=REJECTED");

        OnboardingApplication decided = onboarding.approve(application.getId(), "reviewer-1", true);

        assertThat(decided.getStatus()).isEqualTo(OnboardingApplication.Status.APPROVED);
        assertThat(decided.getDecidedBy()).isEqualTo("reviewer-1");
        // The part that makes this reviewable a year later: the record says the approval went past
        // a refused national id, not merely that somebody approved.
        assertThat(decided.getDocumentIssueOverride()).isEqualTo("NATIONAL_ID=REJECTED");
    }

    @Test
    @DisplayName("acknowledging changes nothing when there was nothing outstanding to acknowledge")
    void acknowledging_nothing_records_nothing() {
        when(documents.outstandingSummary(application.getId())).thenReturn(null);

        OnboardingApplication decided = onboarding.approve(application.getId(), "reviewer-1", true);

        assertThat(decided.getDocumentIssueOverride()).isNull();
    }

    @Test
    @DisplayName("rejecting an application never asks about its documents at all")
    void rejecting_does_not_consult_the_documents() {
        onboarding.reject(application.getId(), "reviewer-1", "Not operating in our regions yet");

        assertThat(application.getStatus()).isEqualTo(OnboardingApplication.Status.REJECTED);
        // Refusing somebody whose licence is still pending is not an override of anything — the
        // outstanding document is simply irrelevant to a "no".
        verify(documents, org.mockito.Mockito.never()).outstandingSummary(any(UUID.class));
    }
}
