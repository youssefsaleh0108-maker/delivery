package com.delivery.onboarding.api;

import java.time.Instant;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.http.MediaType;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import com.delivery.onboarding.client.KeycloakAdminClient;
import com.delivery.onboarding.domain.OnboardingApplication;
import com.delivery.onboarding.domain.OnboardingApplication.Kind;
import com.delivery.onboarding.service.AccountApplicationService;
import com.delivery.onboarding.service.AccountApplicationService.Answers;
import com.delivery.onboarding.service.AccountApplicationService.Caller;
import com.delivery.onboarding.service.AccountApplicationService.Result;
import com.delivery.onboarding.service.OnboardingService;

import com.fasterxml.jackson.databind.ObjectMapper;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * The two signed-in onboarding writes act on the caller's own token and nothing else.
 *
 * <p>The shape of the guarantee is the same as the {@code /applications/mine} document endpoints:
 * there is no account id in the path or in the body, so the test is not "the id is checked", it is
 * "an id somebody puts in the body goes nowhere". The rest pins what the app relies on — 201 against
 * 200 for created against handed back, and the three failure answers it turns into a sentence.
 */
class AccountOnboardingAccessTest {

    private static final ObjectMapper JSON = new ObjectMapper();

    private static final String SAM = "keycloak-sub-sam";
    private static final String ALEX = "keycloak-sub-alex";

    private AccountApplicationService accounts;
    private MockMvc mvc;

    @BeforeEach
    void setUp() {
        accounts = mock(AccountApplicationService.class);
        mvc = MockMvcBuilders.standaloneSetup(new AccountOnboardingController(accounts)).build();
    }

    @AfterEach
    void tearDown() {
        SecurityContextHolder.clearContext();
    }

    /**
     * Signs the request as this subject, the way a Google-brokered token would arrive.
     *
     * @param emailVerified null leaves the claim off the token altogether
     */
    private static void signedInAs(String subject, Boolean emailVerified, String... roles) {
        Jwt.Builder token = Jwt.withTokenValue("token")
                .header("alg", "none")
                .subject(subject)
                .claim("email", subject + "@gmail.example");
        if (emailVerified != null) {
            token.claim("email_verified", emailVerified);
        }
        List<GrantedAuthority> authorities = Arrays.stream(roles)
                .map(role -> (GrantedAuthority) new SimpleGrantedAuthority("ROLE_" + role))
                .toList();
        SecurityContextHolder.getContext().setAuthentication(
                new JwtAuthenticationToken(token.build(), authorities));
    }

    private static OnboardingApplication application(Kind kind) {
        return new OnboardingApplication(kind, "Sam Salem", "Sam Salem", "sam@gmail.example",
                Instant.now(), null, null, null, null, null);
    }

    private static String riderBody(Map<String, Object> extra) throws Exception {
        Map<String, Object> body = new HashMap<>(Map.of(
                "kind", "RIDER",
                "contactName", "Sam Salem"));
        body.putAll(extra);
        return JSON.writeValueAsString(body);
    }

    @Test
    @DisplayName("applies as the token's subject, whatever account the body tries to name")
    void applies_as_the_token_subject() throws Exception {
        when(accounts.apply(any(), any())).thenReturn(new Result(application(Kind.RIDER), true));

        signedInAs(SAM, true);
        mvc.perform(post("/api/onboarding/applications/mine")
                        .contentType(MediaType.APPLICATION_JSON)
                        // Fields the request record does not have. They must go nowhere.
                        .content(riderBody(Map.of(
                                "userRef", ALEX,
                                "applicantUserRef", ALEX,
                                "contactEmail", "alex@example.test"))))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.kind").value("RIDER"))
                .andExpect(jsonPath("$.status").value("SUBMITTED"));

        ArgumentCaptor<Caller> caller = ArgumentCaptor.forClass(Caller.class);
        ArgumentCaptor<Answers> answers = ArgumentCaptor.forClass(Answers.class);
        verify(accounts).apply(caller.capture(), answers.capture());
        assertThat(caller.getValue().userRef()).isEqualTo(SAM);
        // The address is the account's, from the token — not the one the body offered.
        assertThat(caller.getValue().email()).isEqualTo(SAM + "@gmail.example");
        assertThat(caller.getValue().emailVerified()).isTrue();
        assertThat(answers.getValue().kind()).isEqualTo(Kind.RIDER);
        assertThat(answers.getValue().contactName()).isEqualTo("Sam Salem");
    }

    @Test
    @DisplayName("answers 200, not 201, when the account already had the application")
    void an_existing_application_is_200() throws Exception {
        when(accounts.apply(any(), any())).thenReturn(new Result(application(Kind.RIDER), false));

        signedInAs(SAM, true, "APPLICANT", "DELIVERY");
        mvc.perform(post("/api/onboarding/applications/mine")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(riderBody(Map.of())))
                .andExpect(status().isOk());
    }

    @Test
    @DisplayName("asks the token which roles the caller holds, so the service can refuse a demotion")
    void roles_come_from_the_token() throws Exception {
        when(accounts.apply(any(), any())).thenReturn(new Result(application(Kind.RIDER), false));

        signedInAs(SAM, true, "DELIVERY");
        mvc.perform(post("/api/onboarding/applications/mine")
                .contentType(MediaType.APPLICATION_JSON)
                .content(riderBody(Map.of())));

        ArgumentCaptor<Caller> caller = ArgumentCaptor.forClass(Caller.class);
        verify(accounts).apply(caller.capture(), any());
        assertThat(caller.getValue().holdsRole().test("DELIVERY")).isTrue();
        assertThat(caller.getValue().holdsRole().test("MERCHANT")).isFalse();
    }

    @Test
    @DisplayName("reads a token with no email_verified claim as unverified, which refuses rather than admits")
    void a_missing_verified_claim_reads_as_false() throws Exception {
        when(accounts.apply(any(), any())).thenReturn(new Result(application(Kind.RIDER), true));

        signedInAs(SAM, null);
        mvc.perform(post("/api/onboarding/applications/mine")
                .contentType(MediaType.APPLICATION_JSON)
                .content(riderBody(Map.of())));

        ArgumentCaptor<Caller> caller = ArgumentCaptor.forClass(Caller.class);
        verify(accounts).apply(caller.capture(), any());
        assertThat(caller.getValue().emailVerified()).isFalse();
    }

    @Test
    @DisplayName("refuses a request with no kind before the service is touched")
    void a_missing_kind_is_400() throws Exception {
        signedInAs(SAM, true);
        mvc.perform(post("/api/onboarding/applications/mine")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(JSON.writeValueAsString(Map.of("contactName", "Sam Salem"))))
                .andExpect(status().isBadRequest());

        verifyNoInteractions(accounts);
    }

    @Test
    @DisplayName("says why in 422 when the service refuses, so the app can show the sentence")
    void a_rule_is_422_with_its_message() throws Exception {
        when(accounts.apply(any(), any())).thenThrow(new OnboardingService.ApplicationRuleException(
                "This account already has an application to ride with YouDrop"));

        signedInAs(SAM, true);
        mvc.perform(post("/api/onboarding/applications/mine")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(riderBody(Map.of())))
                .andExpect(status().isUnprocessableEntity())
                .andExpect(jsonPath("$.message")
                        .value("This account already has an application to ride with YouDrop"))
                // A plain rule — the domain's own refusals — has no code, and the app then shows
                // the message as it came.
                .andExpect(jsonPath("$.code").doesNotExist());
    }

    @Test
    @DisplayName("carries a known refusal's code beside its message, so the app can say it in the reader's language")
    void a_coded_rule_carries_its_code() throws Exception {
        when(accounts.apply(any(), any())).thenThrow(new AccountApplicationService.AccountRuleException(
                AccountApplicationService.AccountRuleException.ALREADY_PARTNER,
                "This account already sells on YouDrop"));

        signedInAs(SAM, true, "MERCHANT");
        mvc.perform(post("/api/onboarding/applications/mine")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(riderBody(Map.of())))
                .andExpect(status().isUnprocessableEntity())
                .andExpect(jsonPath("$.code").value("already-partner"))
                .andExpect(jsonPath("$.message").value("This account already sells on YouDrop"));
    }

    @Test
    @DisplayName("answers 502 with a retryable sentence when Keycloak would not set the roles")
    void a_keycloak_failure_is_502() throws Exception {
        when(accounts.apply(any(), any())).thenThrow(new KeycloakAdminClient.ProvisioningException(
                "Your application is in, but we could not finish setting up your account. "
                        + "Please try again."));

        signedInAs(SAM, true);
        mvc.perform(post("/api/onboarding/applications/mine")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(riderBody(Map.of())))
                .andExpect(status().isBadGateway())
                .andExpect(jsonPath("$.message").exists());
    }

    @Test
    @DisplayName("becoming a customer acts on the token's subject and answers 204")
    void becoming_a_customer_is_the_callers_own() throws Exception {
        signedInAs(SAM, true);
        mvc.perform(post("/api/onboarding/me/customer"))
                .andExpect(status().isNoContent());

        ArgumentCaptor<Caller> caller = ArgumentCaptor.forClass(Caller.class);
        verify(accounts).becomeCustomer(caller.capture());
        assertThat(caller.getValue().userRef()).isEqualTo(SAM);
    }

    @Test
    @DisplayName("becoming a customer on an unverified address is 422, not a silent success")
    void becoming_a_customer_can_be_refused() throws Exception {
        doThrow(new OnboardingService.ApplicationRuleException(
                "Your account's email address has not been verified, so it cannot shop yet"))
                .when(accounts).becomeCustomer(any());

        signedInAs(SAM, false);
        mvc.perform(post("/api/onboarding/me/customer"))
                .andExpect(status().isUnprocessableEntity())
                .andExpect(jsonPath("$.message").exists());
    }
}
