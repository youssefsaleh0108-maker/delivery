package com.delivery.onboarding.api;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import com.delivery.onboarding.client.PlatformClient;
import com.delivery.onboarding.service.AccountApplicationService;
import com.delivery.onboarding.service.ApplicantDocumentService;
import com.delivery.onboarding.service.CustomerSignUpService;
import com.delivery.onboarding.service.OnboardingService;
import com.delivery.onboarding.service.PartnerManagementService;
import com.delivery.onboarding.service.PayoutDetailsService;
import com.delivery.onboarding.service.VerificationService;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * What the app is told when an applicant chooses their passcode.
 *
 * <p>The app matches on the {@code code}, not the sentence, and a failure it has no code for is shown
 * as "That did not go through" — which is what a rider saw when this endpoint could only answer a bare
 * 500. So the codes are pinned here as the contract they are.
 */
class ApplicantSignInApiTest {

    private static final String BODY = "{\"password\":\"482910\",\"accountTicket\":\"ticket-sam\"}";

    private OnboardingService onboarding;
    private MockMvc mvc;

    @BeforeEach
    void setUp() {
        onboarding = mock(OnboardingService.class);
        mvc = MockMvcBuilders.standaloneSetup(new OnboardingController(
                        onboarding, mock(VerificationService.class),
                        mock(PlatformClient.class), mock(CustomerSignUpService.class),
                        mock(ApplicantDocumentService.class), mock(PayoutDetailsService.class),
                        mock(PartnerManagementService.class)))
                .build();
    }

    @Test
    @DisplayName("201 once the sign-in exists, with the ticket taken from the body")
    void made() throws Exception {
        mvc.perform(post("/api/onboarding/applications/ref-sam/account")
                        .contentType(MediaType.APPLICATION_JSON).content(BODY))
                .andExpect(status().isCreated());

        verify(onboarding).createApplicantAccount("ref-sam", "482910", "ticket-sam", null);
    }

    @Test
    @DisplayName("an email proof in the body reaches the service in the ticket's place")
    void an_email_proof_instead() throws Exception {
        mvc.perform(post("/api/onboarding/applications/ref-sam/account")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"password\":\"482910\",\"emailVerificationToken\":\"proof-sam\"}"))
                .andExpect(status().isCreated());

        verify(onboarding).createApplicantAccount("ref-sam", "482910", null, "proof-sam");
    }

    @Test
    @DisplayName("the reference alone is a 422 coded sign-in-proof-missing, whose words tell an old app's user to update")
    void the_reference_alone() throws Exception {
        assertThat(AccountApplicationService.AccountRuleException.SIGN_IN_PROOF_MISSING)
                .isEqualTo("sign-in-proof-missing");
        doThrow(new AccountApplicationService.AccountRuleException("sign-in-proof-missing",
                "This version of the app can no longer finish setting up a sign-in. Please update "
                        + "the app and try again."))
                .when(onboarding).createApplicantAccount("ref-sam", "482910", null, null);

        // Exactly what an installed copy of the app sends: the passcode and nothing else.
        mvc.perform(post("/api/onboarding/applications/ref-sam/account")
                        .contentType(MediaType.APPLICATION_JSON).content("{\"password\":\"482910\"}"))
                .andExpect(status().isUnprocessableEntity())
                .andExpect(jsonPath("$.code").value("sign-in-proof-missing"))
                .andExpect(jsonPath("$.message").value(
                        org.hamcrest.Matchers.containsString("update the app")));
    }

    @Test
    @DisplayName("a ticket that is wrong, spent or late is a 422 coded sign-in-proof-rejected")
    void a_rejected_ticket() throws Exception {
        assertThat(AccountApplicationService.AccountRuleException.SIGN_IN_PROOF_REJECTED)
                .isEqualTo("sign-in-proof-rejected");
        doThrow(new AccountApplicationService.AccountRuleException("sign-in-proof-rejected",
                "That confirmation has expired or was already used."))
                .when(onboarding).createApplicantAccount("ref-sam", "482910", "ticket-sam", null);

        mvc.perform(post("/api/onboarding/applications/ref-sam/account")
                        .contentType(MediaType.APPLICATION_JSON).content(BODY))
                .andExpect(status().isUnprocessableEntity())
                .andExpect(jsonPath("$.code").value("sign-in-proof-rejected"));
    }

    @Test
    @DisplayName("an address that belongs to another account is a 422 coded account-exists")
    void the_address_has_an_account() throws Exception {
        doThrow(new AccountApplicationService.AccountRuleException(
                AccountApplicationService.AccountRuleException.ACCOUNT_EXISTS,
                "An account already uses this email address."))
                .when(onboarding).createApplicantAccount("ref-sam", "482910", "ticket-sam", null);

        mvc.perform(post("/api/onboarding/applications/ref-sam/account")
                        .contentType(MediaType.APPLICATION_JSON).content(BODY))
                .andExpect(status().isUnprocessableEntity())
                .andExpect(jsonPath("$.code").value("account-exists"))
                .andExpect(jsonPath("$.message").value("An account already uses this email address."));
    }

    @Test
    @DisplayName("asking again once the sign-in is recorded is a 422 coded sign-in-exists, not bare English")
    void the_sign_in_is_already_there() throws Exception {
        doThrow(new AccountApplicationService.AccountRuleException(
                AccountApplicationService.AccountRuleException.SIGN_IN_EXISTS,
                "That application already has a sign-in."))
                .when(onboarding).createApplicantAccount("ref-sam", "482910", "ticket-sam", null);

        mvc.perform(post("/api/onboarding/applications/ref-sam/account")
                        .contentType(MediaType.APPLICATION_JSON).content(BODY))
                .andExpect(status().isUnprocessableEntity())
                .andExpect(jsonPath("$.code").value("sign-in-exists"));
    }

    @Test
    @DisplayName("a decided application, or one whose email backoffice changed, is refused by name too")
    void the_other_refusals_are_coded() throws Exception {
        // Literals, not the constants: these strings are what the app matches on.
        assertThat(AccountApplicationService.AccountRuleException.SIGN_IN_EXISTS).isEqualTo("sign-in-exists");
        assertThat(AccountApplicationService.AccountRuleException.APPLICATION_DECIDED)
                .isEqualTo("application-decided");
        assertThat(AccountApplicationService.AccountRuleException.EMAIL_CHANGED).isEqualTo("email-changed");
        for (String code : new String[] {"application-decided", "email-changed"}) {
            doThrow(new AccountApplicationService.AccountRuleException(code, "Refused."))
                    .when(onboarding).createApplicantAccount("ref-sam", "482910", "ticket-sam", null);

            mvc.perform(post("/api/onboarding/applications/ref-sam/account")
                            .contentType(MediaType.APPLICATION_JSON).content(BODY))
                    .andExpect(status().isUnprocessableEntity())
                    .andExpect(jsonPath("$.code").value(code));
        }
    }

    @Test
    @DisplayName("the platform failing on its side is a 503 coded sign-in-unavailable, not a bare 500")
    void the_platform_failed() throws Exception {
        doThrow(new OnboardingService.SignInUnavailableException(
                "Your sign-in could not be set up just now. Please try again in a minute.",
                new IllegalStateException("Keycloak refused a service-account token")))
                .when(onboarding).createApplicantAccount("ref-sam", "482910", "ticket-sam", null);

        mvc.perform(post("/api/onboarding/applications/ref-sam/account")
                        .contentType(MediaType.APPLICATION_JSON).content(BODY))
                .andExpect(status().isServiceUnavailable())
                .andExpect(jsonPath("$.code").value("sign-in-unavailable"))
                .andExpect(jsonPath("$.message").value(
                        "Your sign-in could not be set up just now. Please try again in a minute."));
    }

    @Test
    @DisplayName("a rejection that lost to the applicant's sign-in on the row's version is a 409, not a bare 500")
    void a_version_conflict() throws Exception {
        java.util.UUID id = java.util.UUID.randomUUID();
        org.springframework.security.core.context.SecurityContextHolder.getContext().setAuthentication(
                new org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken(
                        org.springframework.security.oauth2.jwt.Jwt.withTokenValue("token")
                                .header("alg", "none").subject("reviewer-1").build(),
                        java.util.List.of()));
        try {
            doThrow(new org.springframework.orm.ObjectOptimisticLockingFailureException(
                    "OnboardingApplication", id))
                    .when(onboarding).reject(id, "reviewer-1", "Not taking riders there");

            mvc.perform(post("/api/onboarding/applications/{id}/reject", id)
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{\"reason\":\"Not taking riders there\"}"))
                    .andExpect(status().isConflict())
                    .andExpect(jsonPath("$.code").value("application-changed"));
        } finally {
            org.springframework.security.core.context.SecurityContextHolder.clearContext();
        }
    }
}
