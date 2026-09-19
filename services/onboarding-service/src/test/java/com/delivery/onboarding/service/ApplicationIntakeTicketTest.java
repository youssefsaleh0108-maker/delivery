package com.delivery.onboarding.service;

import java.lang.reflect.Field;
import java.time.Instant;
import java.util.Arrays;
import java.util.Map;
import java.util.Optional;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import com.delivery.onboarding.domain.ContactVerification.Channel;
import com.delivery.onboarding.domain.OnboardingApplication;
import com.delivery.onboarding.domain.OnboardingApplication.Kind;
import com.delivery.onboarding.domain.OnboardingApplication.TicketCheck;
import com.delivery.onboarding.domain.OnboardingApplicationRepository;

import jakarta.persistence.Version;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatIllegalStateException;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * The intake's half of the passcode step's secret: issuing the account-setup ticket with the
 * application, and spending it — or the email proof that stood in for it — with the sign-in.
 *
 * <p>And the attach judging the row again, on the version it read: a sign-in is never recorded on an
 * application a reviewer decided while the passcode was being set.
 */
@DisplayName("the intake, the account-setup ticket and the attach")
class ApplicationIntakeTicketTest {

    private static final String SAM_EMAIL = "sam@example.test";

    private OnboardingApplicationRepository applications;
    private VerificationService verifications;
    private ApplicationIntake intake;

    private OnboardingApplication sam;
    private String ticket;

    @BeforeEach
    void setUp() {
        applications = mock(OnboardingApplicationRepository.class);
        verifications = mock(VerificationService.class);
        intake = new ApplicationIntake(applications, verifications);

        sam = new OnboardingApplication(Kind.RIDER, "Sam Salem", "Sam Salem", SAM_EMAIL,
                Instant.now(), null, null, null, null, null);
        ticket = sam.issueAccountTicket(Instant.now());
        when(applications.findById(sam.getId())).thenReturn(Optional.of(sam));
        when(applications.saveAndFlush(any())).thenAnswer(call -> call.getArgument(0));
    }

    private static String codeOf(Runnable call) {
        try {
            call.run();
        } catch (AccountApplicationService.AccountRuleException e) {
            return e.code();
        }
        throw new AssertionError("expected a refusal carrying a code");
    }

    @Nested
    @DisplayName("issuing the ticket")
    class Issuing {

        @BeforeEach
        void theProofSpends() {
            when(verifications.consume(anyString(), eq(Channel.EMAIL), anyString()))
                    .thenReturn(Instant.now());
            when(verifications.normalise(eq(Channel.EMAIL), anyString()))
                    .thenAnswer(call -> call.getArgument(1));
        }

        private ApplicationIntake.Recorded submit() {
            ServiceProviderAnswers answers = new ServiceProviderAnswers(
                    mock(com.delivery.onboarding.client.PlatformClient.class), mock(HiringCompanies.class));
            return intake.record(Kind.RIDER, "Sam Salem", "Sam Salem", SAM_EMAIL, "email-proof",
                    null, null, null,
                    answers.checked(Kind.RIDER, Map.of("vehicleType", "MOTORCYCLE"), null), null);
        }

        @Test
        @DisplayName("256 random bits go back to the submitter; the record keeps only their hash")
        void only_the_hash_is_kept() throws IllegalAccessException {
            ApplicationIntake.Recorded recorded = submit();

            // 32 bytes, base64url without padding.
            assertThat(recorded.accountTicket()).matches("[A-Za-z0-9_-]{43}");
            assertThat(recorded.application().checkAccountTicket(recorded.accountTicket(), Instant.now()))
                    .isEqualTo(TicketCheck.VALID);
            for (Field field : OnboardingApplication.class.getDeclaredFields()) {
                field.setAccessible(true);
                assertThat(String.valueOf(field.get(recorded.application())))
                        .as(field.getName())
                        .doesNotContain(recorded.accountTicket());
            }
            // Nor does printing what the intake answered print the ticket.
            assertThat(recorded.toString()).doesNotContain(recorded.accountTicket());
        }

        @Test
        @DisplayName("each application gets its own, and it lasts half an hour")
        void its_own_and_short_lived() {
            ApplicationIntake.Recorded first = submit();
            ApplicationIntake.Recorded second = submit();

            assertThat(first.accountTicket()).isNotEqualTo(second.accountTicket());
            assertThat(second.application().checkAccountTicket(first.accountTicket(), Instant.now()))
                    .isEqualTo(TicketCheck.WRONG);
            assertThat(first.application().checkAccountTicket(first.accountTicket(),
                    Instant.now().plus(OnboardingApplication.ACCOUNT_TICKET_LIFETIME).plusSeconds(1)))
                    .isEqualTo(TicketCheck.EXPIRED);
        }

        @Test
        @DisplayName("an application is issued one ticket, ever")
        void issued_once() {
            assertThatIllegalStateException().isThrownBy(() -> sam.issueAccountTicket(Instant.now()));
            assertThat(sam.checkAccountTicket(null, Instant.now())).isEqualTo(TicketCheck.WRONG);
            assertThat(sam.checkAccountTicket("  ", Instant.now())).isEqualTo(TicketCheck.WRONG);
        }
    }

    @Nested
    @DisplayName("recording the sign-in")
    class Attaching {

        @Test
        @DisplayName("records the account and spends the ticket, in the same write")
        void spends_the_ticket() {
            intake.attachApplicantAccount(sam.getId(), "kc-sam", OnboardingService.SignInProof.TICKET);

            assertThat(sam.getApplicantUserRef()).isEqualTo("kc-sam");
            assertThat(sam.checkAccountTicket(ticket, Instant.now())).isEqualTo(TicketCheck.SPENT);
            verify(applications).saveAndFlush(sam);
            verify(verifications, never()).consume(any(), any(), any());
        }

        @Test
        @DisplayName("spends an email proof that stood in for the ticket, in the same write")
        void spends_the_email_proof() {
            intake.attachApplicantAccount(sam.getId(), "kc-sam",
                    new OnboardingService.SignInProof("proof-now"));

            verify(verifications).consume("proof-now", Channel.EMAIL, SAM_EMAIL);
            assertThat(sam.getApplicantUserRef()).isEqualTo("kc-sam");
            // Its sign-in is made, so its ticket has nothing left to start either.
            assertThat(sam.checkAccountTicket(ticket, Instant.now())).isEqualTo(TicketCheck.SPENT);
        }

        @Test
        @DisplayName("a proof another request spent meanwhile is sign-in-proof-rejected, and nothing is written")
        void a_proof_spent_meanwhile() {
            when(verifications.consume("proof-now", Channel.EMAIL, SAM_EMAIL))
                    .thenThrow(new VerificationService.VerificationException(
                            "That verification is no longer valid. Please verify again."));

            assertThat(codeOf(() -> intake.attachApplicantAccount(sam.getId(), "kc-sam",
                    new OnboardingService.SignInProof("proof-now"))))
                    .isEqualTo("sign-in-proof-rejected");
            verify(applications, never()).saveAndFlush(any());
        }

        @Test
        @DisplayName("an application decided since the caller read it gets no sign-in: application-decided, nothing written")
        void a_decided_application_is_refused() {
            sam.reject("reviewer-1", "Not taking riders there");

            assertThat(codeOf(() -> intake.attachApplicantAccount(sam.getId(), "kc-sam",
                    OnboardingService.SignInProof.TICKET)))
                    .isEqualTo("application-decided");
            assertThat(sam.getApplicantUserRef()).isNull();
            assertThat(sam.getStatus()).isEqualTo(OnboardingApplication.Status.REJECTED);
            verify(applications, never()).saveAndFlush(any());
        }

        @Test
        @DisplayName("the same account again is not a second sign-in, even once auto-approval decided it — nothing written")
        void the_same_account_again() {
            sam.applicantAccountCreated("kc-sam");
            sam.approve(AutoApprovalPolicy.AUTOMATIC_REVIEWER);

            assertThat(intake.attachApplicantAccount(sam.getId(), "kc-sam",
                    OnboardingService.SignInProof.TICKET)).isSameAs(sam);
            verify(applications, never()).saveAndFlush(any());
        }

        @Test
        @DisplayName("another account on the row is sign-in-exists")
        void another_account() {
            sam.applicantAccountCreated("kc-first");

            assertThat(codeOf(() -> intake.attachApplicantAccount(sam.getId(), "kc-second",
                    OnboardingService.SignInProof.TICKET)))
                    .isEqualTo("sign-in-exists");
        }

        @Test
        @DisplayName("by shape: the row carries a version, so a decision and a sign-in cannot both write a stale copy")
        void the_row_is_versioned() {
            assertThat(Arrays.stream(OnboardingApplication.class.getDeclaredFields())
                    .filter(field -> field.isAnnotationPresent(Version.class))
                    .map(Field::getName))
                    .containsExactly("version");
        }
    }
}
