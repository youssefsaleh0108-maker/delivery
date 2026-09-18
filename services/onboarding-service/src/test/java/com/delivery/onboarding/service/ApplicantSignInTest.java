package com.delivery.onboarding.service;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import java.util.stream.Stream;

import org.camunda.bpm.engine.RuntimeService;
import org.camunda.bpm.engine.TaskService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.Arguments;
import org.junit.jupiter.params.provider.MethodSource;
import org.mockito.InOrder;
import org.springframework.dao.DataAccessResourceFailureException;
import org.springframework.http.HttpStatus;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.ResourceAccessException;

import com.delivery.onboarding.client.KeycloakAdminClient;
import com.delivery.onboarding.domain.AutoApprovalAuditRepository;
import com.delivery.onboarding.domain.AutoApprovalDecisionRepository;
import com.delivery.onboarding.domain.OnboardingApplication;
import com.delivery.onboarding.domain.OnboardingApplication.Kind;
import com.delivery.onboarding.domain.OnboardingApplication.Status;
import com.delivery.onboarding.domain.OnboardingApplicationRepository;

import static com.delivery.onboarding.service.TransactionsWithoutADatabase.where;
import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatExceptionOfType;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyMap;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.RETURNS_DEEP_STUBS;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.doReturn;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.inOrder;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

/**
 * The open form's last step: choosing a passcode, which makes the applicant's sign-in — and, when the
 * policy says so, approves them.
 *
 * <p>What went wrong is worth naming, because each half is pinned here. The sign-in and the automatic
 * approval shared one transaction, so an approval step that failed (a Keycloak role change, or
 * order-manager refusing to attach a rider) marked it rollback-only; the failure was caught and
 * logged, and the commit then threw. The applicant saw "We could not set up your sign-in", the record
 * lost the account, Keycloak kept it — and every retry met Keycloak's 409, which nothing answered, so
 * it was a 500 too. The app, with no words for a bare 500, said "That did not go through".
 *
 * <p>The transactions are real, over {@link TransactionsWithoutADatabase}, so where each call ran and
 * which transaction rolled back is observed rather than assumed. The approval itself is the real
 * {@code approve}; its failing step is the process's, thrown from completing the review task.
 */
class ApplicantSignInTest {

    private static final String REFERENCE = "ref-sam";
    private static final String PASSCODE = "482910";
    private static final String SAM_EMAIL = "sam@example.test";

    private OnboardingApplicationRepository applications;
    private ApplicationIntake intake;
    private TaskService tasks;
    private KeycloakAdminClient keycloak;
    private AutoApprovalDecisionRepository decisions;
    private TransactionsWithoutADatabase transactions;

    /** What happened, in order, and whether a transaction was open when it did. */
    private final List<String> events = new ArrayList<>();

    /** Sam's rider application as it was recorded: submitted, with no sign-in until one is attached. */
    private OnboardingApplication sam;

    /** How the database answers a read by id: undecided unless a test says a reviewer decided it. */
    private Status stored = Status.SUBMITTED;

    @BeforeEach
    void setUp() {
        applications = mock(OnboardingApplicationRepository.class);
        intake = mock(ApplicationIntake.class);
        tasks = mock(TaskService.class, RETURNS_DEEP_STUBS);
        keycloak = mock(KeycloakAdminClient.class);
        decisions = mock(AutoApprovalDecisionRepository.class);
        transactions = new TransactionsWithoutADatabase();

        sam = rider();
        when(applications.findByReference(REFERENCE)).thenReturn(Optional.of(sam));
        // Every read by id is a fresh copy of the row, as another transaction reads it: what the
        // approval changes in its own copy is only ever the database's if its transaction commits.
        when(applications.findById(sam.getId())).thenAnswer(call -> Optional.of(storedCopy()));
        when(applications.save(any())).thenAnswer(call -> {
            events.add(where("save " + call.<OnboardingApplication>getArgument(0).getStatus()));
            return call.getArgument(0);
        });
        when(applications.findByApplicantUserRef(anyString())).thenReturn(Optional.empty());
        when(applications.findFirstByProvisionedUserRefOrderByCreatedAtDesc(anyString()))
                .thenReturn(Optional.empty());

        when(keycloak.createApplicant(SAM_EMAIL, "Sam", "Salem", "DELIVERY", PASSCODE))
                .thenAnswer(call -> {
                    events.add(where("create the sign-in"));
                    return "kc-sam";
                });
        doAnswer(call -> events.add(where("grant " + call.getArgument(1))))
                .when(keycloak).grantRealmRole(anyString(), anyString());
        when(intake.attachApplicantAccount(eq(sam.getId()), anyString()))
                .thenAnswer(call -> recordSignIn(call.getArgument(1)));
    }

    private static OnboardingApplication rider() {
        return new OnboardingApplication(Kind.RIDER, "Sam Salem", "Sam Salem", SAM_EMAIL,
                Instant.now(), null, null, null, null, null);
    }

    private OnboardingApplication storedCopy() {
        OnboardingApplication copy = rider();
        copy.startedAs("process-sam");
        if (stored == Status.APPROVED) {
            copy.approve("reviewer-1");
        }
        return copy;
    }

    /** What the intake does, committed in its own transaction: the sign-in is on the record. */
    private OnboardingApplication recordSignIn(String userRef) {
        events.add(where("record the sign-in"));
        sam.applicantAccountCreated(userRef);
        return sam;
    }

    private OnboardingService onboarding(boolean riderAutomatic) {
        return new OnboardingService(applications, intake, mock(VerificationService.class),
                mock(ServiceProviderAnswers.class), mock(RuntimeService.class), tasks, keycloak,
                mock(ApplicantDocumentService.class),
                new AutoApprovalPolicy(riderAutomatic, false, false, decisions,
                        mock(AutoApprovalAuditRepository.class)),
                transactions);
    }

    /** The process failing where the brief found it failing: inside the review's completion. */
    private void anApprovalStepFails() {
        doAnswer(call -> {
            events.add(where("complete the review"));
            throw new IllegalStateException("order-manager refused to attach the rider");
        }).when(tasks).complete(any(), anyMap());
    }

    /** The code a refusal carries, which is what the app translates. Fails when there is none. */
    private static String codeOf(Runnable call) {
        try {
            call.run();
        } catch (AccountApplicationService.AccountRuleException e) {
            return e.code();
        }
        throw new AssertionError("expected a refusal carrying a code");
    }

    @Nested
    @DisplayName("with auto-approval on")
    class AutoApproval {

        @Test
        @DisplayName("an approval step that fails leaves the sign-in made, the application waiting, "
                + "and the applicant told it worked")
        void a_failing_approval_step_does_not_take_the_sign_in_with_it() {
            anApprovalStepFails();

            assertThatCode(() -> onboarding(true).createApplicantAccount(REFERENCE, PASSCODE))
                    .doesNotThrowAnyException();

            // The sign-in is made and recorded before any transaction exists; the approval runs in a
            // transaction of its own, which is the only one, and it rolled back: the APPROVED it saved
            // never reached the database. Then APPLICANT goes back on — the process had taken it.
            assertThat(events).containsExactly(
                    "create the sign-in outside a transaction",
                    "record the sign-in outside a transaction",
                    "save APPROVED inside a transaction",
                    "complete the review inside a transaction",
                    "grant APPLICANT outside a transaction");
            assertThat(transactions.begun()).isEqualTo(1);
            assertThat(transactions.rolledBack()).isEqualTo(1);
            assertThat(transactions.committed()).isZero();

            assertThat(sam.getApplicantUserRef()).isEqualTo("kc-sam");
            assertThat(sam.getStatus()).isEqualTo(Status.SUBMITTED);
            verify(keycloak).grantRealmRole("kc-sam", "APPLICANT");
        }

        @Test
        @DisplayName("an approval that goes through commits in its own transaction, after the sign-in")
        void a_clean_approval_commits_on_its_own() {
            onboarding(true).createApplicantAccount(REFERENCE, PASSCODE);

            assertThat(events).containsExactly(
                    "create the sign-in outside a transaction",
                    "record the sign-in outside a transaction",
                    "save APPROVED inside a transaction");
            assertThat(transactions.begun()).isEqualTo(1);
            assertThat(transactions.committed()).isEqualTo(1);
            verify(tasks).complete(any(), eq(java.util.Map.of("approved", true)));
            verify(keycloak, never()).grantRealmRole(any(), any());
        }

        @Test
        @DisplayName("never puts APPLICANT back on an application a reviewer decided meanwhile")
        void a_reviewers_decision_is_not_undone() {
            stored = Status.APPROVED;

            assertThatCode(() -> onboarding(true).createApplicantAccount(REFERENCE, PASSCODE))
                    .doesNotThrowAnyException();

            assertThat(transactions.rolledBack()).isEqualTo(1);
            verify(keycloak, never()).grantRealmRole(any(), any());
        }

        @Test
        @DisplayName("asking again after that is refused as before: the sign-in is already recorded")
        void asking_again_does_not_make_a_second_sign_in() {
            anApprovalStepFails();
            OnboardingService onboarding = onboarding(true);
            onboarding.createApplicantAccount(REFERENCE, PASSCODE);

            assertThatExceptionOfType(OnboardingService.ApplicationRuleException.class)
                    .isThrownBy(() -> onboarding.createApplicantAccount(REFERENCE, PASSCODE))
                    .withMessage("That application already has a sign-in");
            verify(keycloak).createApplicant(any(), any(), any(), any(), any());
        }
    }

    @Test
    @DisplayName("with auto-approval off nothing changes: the sign-in is made and the application waits")
    void manual_review_is_untouched() {
        onboarding(false).createApplicantAccount(REFERENCE, PASSCODE);

        assertThat(events).containsExactly(
                "create the sign-in outside a transaction",
                "record the sign-in outside a transaction");
        assertThat(transactions.begun()).isZero();
        verifyNoInteractions(tasks);
        verify(keycloak, never()).grantRealmRole(any(), any());
        assertThat(sam.getApplicantUserRef()).isEqualTo("kc-sam");
        assertThat(sam.getStatus()).isEqualTo(Status.SUBMITTED);
    }

    @Test
    @DisplayName("by shape: the sign-in commits by itself, and the method around it holds no transaction")
    void the_sign_in_commits_before_anything_is_tried_on_top_of_it() throws NoSuchMethodException {
        assertThat(OnboardingService.class.getMethod("createApplicantAccount", String.class, String.class)
                .getAnnotation(Transactional.class)).isNull();
        assertThat(OnboardingService.class.getAnnotation(Transactional.class)).isNull();
        assertThat(ApplicationIntake.class.getMethod("attachApplicantAccount", UUID.class, String.class)
                .getAnnotation(Transactional.class).propagation()).isEqualTo(Propagation.REQUIRES_NEW);
    }

    @Nested
    @DisplayName("when Keycloak already has an account for the address")
    class AccountExists {

        private static final String LEFTOVER = "kc-leftover";

        @BeforeEach
        void anAccountHoldsTheAddress() {
            doThrow(new KeycloakAdminClient.AccountExistsException(
                    "An account already exists for that email address"))
                    .when(keycloak).createApplicant(SAM_EMAIL, "Sam", "Salem", "DELIVERY", PASSCODE);
            when(keycloak.findUserIdByEmail(SAM_EMAIL)).thenReturn(Optional.of(LEFTOVER));
        }

        static Stream<Arguments> whatAnInterruptedSignUpLeaves() {
            return Stream.of(
                    Arguments.of(List.of("default-roles-delivery-platform")),
                    Arguments.of(List.of("default-roles-delivery-platform", "APPLICANT")),
                    Arguments.of(List.of("default-roles-delivery-platform", "APPLICANT", "DELIVERY")),
                    Arguments.of(List.of("APPLICANT", "DELIVERY", "offline_access", "uma_authorization")));
        }

        @ParameterizedTest(name = "holding {0}")
        @MethodSource("whatAnInterruptedSignUpLeaves")
        @DisplayName("the one an earlier attempt of this sign-up left is taken up and recorded")
        void this_applicants_own_leftover_is_taken_up(List<String> roles) {
            when(keycloak.realmRolesOf(LEFTOVER)).thenReturn(roles);

            onboarding(false).createApplicantAccount(REFERENCE, PASSCODE);

            // APPLICANT before the live role, as at creation; then the passcode they just chose,
            // which is the one they sign in with next.
            InOrder order = inOrder(keycloak);
            order.verify(keycloak).grantRealmRole(LEFTOVER, "APPLICANT");
            order.verify(keycloak).grantRealmRole(LEFTOVER, "DELIVERY");
            order.verify(keycloak).resetPassword(LEFTOVER, PASSCODE);
            verify(intake).attachApplicantAccount(sam.getId(), LEFTOVER);
            assertThat(sam.getApplicantUserRef()).isEqualTo(LEFTOVER);
        }

        @Test
        @DisplayName("a retry after a failure part way succeeds, on the account the failed attempt made")
        void a_retry_after_a_failure_part_way_succeeds() {
            // First attempt: Keycloak made the account, the record did not save.
            doReturn("kc-sam")
                    .doThrow(new KeycloakAdminClient.AccountExistsException("taken"))
                    .when(keycloak).createApplicant(SAM_EMAIL, "Sam", "Salem", "DELIVERY", PASSCODE);
            doThrow(new DataAccessResourceFailureException("the pool is exhausted"))
                    .doAnswer(call -> recordSignIn(call.getArgument(1)))
                    .when(intake).attachApplicantAccount(eq(sam.getId()), anyString());
            when(keycloak.findUserIdByEmail(SAM_EMAIL)).thenReturn(Optional.of("kc-sam"));
            when(keycloak.realmRolesOf("kc-sam")).thenReturn(
                    List.of("default-roles-delivery-platform", "APPLICANT", "DELIVERY"));
            OnboardingService onboarding = onboarding(false);

            assertThatExceptionOfType(OnboardingService.SignInUnavailableException.class)
                    .isThrownBy(() -> onboarding.createApplicantAccount(REFERENCE, PASSCODE));
            onboarding.createApplicantAccount(REFERENCE, PASSCODE);

            assertThat(sam.getApplicantUserRef()).isEqualTo("kc-sam");
            verify(keycloak).resetPassword("kc-sam", PASSCODE);
        }

        static Stream<Arguments> accountsInUse() {
            return Stream.of(
                    Arguments.of("a customer's", List.of("default-roles-delivery-platform", "CUSTOMER")),
                    Arguments.of("a working rider's", List.of("default-roles-delivery-platform", "DELIVERY")),
                    Arguments.of("an applicant for a shop", List.of("APPLICANT", "MERCHANT")),
                    Arguments.of("staff's", List.of("BACKOFFICE")),
                    Arguments.of("a shop's staff", List.of("MERCHANT_STAFF")));
        }

        @ParameterizedTest(name = "{0}")
        @MethodSource("accountsInUse")
        @DisplayName("anybody else's account is refused with account-exists, and left exactly as it was")
        void an_account_in_use_is_refused(String whose, List<String> roles) {
            when(keycloak.realmRolesOf(LEFTOVER)).thenReturn(roles);

            assertThat(codeOf(() -> onboarding(true).createApplicantAccount(REFERENCE, PASSCODE)))
                    .isEqualTo("account-exists");
            verify(keycloak, never()).grantRealmRole(any(), any());
            verify(keycloak, never()).resetPassword(any(), any());
            verify(intake, never()).attachApplicantAccount(any(), any());
        }

        @Test
        @DisplayName("an account another application records is refused, whatever it holds")
        void an_account_another_application_records_is_refused() {
            when(applications.findByApplicantUserRef(LEFTOVER)).thenReturn(Optional.of(rider()));
            when(keycloak.realmRolesOf(LEFTOVER)).thenReturn(List.of("APPLICANT", "DELIVERY"));

            assertThat(codeOf(() -> onboarding(false).createApplicantAccount(REFERENCE, PASSCODE)))
                    .isEqualTo("account-exists");
            verify(keycloak, never()).resetPassword(any(), any());
        }

        @Test
        @DisplayName("a partner provisioned the old way is refused too")
        void a_provisioned_partner_is_refused() {
            when(applications.findFirstByProvisionedUserRefOrderByCreatedAtDesc(LEFTOVER))
                    .thenReturn(Optional.of(rider()));
            when(keycloak.realmRolesOf(LEFTOVER)).thenReturn(List.of());

            assertThat(codeOf(() -> onboarding(false).createApplicantAccount(REFERENCE, PASSCODE)))
                    .isEqualTo("account-exists");
            verify(keycloak, never()).resetPassword(any(), any());
        }

        @Test
        @DisplayName("a 409 on the username with no account on the address is refused, not guessed at")
        void no_account_on_the_address_is_refused() {
            when(keycloak.findUserIdByEmail(SAM_EMAIL)).thenReturn(Optional.empty());

            assertThat(codeOf(() -> onboarding(false).createApplicantAccount(REFERENCE, PASSCODE)))
                    .isEqualTo("account-exists");
            verify(intake, never()).attachApplicantAccount(any(), any());
        }

        @Test
        @DisplayName("Keycloak failing while the leftover is taken up answers sign-in-unavailable")
        void failing_part_way_through_taking_up_is_retryable() {
            when(keycloak.realmRolesOf(LEFTOVER)).thenReturn(List.of("APPLICANT"));
            doAnswer(call -> {
                throw new KeycloakAdminClient.ProvisioningException("The passcode could not be updated");
            }).when(keycloak).resetPassword(LEFTOVER, PASSCODE);

            assertThatExceptionOfType(OnboardingService.SignInUnavailableException.class)
                    .isThrownBy(() -> onboarding(false).createApplicantAccount(REFERENCE, PASSCODE));
            verify(intake, never()).attachApplicantAccount(any(), any());
        }
    }

    @Nested
    @DisplayName("when the platform fails on its side")
    class PlatformFailures {

        static Stream<Arguments> keycloakFailures() {
            return Stream.of(
                    Arguments.of("no service-account secret", new KeycloakAdminClient.ProvisioningException(
                            "No Keycloak service-account secret is configured")),
                    Arguments.of("the token refused", new HttpClientErrorException(HttpStatus.UNAUTHORIZED)),
                    Arguments.of("Keycloak unreachable", new ResourceAccessException("Connection refused")));
        }

        @ParameterizedTest(name = "{0}")
        @MethodSource("keycloakFailures")
        @DisplayName("Keycloak failing answers sign-in-unavailable, with the cause kept for the log")
        void keycloak_failing_is_a_coded_503(String what, RuntimeException failure) {
            doThrow(failure)
                    .when(keycloak).createApplicant(SAM_EMAIL, "Sam", "Salem", "DELIVERY", PASSCODE);

            assertThatExceptionOfType(OnboardingService.SignInUnavailableException.class)
                    .isThrownBy(() -> onboarding(true).createApplicantAccount(REFERENCE, PASSCODE))
                    .withCause(failure);
            verify(intake, never()).attachApplicantAccount(any(), any());
            assertThat(OnboardingService.SignInUnavailableException.CODE).isEqualTo("sign-in-unavailable");
        }

        @Test
        @DisplayName("the record failing to save answers sign-in-unavailable, and nothing is approved")
        void the_record_failing_is_a_coded_503() {
            doThrow(new DataAccessResourceFailureException("the pool is exhausted"))
                    .when(intake).attachApplicantAccount(eq(sam.getId()), anyString());

            assertThatExceptionOfType(OnboardingService.SignInUnavailableException.class)
                    .isThrownBy(() -> onboarding(true).createApplicantAccount(REFERENCE, PASSCODE));
            assertThat(transactions.begun()).isZero();
        }

        @Test
        @DisplayName("an unknown reference is still the applicant's refusal, not the platform's failure")
        void an_unknown_reference_stays_a_rule() {
            when(applications.findByReference("nope")).thenReturn(Optional.empty());

            assertThatThrownBy(() -> onboarding(false).createApplicantAccount("nope", PASSCODE))
                    .isExactlyInstanceOf(OnboardingService.ApplicationRuleException.class);
            verifyNoInteractions(keycloak);
        }
    }
}
