package com.delivery.onboarding.service;

import java.time.Duration;
import java.time.Instant;
import java.util.Optional;

import org.camunda.bpm.engine.RuntimeService;
import org.camunda.bpm.engine.TaskService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.orm.ObjectOptimisticLockingFailureException;

import com.delivery.onboarding.client.KeycloakAdminClient;
import com.delivery.onboarding.domain.AutoApprovalAuditRepository;
import com.delivery.onboarding.domain.AutoApprovalDecisionRepository;
import com.delivery.onboarding.domain.ContactVerification.Channel;
import com.delivery.onboarding.domain.OnboardingApplication;
import com.delivery.onboarding.domain.OnboardingApplication.Kind;
import com.delivery.onboarding.domain.OnboardingApplicationRepository;
import com.delivery.onboarding.domain.PartnerEditEntryRepository;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatExceptionOfType;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

/**
 * The passcode step asks for a secret only the applicant holds — and the reference is not one.
 *
 * <p>{@code POST /applications/{reference}/account} trusted the reference: "160 bits, handed to one
 * person". Back office reads it on every application, a delivery company on every rider applying to it
 * (its portal prints it), and it rides in the path, which the gateway's access log keeps. So a company
 * could choose the passcode on its applicant's unfinished sign-in — or on the leftover account a failed
 * attempt left stamped for the application — then sign in as the rider and approve itself a rider.
 *
 * <p>Now the call shows the account-setup ticket the submission answered with, or a code answered on
 * the address in the last half hour, and either is judged before anything else: before the
 * application's state is answered, and before Keycloak is asked anything.
 */
@DisplayName("the passcode step's secret")
class SignInProofTest {

    private static final String REFERENCE = "ref-sam";
    private static final String PASSCODE = "482910";
    private static final String SAM_EMAIL = "sam@example.test";

    private OnboardingApplicationRepository applications;
    private ApplicationIntake intake;
    private VerificationService verifications;
    private KeycloakAdminClient keycloak;

    private OnboardingApplication sam;
    private String ticket;

    @BeforeEach
    void setUp() {
        applications = mock(OnboardingApplicationRepository.class);
        intake = mock(ApplicationIntake.class);
        verifications = mock(VerificationService.class);
        keycloak = mock(KeycloakAdminClient.class);

        sam = rider();
        ticket = sam.issueAccountTicket(Instant.now());
        when(applications.findByReference(REFERENCE)).thenReturn(Optional.of(sam));
        when(applications.findByApplicantUserRef(anyString())).thenReturn(Optional.empty());
        when(applications.findFirstByProvisionedUserRefOrderByCreatedAtDesc(anyString()))
                .thenReturn(Optional.empty());
        when(keycloak.createApplicant(SAM_EMAIL, "Sam", "Salem", "DELIVERY", PASSCODE, sam.getId()))
                .thenReturn("kc-sam");
        // The intake as it behaves: the sign-in recorded, and the ticket spent with it.
        when(intake.attachApplicantAccount(eq(sam.getId()), anyString(), any())).thenAnswer(call -> {
            sam.applicantAccountCreated(call.getArgument(1));
            sam.spendAccountTicket(Instant.now());
            return sam;
        });
    }

    private static OnboardingApplication rider() {
        return new OnboardingApplication(Kind.RIDER, "Sam Salem", "Sam Salem", SAM_EMAIL,
                Instant.now(), null, null, null, null, null);
    }

    private OnboardingService onboarding() {
        return new OnboardingService(applications, intake, verifications,
                mock(ServiceProviderAnswers.class), mock(RuntimeService.class), mock(TaskService.class),
                keycloak, mock(ApplicantDocumentService.class),
                new AutoApprovalPolicy(false, false, false, mock(AutoApprovalDecisionRepository.class),
                        mock(AutoApprovalAuditRepository.class)),
                new TransactionsWithoutADatabase(), mock(PartnerEditEntryRepository.class));
    }

    private static String codeOf(Runnable call) {
        try {
            call.run();
        } catch (AccountApplicationService.AccountRuleException e) {
            return e.code();
        }
        throw new AssertionError("expected a refusal carrying a code");
    }

    /** Nothing asked of Keycloak and nothing recorded: no account made, found, or given a passcode. */
    private void nothingTouched() {
        verifyNoInteractions(keycloak);
        verify(intake, never()).attachApplicantAccount(any(), any(), any());
    }

    @Nested
    @DisplayName("refused before Keycloak is asked anything")
    class Refused {

        @Test
        @DisplayName("no secret at all — what an installed app sends — is sign-in-proof-missing, "
                + "in words that say to update the app")
        void no_secret() {
            AccountApplicationService.AccountRuleException refusal = catchRefusal(
                    () -> onboarding().createApplicantAccount(REFERENCE, PASSCODE, null, null));

            assertThat(refusal.code()).isEqualTo("sign-in-proof-missing");
            // An installed app has no words for this code and shows the sentence as it comes.
            assertThat(refusal.getMessage()).contains("update the app");
            nothingTouched();
        }

        @Test
        @DisplayName("a wrong ticket is sign-in-proof-rejected")
        void a_wrong_ticket() {
            assertThat(codeOf(() -> onboarding().createApplicantAccount(
                    REFERENCE, PASSCODE, "not-the-ticket", null)))
                    .isEqualTo("sign-in-proof-rejected");
            nothingTouched();
        }

        @Test
        @DisplayName("another application's valid ticket is wrong for this one")
        void another_applications_ticket() {
            String theirs = rider().issueAccountTicket(Instant.now());

            assertThat(codeOf(() -> onboarding().createApplicantAccount(
                    REFERENCE, PASSCODE, theirs, null)))
                    .isEqualTo("sign-in-proof-rejected");
            nothingTouched();
        }

        @Test
        @DisplayName("an expired ticket is sign-in-proof-rejected, and the app asks for a code")
        void an_expired_ticket() {
            OnboardingApplication late = rider();
            String old = late.issueAccountTicket(Instant.now()
                    .minus(OnboardingApplication.ACCOUNT_TICKET_LIFETIME).minusSeconds(1));
            when(applications.findByReference("ref-late")).thenReturn(Optional.of(late));

            assertThat(codeOf(() -> onboarding().createApplicantAccount(
                    "ref-late", PASSCODE, old, null)))
                    .isEqualTo("sign-in-proof-rejected");
            nothingTouched();
        }

        @Test
        @DisplayName("an email proof that is stale, spent, or for another address is sign-in-proof-rejected")
        void a_proof_that_is_not_fresh() {
            // The service answers false for all three; the conditions are VerificationServiceTest's.
            when(verifications.isFreshlyVerified(any(), any(), any(), any())).thenReturn(false);

            assertThat(codeOf(() -> onboarding().createApplicantAccount(
                    REFERENCE, PASSCODE, null, "proof-old")))
                    .isEqualTo("sign-in-proof-rejected");
            nothingTouched();
        }

        @Test
        @DisplayName("the secret is judged first: without it, even a decided application says nothing about itself")
        void judged_before_the_application_is() {
            sam.reject("reviewer-1", "Not taking riders there");

            assertThat(codeOf(() -> onboarding().createApplicantAccount(REFERENCE, PASSCODE, null, null)))
                    .isEqualTo("sign-in-proof-missing");
            nothingTouched();
        }
    }

    @Nested
    @DisplayName("accepted")
    class Accepted {

        @Test
        @DisplayName("a valid ticket sets up the sign-in, and the record spends it")
        void a_valid_ticket() {
            onboarding().createApplicantAccount(REFERENCE, PASSCODE, ticket, null);

            verify(keycloak).createApplicant(SAM_EMAIL, "Sam", "Salem", "DELIVERY", PASSCODE, sam.getId());
            verify(intake).attachApplicantAccount(sam.getId(), "kc-sam",
                    OnboardingService.SignInProof.TICKET);
            assertThat(sam.getApplicantUserRef()).isEqualTo("kc-sam");
            assertThat(sam.checkAccountTicket(ticket, Instant.now()))
                    .isEqualTo(OnboardingApplication.TicketCheck.SPENT);
        }

        @Test
        @DisplayName("once the ticket is gone, a fresh code answered on the application's address does instead, "
                + "and is spent with the sign-in")
        void a_fresh_email_proof() {
            when(verifications.isFreshlyVerified("proof-now", Channel.EMAIL, SAM_EMAIL,
                    Duration.ofMinutes(30))).thenReturn(true);

            onboarding().createApplicantAccount(REFERENCE, PASSCODE, null, "proof-now");

            verify(keycloak).createApplicant(SAM_EMAIL, "Sam", "Salem", "DELIVERY", PASSCODE, sam.getId());
            verify(intake).attachApplicantAccount(sam.getId(), "kc-sam",
                    new OnboardingService.SignInProof("proof-now"));
        }

        @Test
        @DisplayName("an expired ticket beside a fresh proof: the proof carries it")
        void a_late_ticket_and_a_fresh_proof() {
            OnboardingApplication late = rider();
            String old = late.issueAccountTicket(Instant.now().minus(Duration.ofHours(2)));
            when(applications.findByReference("ref-late")).thenReturn(Optional.of(late));
            when(keycloak.createApplicant(SAM_EMAIL, "Sam", "Salem", "DELIVERY", PASSCODE, late.getId()))
                    .thenReturn("kc-late");
            when(intake.attachApplicantAccount(eq(late.getId()), anyString(), any())).thenReturn(late);
            when(verifications.isFreshlyVerified("proof-now", Channel.EMAIL, SAM_EMAIL,
                    Duration.ofMinutes(30))).thenReturn(true);

            assertThatCode(() -> onboarding().createApplicantAccount("ref-late", PASSCODE, old, "proof-now"))
                    .doesNotThrowAnyException();
            verify(intake).attachApplicantAccount(late.getId(), "kc-late",
                    new OnboardingService.SignInProof("proof-now"));
        }
    }

    @Nested
    @DisplayName("a ticket used twice")
    class Reused {

        @Test
        @DisplayName("once its sign-in is recorded, the ticket sets no passcode again — its holder is told sign-in-exists")
        void a_spent_ticket_sets_nothing() {
            OnboardingService onboarding = onboarding();
            onboarding.createApplicantAccount(REFERENCE, PASSCODE, ticket, null);

            assertThat(codeOf(() -> onboarding.createApplicantAccount(REFERENCE, "000000", ticket, null)))
                    .isEqualTo("sign-in-exists");
            // One account, made once, and nobody's passcode changed by the second call.
            verify(keycloak, times(1)).createApplicant(any(), any(), any(), any(), any(), any());
            verify(keycloak, never()).resetPassword(any(), any());
            verify(intake, times(1)).attachApplicantAccount(any(), any(), any());
        }

        @Test
        @DisplayName("a double tap whose second call overlapped the first is sign-in-exists, not account-exists")
        void a_double_tap_is_sent_to_sign_in() {
            // The second call read the application before the first recorded its sign-in, so its
            // ticket was still good; by the time Keycloak answered 409, the account it met was the
            // one the first call made and recorded — against this very application.
            doThrow(new KeycloakAdminClient.AccountExistsException("taken"))
                    .when(keycloak).createApplicant(SAM_EMAIL, "Sam", "Salem", "DELIVERY", PASSCODE, sam.getId());
            when(keycloak.findUserIdByEmail(SAM_EMAIL)).thenReturn(Optional.of("kc-sam"));
            when(applications.findByApplicantUserRef("kc-sam")).thenReturn(Optional.of(sam));

            assertThat(codeOf(() -> onboarding().createApplicantAccount(REFERENCE, PASSCODE, ticket, null)))
                    .isEqualTo("sign-in-exists");
            verify(keycloak, never()).resetPassword(any(), any());
            verify(keycloak, never()).grantRealmRole(any(), any());
            verify(intake, never()).attachApplicantAccount(any(), any(), any());
        }
    }

    @Nested
    @DisplayName("a rejection landing while the passcode is being set")
    class RejectedMeanwhile {

        /** The row as another transaction would read it now: rejected by a reviewer. */
        private OnboardingApplication rejectedCopy() {
            OnboardingApplication copy = rider();
            copy.reject("reviewer-1", "Not taking riders there");
            return copy;
        }

        @Test
        @DisplayName("committed before the attach read the row: application-decided, and the live role made with the account goes")
        void decided_before_the_attach() {
            doThrow(OnboardingService.applicationDecided())
                    .when(intake).attachApplicantAccount(eq(sam.getId()), eq("kc-sam"), any());

            assertThat(codeOf(() -> onboarding().createApplicantAccount(REFERENCE, PASSCODE, ticket, null)))
                    .isEqualTo("application-decided");
            verify(keycloak).revokeRealmRole("kc-sam", "DELIVERY");
            verify(keycloak, never()).revokeRealmRole("kc-sam", "APPLICANT");
        }

        @Test
        @DisplayName("committed between the attach's read and its write: the version refuses the write, "
                + "and it is said as application-decided")
        void decided_during_the_attach() {
            doThrow(new ObjectOptimisticLockingFailureException(OnboardingApplication.class, sam.getId()))
                    .when(intake).attachApplicantAccount(eq(sam.getId()), eq("kc-sam"), any());
            when(applications.findById(sam.getId())).thenReturn(Optional.of(rejectedCopy()));

            assertThat(codeOf(() -> onboarding().createApplicantAccount(REFERENCE, PASSCODE, ticket, null)))
                    .isEqualTo("application-decided");
            verify(keycloak).revokeRealmRole("kc-sam", "DELIVERY");
            assertThat(sam.getApplicantUserRef()).isNull();
        }

        @Test
        @DisplayName("a conflict that was the other tap recording this same account is success, and the role stays")
        void the_other_tap_won_the_write() {
            OnboardingApplication recordedByTheOtherTap = rider();
            recordedByTheOtherTap.applicantAccountCreated("kc-sam");
            doThrow(new ObjectOptimisticLockingFailureException(OnboardingApplication.class, sam.getId()))
                    .when(intake).attachApplicantAccount(eq(sam.getId()), eq("kc-sam"), any());
            when(applications.findById(sam.getId())).thenReturn(Optional.of(recordedByTheOtherTap));

            assertThatCode(() -> onboarding().createApplicantAccount(REFERENCE, PASSCODE, ticket, null))
                    .doesNotThrowAnyException();
            verify(keycloak, never()).revokeRealmRole(any(), any());
        }

        @Test
        @DisplayName("any other conflict is worth another try: sign-in-unavailable, the role taken back until then")
        void another_conflict_is_retryable() {
            doThrow(new ObjectOptimisticLockingFailureException(OnboardingApplication.class, sam.getId()))
                    .when(intake).attachApplicantAccount(eq(sam.getId()), eq("kc-sam"), any());
            when(applications.findById(sam.getId())).thenReturn(Optional.of(rider()));

            assertThatExceptionOfType(OnboardingService.SignInUnavailableException.class)
                    .isThrownBy(() -> onboarding().createApplicantAccount(REFERENCE, PASSCODE, ticket, null));
            verify(keycloak).revokeRealmRole("kc-sam", "DELIVERY");
        }

        @Test
        @DisplayName("and the retry after it, ticket still good, is refused before Keycloak: the leftover is never taken up")
        void the_retry_after_the_decision() {
            sam.reject("reviewer-1", "Not taking riders there");

            assertThat(codeOf(() -> onboarding().createApplicantAccount(REFERENCE, PASSCODE, ticket, null)))
                    .isEqualTo("application-decided");
            nothingTouched();
        }
    }

    private static AccountApplicationService.AccountRuleException catchRefusal(Runnable call) {
        try {
            call.run();
        } catch (AccountApplicationService.AccountRuleException e) {
            return e;
        }
        throw new AssertionError("expected a refusal carrying a code");
    }
}
