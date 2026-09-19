package com.delivery.onboarding.api;

import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import com.delivery.onboarding.client.PlatformClient;
import com.delivery.onboarding.service.AccountApplicationService;
import com.delivery.onboarding.service.ApplicantDocumentService;
import com.delivery.onboarding.service.CompanyRiderAnswers;
import com.delivery.onboarding.service.CustomerSignUpService;
import com.delivery.onboarding.service.OnboardingService;
import com.delivery.onboarding.service.PartnerManagementService;
import com.delivery.onboarding.service.PayoutDetailsService;
import com.delivery.onboarding.service.VerificationService;

import com.fasterxml.jackson.databind.ObjectMapper;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * A rider's delivery company refused, or not checked, as both front doors answer it.
 *
 * <p>The app reads these two answers by their code, says them in the reader's language, and acts on
 * them differently: {@code company-not-hiring} (422) takes the rider back to choose another company,
 * while {@code hiring-companies-unavailable} (503) offers the same application again. So the status
 * and the code are pinned on the open form's door and on the signed-in one alike.
 */
@DisplayName("a rider's delivery company, refused or unchecked, over HTTP")
class RiderCompanyAnswersHttpTest {

    private static final ObjectMapper JSON = new ObjectMapper();
    private static final UUID SWIFT = UUID.fromString("8a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d");

    private OnboardingService onboarding;
    private AccountApplicationService accounts;
    private MockMvc open;
    private MockMvc signedIn;

    @BeforeEach
    void setUp() {
        onboarding = mock(OnboardingService.class);
        accounts = mock(AccountApplicationService.class);
        open = MockMvcBuilders.standaloneSetup(new OnboardingController(
                        onboarding, mock(VerificationService.class), mock(PlatformClient.class),
                        mock(CustomerSignUpService.class), mock(ApplicantDocumentService.class),
                        mock(PayoutDetailsService.class), mock(PartnerManagementService.class)))
                .build();
        signedIn = MockMvcBuilders.standaloneSetup(new AccountOnboardingController(accounts))
                .build();

        Jwt token = Jwt.withTokenValue("token").header("alg", "none")
                .subject("keycloak-sub-sam")
                .claim("email", "sam@gmail.example")
                .claim("email_verified", true)
                .build();
        SecurityContextHolder.getContext().setAuthentication(
                new JwtAuthenticationToken(token, List.of()));
    }

    @AfterEach
    void tearDown() {
        SecurityContextHolder.clearContext();
    }

    private static String openFormRider() throws Exception {
        return JSON.writeValueAsString(Map.of(
                "kind", "RIDER",
                "businessName", "Sam Salem",
                "contactName", "Sam Salem",
                "contactEmail", "sam@example.test",
                "emailVerificationToken", "proof-token",
                "targetProviderId", SWIFT.toString()));
    }

    private static String accountRider() throws Exception {
        return JSON.writeValueAsString(Map.of(
                "kind", "RIDER",
                "contactName", "Sam Salem",
                "targetProviderId", SWIFT.toString()));
    }

    private static CompanyRiderAnswers.CompanyAnswerException notHiring() {
        return new CompanyRiderAnswers.CompanyAnswerException(
                CompanyRiderAnswers.CompanyAnswerException.NOT_HIRING,
                "That delivery company is not taking riders right now. Choose another company, "
                        + "or ride for YouDrop");
    }

    private static PlatformClient.CompaniesUnavailableException unavailable() {
        return new PlatformClient.CompaniesUnavailableException(
                "We could not check that delivery company just now. Please try again in a moment.",
                null);
    }

    @Test
    @DisplayName("the open form: a company that is not hiring is a 422 carrying company-not-hiring")
    void open_form_not_hiring() throws Exception {
        when(onboarding.submit(any(), any(), any(), any(), any(), any(), any(), any(), any(), any()))
                .thenThrow(notHiring());

        open.perform(post("/api/onboarding/applications")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(openFormRider()))
                .andExpect(status().isUnprocessableEntity())
                .andExpect(jsonPath("$.code").value("company-not-hiring"))
                .andExpect(jsonPath("$.message").exists());
    }

    @Test
    @DisplayName("the open form: Order Manager not answering is a 503 carrying hiring-companies-unavailable")
    void open_form_unavailable() throws Exception {
        when(onboarding.submit(any(), any(), any(), any(), any(), any(), any(), any(), any(), any()))
                .thenThrow(unavailable());

        open.perform(post("/api/onboarding/applications")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(openFormRider()))
                .andExpect(status().isServiceUnavailable())
                .andExpect(jsonPath("$.code").value("hiring-companies-unavailable"))
                .andExpect(jsonPath("$.message").exists());
    }

    @Test
    @DisplayName("signed in: a company that is not hiring is a 422 carrying company-not-hiring")
    void signed_in_not_hiring() throws Exception {
        when(accounts.apply(any(), any())).thenThrow(notHiring());

        signedIn.perform(post("/api/onboarding/applications/mine")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(accountRider()))
                .andExpect(status().isUnprocessableEntity())
                .andExpect(jsonPath("$.code").value("company-not-hiring"));
    }

    @Test
    @DisplayName("signed in: Order Manager not answering is a 503 carrying hiring-companies-unavailable")
    void signed_in_unavailable() throws Exception {
        when(accounts.apply(any(), any())).thenThrow(unavailable());

        signedIn.perform(post("/api/onboarding/applications/mine")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(accountRider()))
                .andExpect(status().isServiceUnavailable())
                .andExpect(jsonPath("$.code").value("hiring-companies-unavailable"));
    }
}
