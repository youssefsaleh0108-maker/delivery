package com.delivery.onboarding.service;

import java.time.Instant;
import java.util.Map;
import java.util.Optional;
import java.util.Set;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.mockito.InOrder;

import com.delivery.onboarding.client.KeycloakAdminClient;
import com.delivery.onboarding.domain.AutoApprovalAuditRepository;
import com.delivery.onboarding.domain.AutoApprovalDecisionRepository;
import com.delivery.onboarding.domain.OnboardingApplication;
import com.delivery.onboarding.domain.OnboardingApplication.Kind;
import com.delivery.onboarding.domain.OnboardingApplicationRepository;
import com.delivery.onboarding.service.AccountApplicationService.Answers;
import com.delivery.onboarding.service.AccountApplicationService.Caller;
import com.delivery.onboarding.service.AccountApplicationService.Result;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatExceptionOfType;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyBoolean;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.inOrder;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

/**
 * Somebody who signed in with Google asking to ride, to sell, or to shop.
 *
 * <p>The property worth pinning above everything else is the one the class comment names: arriving
 * through Google is a new front door onto the existing review, not a way around it. So these check
 * what the account is given and in what order, that the approval gate is the same policy the open
 * form consults, and that asking twice — or asking for a role the platform took away — never
 * produces a second application or a role nobody decided on.
 */
class AccountApplicationServiceTest {

    private static final String SAM = "keycloak-sub-sam";

    private OnboardingApplicationRepository applications;
    private ApplicationIntake intake;
    private OnboardingService onboarding;
    private KeycloakAdminClient keycloak;
    private AutoApprovalDecisionRepository decisions;

    private AccountApplicationService service;

    @BeforeEach
    void setUp() {
        applications = mock(OnboardingApplicationRepository.class);
        intake = mock(ApplicationIntake.class);
        onboarding = mock(OnboardingService.class);
        keycloak = mock(KeycloakAdminClient.class);
        decisions = mock(AutoApprovalDecisionRepository.class);
        service = serviceWith(false, false);

        when(applications.findByApplicantUserRef(anyString())).thenReturn(Optional.empty());
        when(applications.findFirstByProvisionedUserRefOrderByCreatedAtDesc(anyString()))
                .thenReturn(Optional.empty());
    }

    /**
     * A real policy over an empty settings store, so the configured default is what answers — the
     * same arrangement {@code ApplicationDecisionOverDocumentsTest} uses for "manual".
     */
    private AccountApplicationService serviceWith(boolean riderAutomatic, boolean merchantAutomatic) {
        return new AccountApplicationService(applications, intake, onboarding, keycloak,
                new AutoApprovalPolicy(riderAutomatic, merchantAutomatic, false, decisions,
                        mock(AutoApprovalAuditRepository.class)));
    }

    /** Sam, signed in with Google: a verified address, and whatever roles the test says. */
    private static Caller sam(String... roles) {
        Set<String> held = Set.of(roles);
        return new Caller(SAM, "sam@gmail.example", true, held::contains);
    }

    private static Answers rider() {
        return new Answers(Kind.RIDER, null, "Sam Salem", null, null, null,
                Map.of("vehicleType", "MOTORCYCLE"), null);
    }

    private static Answers shop(String name) {
        return new Answers(Kind.MERCHANT, name, "Sam Salem", null, null, null, null, null);
    }

    private static OnboardingApplication recorded(Kind kind) {
        OnboardingApplication application = new OnboardingApplication(kind, "Sam Salem", "Sam Salem",
                "sam@gmail.example", Instant.now(), null, null, null, null, null);
        application.applicantAccountCreated(SAM);
        return application;
    }

    private void intakeReturns(OnboardingApplication application) {
        when(intake.recordForAccount(any(), any(), any(), any(), any(), any(), any(), any(), any(),
                any(), any())).thenReturn(application);
    }

    /**
     * The code a refusal carries — what the app translates, since the message is English.
     * Fails the test when the call is not refused, or is refused without a code.
     */
    private static String codeOf(Runnable call) {
        try {
            call.run();
        } catch (AccountApplicationService.AccountRuleException e) {
            return e.code();
        }
        throw new AssertionError("expected a refusal carrying a code");
    }

    @Nested
    @DisplayName("a first application")
    class FirstApplication {

        @Test
        @DisplayName("is recorded against the caller's own account, with the account's own address")
        void is_recorded_against_the_callers_account() {
            OnboardingApplication application = recorded(Kind.RIDER);
            intakeReturns(application);

            Result result = service.apply(sam(), rider());

            assertThat(result.created()).isTrue();
            assertThat(result.application()).isSameAs(application);
            // The subject and the address come from the token. A rider's business name is simply
            // their own, as the open form sends it.
            verify(intake).recordForAccount(eq(SAM), eq(Kind.RIDER), eq("Sam Salem"),
                    eq("Sam Salem"), eq("sam@gmail.example"), any(Instant.class), any(), any(),
                    any(), eq(Map.of("vehicleType", "MOTORCYCLE")), any());
            verify(onboarding).startReview(application);
        }

        @Test
        @DisplayName("gives the account APPLICANT BEFORE the live role, so a failure between them commits nothing")
        void grants_applicant_before_the_live_role() {
            intakeReturns(recorded(Kind.RIDER));

            service.apply(sam(), rider());

            InOrder order = inOrder(keycloak);
            order.verify(keycloak).grantRealmRole(SAM, "APPLICANT");
            order.verify(keycloak).grantRealmRole(SAM, "DELIVERY");
        }

        @Test
        @DisplayName("never hands out the live role when APPLICANT could not be granted")
        void no_live_role_without_applicant() {
            intakeReturns(recorded(Kind.MERCHANT));
            doThrow(new KeycloakAdminClient.ProvisioningException("Keycloak said no"))
                    .when(keycloak).grantRealmRole(SAM, "APPLICANT");

            assertThatExceptionOfType(KeycloakAdminClient.ProvisioningException.class)
                    .isThrownBy(() -> service.apply(sam(), shop("Sam's Shakes")));

            // The whole point of the order: MERCHANT on its own is a shop nobody approved.
            verify(keycloak, never()).grantRealmRole(SAM, "MERCHANT");
        }

        @Test
        @DisplayName("turns a transport failure from Keycloak into one the app can show and retry")
        void a_transport_failure_is_reported_as_retryable() {
            intakeReturns(recorded(Kind.RIDER));
            doThrow(new IllegalStateException("connection reset"))
                    .when(keycloak).grantRealmRole(SAM, "APPLICANT");

            assertThatExceptionOfType(KeycloakAdminClient.ProvisioningException.class)
                    .isThrownBy(() -> service.apply(sam(), rider()))
                    .withMessageContaining("try again");
        }

        @Test
        @DisplayName("stays in the review queue when auto-approval is off for that kind")
        void waits_for_a_reviewer_when_manual() {
            intakeReturns(recorded(Kind.RIDER));

            Result result = service.apply(sam(), rider());

            assertThat(result.application().getStatus())
                    .isEqualTo(OnboardingApplication.Status.SUBMITTED);
            verify(onboarding, never()).approve(any(), anyString(), anyBoolean());
        }

        @Test
        @DisplayName("is approved through the reviewer's own path when auto-approval is on for that kind")
        void auto_approval_goes_through_the_reviewers_path() {
            service = serviceWith(true, false);
            OnboardingApplication application = recorded(Kind.RIDER);
            intakeReturns(application);
            when(onboarding.approve(application.getId(), AutoApprovalPolicy.AUTOMATIC_REVIEWER, true))
                    .thenReturn(application);

            service.apply(sam(), rider());

            // Same policy, same approve(): the APPLICANT revoke and the partner record hang off it.
            verify(onboarding).approve(application.getId(), AutoApprovalPolicy.AUTOMATIC_REVIEWER, true);
        }

        @Test
        @DisplayName("is not auto-approved for one kind because the other kind is automatic")
        void auto_approval_is_per_kind() {
            service = serviceWith(true, false);
            intakeReturns(recorded(Kind.MERCHANT));

            service.apply(sam(), shop("Sam's Shakes"));

            verify(onboarding, never()).approve(any(), anyString(), anyBoolean());
        }

        @Test
        @DisplayName("stays in the queue, holding APPLICANT, when the automatic approval fails")
        void a_failed_auto_approval_leaves_it_in_the_queue() {
            service = serviceWith(true, false);
            OnboardingApplication application = recorded(Kind.RIDER);
            intakeReturns(application);
            when(onboarding.approve(any(), anyString(), anyBoolean()))
                    .thenThrow(new IllegalStateException("engine down"));

            Result result = service.apply(sam(), rider());

            assertThat(result.application()).isSameAs(application);
            assertThat(result.application().getStatus())
                    .isEqualTo(OnboardingApplication.Status.SUBMITTED);
            verify(keycloak, never()).revokeRealmRole(any(), any());
        }
    }

    @Nested
    @DisplayName("asking again")
    class Idempotency {

        @Test
        @DisplayName("hands back the same application and records nothing new")
        void a_second_call_does_not_duplicate() {
            OnboardingApplication existing = recorded(Kind.RIDER);
            when(applications.findByApplicantUserRef(SAM)).thenReturn(Optional.of(existing));

            Result result = service.apply(sam("APPLICANT", "DELIVERY"), rider());

            assertThat(result.created()).isFalse();
            assertThat(result.application()).isSameAs(existing);
            verifyNoInteractions(intake);
            verify(onboarding, never()).startReview(any());
        }

        @Test
        @DisplayName("re-asserts the applicant's roles while undecided, which is how a half-finished first try completes")
        void a_retry_finishes_what_the_first_attempt_started() {
            when(applications.findByApplicantUserRef(SAM))
                    .thenReturn(Optional.of(recorded(Kind.MERCHANT)));

            service.apply(sam(), shop("Sam's Shakes"));

            InOrder order = inOrder(keycloak);
            order.verify(keycloak).grantRealmRole(SAM, "APPLICANT");
            order.verify(keycloak).grantRealmRole(SAM, "MERCHANT");
        }

        @Test
        @DisplayName("touches no role once the application has been decided")
        void a_decided_application_is_returned_untouched() {
            OnboardingApplication approved = recorded(Kind.RIDER);
            approved.approve("reviewer-1");
            when(applications.findByApplicantUserRef(SAM)).thenReturn(Optional.of(approved));

            Result result = service.apply(sam("DELIVERY"), rider());

            assertThat(result.application()).isSameAs(approved);
            // Re-granting APPLICANT here would take away exactly what approval gave.
            verifyNoInteractions(keycloak);
        }

        @Test
        @DisplayName("refuses the other kind rather than starting a second application")
        void the_other_kind_is_refused() {
            when(applications.findByApplicantUserRef(SAM))
                    .thenReturn(Optional.of(recorded(Kind.RIDER)));

            assertThatExceptionOfType(OnboardingService.ApplicationRuleException.class)
                    .isThrownBy(() -> service.apply(sam(), shop("Sam's Shakes")))
                    .withMessageContaining("ride");
            assertThat(codeOf(() -> service.apply(sam(), shop("Sam's Shakes"))))
                    .isEqualTo(AccountApplicationService.AccountRuleException.OTHER_APPLICATION);

            verifyNoInteractions(intake, keycloak);
        }

        @Test
        @DisplayName("hands back the winner when two taps race to the insert")
        void a_lost_race_returns_the_winners_application() {
            OnboardingApplication winner = recorded(Kind.RIDER);
            when(applications.findByApplicantUserRef(SAM))
                    .thenReturn(Optional.empty())
                    .thenReturn(Optional.of(winner));
            when(intake.recordForAccount(any(), any(), any(), any(), any(), any(), any(), any(),
                    any(), any(), any()))
                    .thenThrow(new OnboardingService.ApplicationRuleException(
                            "You already have an application in progress for this business"));

            Result result = service.apply(sam(), rider());

            assertThat(result.created()).isFalse();
            assertThat(result.application()).isSameAs(winner);
        }
    }

    @Nested
    @DisplayName("the gates")
    class Gates {

        @Test
        @DisplayName("a partner on the provisioned column cannot apply again to get a suspended role back")
        void a_suspended_partner_cannot_reapply() {
            OnboardingApplication provisioned = new OnboardingApplication(Kind.RIDER, "Sam Salem",
                    "Sam Salem", "sam@gmail.example", Instant.now(), null, null, null, null, null);
            provisioned.approve("reviewer-1");
            provisioned.provisionedAs(SAM, null);
            when(applications.findFirstByProvisionedUserRefOrderByCreatedAtDesc(SAM))
                    .thenReturn(Optional.of(provisioned));

            // Suspended: the token no longer carries DELIVERY.
            Result result = service.apply(sam(), rider());

            assertThat(result.created()).isFalse();
            verifyNoInteractions(intake, keycloak);
        }

        @Test
        @DisplayName("an account that already trades as that kind is refused, not demoted to APPLICANT")
        void an_account_holding_the_role_is_refused() {
            assertThatExceptionOfType(OnboardingService.ApplicationRuleException.class)
                    .isThrownBy(() -> service.apply(sam("DELIVERY"), rider()));

            verifyNoInteractions(intake, keycloak);
        }

        @Test
        @DisplayName("an account that trades as the OTHER kind is refused too, so APPLICANT never blocks a working partner")
        void an_account_trading_as_the_other_kind_is_refused() {
            // A shop with no onboarding row — a seeded account, or one given MERCHANT by hand —
            // asking to ride. APPLICANT is realm-wide: granted here it would stop the shop
            // publishing at once, and a rejection would never take it off again.
            assertThat(codeOf(() -> service.apply(sam("MERCHANT"), rider())))
                    .isEqualTo(AccountApplicationService.AccountRuleException.ALREADY_PARTNER);
            // And a rider asking to sell, and a delivery company asking either.
            assertThat(codeOf(() -> service.apply(sam("DELIVERY"), shop("Sam's Shakes"))))
                    .isEqualTo(AccountApplicationService.AccountRuleException.ALREADY_PARTNER);
            assertThat(codeOf(() -> service.apply(sam("CARRIER"), rider())))
                    .isEqualTo(AccountApplicationService.AccountRuleException.ALREADY_PARTNER);

            verify(keycloak, never()).grantRealmRole(anyString(), anyString());
            verifyNoInteractions(intake);
        }

        @Test
        @DisplayName("a delivery company cannot be applied for from a signed-in account")
        void a_carrier_is_refused() {
            Answers carrier = new Answers(Kind.CARRIER, "Fast Fleet", "Sam Salem", null, null,
                    null, null, null);

            assertThatExceptionOfType(OnboardingService.ApplicationRuleException.class)
                    .isThrownBy(() -> service.apply(sam(), carrier));

            verifyNoInteractions(intake, keycloak);
        }

        @Test
        @DisplayName("an address the identity provider did not vouch for is refused before anything is written")
        void an_unverified_address_is_refused() {
            Caller unverified = new Caller(SAM, "sam@gmail.example", false, role -> false);

            assertThatExceptionOfType(OnboardingService.ApplicationRuleException.class)
                    .isThrownBy(() -> service.apply(unverified, rider()));
            assertThat(codeOf(() -> service.apply(unverified, rider())))
                    .isEqualTo(AccountApplicationService.AccountRuleException.EMAIL_UNVERIFIED);

            verifyNoInteractions(intake, keycloak);
        }

        @Test
        @DisplayName("a shop with no name is refused")
        void a_shop_needs_a_name() {
            assertThatExceptionOfType(OnboardingService.ApplicationRuleException.class)
                    .isThrownBy(() -> service.apply(sam(), shop("  ")));

            verifyNoInteractions(intake, keycloak);
        }

        @Test
        @DisplayName("the domain's own refusals come back as something the caller can act on")
        void domain_refusals_become_rule_violations() {
            when(intake.recordForAccount(any(), any(), any(), any(), any(), any(), any(), any(),
                    any(), any(), any()))
                    .thenThrow(new IllegalArgumentException("Only a rider applies to a delivery company"));

            assertThatExceptionOfType(OnboardingService.ApplicationRuleException.class)
                    .isThrownBy(() -> service.apply(sam(), shop("Sam's Shakes")))
                    .withMessage("Only a rider applies to a delivery company");
        }
    }

    @Nested
    @DisplayName("becoming a customer")
    class Customer {

        @Test
        @DisplayName("grants CUSTOMER to the caller's own account and nothing else")
        void grants_customer_to_the_caller() {
            service.becomeCustomer(sam());

            verify(keycloak).grantRealmRole(SAM, "CUSTOMER");
            verify(keycloak, never()).grantRealmRole(eq(SAM), eq("APPLICANT"));
        }

        @Test
        @DisplayName("is a no-op for an account that already shops")
        void is_idempotent() {
            service.becomeCustomer(sam("CUSTOMER"));

            verifyNoInteractions(keycloak);
        }

        @Test
        @DisplayName("is refused on an address nobody vouched for, as customer sign-up is")
        void needs_a_verified_address() {
            Caller unverified = new Caller(SAM, "sam@gmail.example", false, role -> false);

            assertThatExceptionOfType(OnboardingService.ApplicationRuleException.class)
                    .isThrownBy(() -> service.becomeCustomer(unverified));

            verifyNoInteractions(keycloak);
        }
    }
}
