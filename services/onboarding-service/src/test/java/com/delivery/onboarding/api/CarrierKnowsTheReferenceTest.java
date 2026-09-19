package com.delivery.onboarding.api;

import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.camunda.bpm.engine.RuntimeService;
import org.camunda.bpm.engine.TaskService;
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
import org.springframework.transaction.PlatformTransactionManager;

import com.delivery.onboarding.client.KeycloakAdminClient;
import com.delivery.onboarding.client.PlatformClient;
import com.delivery.onboarding.domain.AutoApprovalAuditRepository;
import com.delivery.onboarding.domain.AutoApprovalDecisionRepository;
import com.delivery.onboarding.domain.OnboardingApplication;
import com.delivery.onboarding.domain.OnboardingApplication.Kind;
import com.delivery.onboarding.domain.OnboardingApplicationRepository;
import com.delivery.onboarding.domain.PartnerEditEntryRepository;
import com.delivery.onboarding.service.ApplicantDocumentService;
import com.delivery.onboarding.service.ApplicationIntake;
import com.delivery.onboarding.service.AutoApprovalPolicy;
import com.delivery.onboarding.service.CustomerSignUpService;
import com.delivery.onboarding.service.OnboardingService;
import com.delivery.onboarding.service.PartnerManagementService;
import com.delivery.onboarding.service.PayoutDetailsService;
import com.delivery.onboarding.service.ServiceProviderAnswers;
import com.delivery.onboarding.service.VerificationService;
import com.jayway.jsonpath.JsonPath;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * A delivery company knows its applicants' references, and a reference sets no passcode.
 *
 * <p>The finding, end to end over HTTP and through the real service: the company's own listing hands
 * it every open rider application's reference — its portal prints them — and the passcode step used
 * to take a reference as the whole of its proof. The company could choose the passcode on a rider's
 * unfinished sign-in, sign in as the rider, and then approve it from its own queue.
 */
@DisplayName("a delivery company that knows an applicant's reference")
class CarrierKnowsTheReferenceTest {

    private static final String COMPANY_OWNER = "keycloak-sub-company-owner";

    private final UUID company = UUID.randomUUID();

    private OnboardingApplicationRepository applications;
    private ApplicationIntake intake;
    private VerificationService verifications;
    private KeycloakAdminClient keycloak;
    private MockMvc mvc;

    /** Nadia's application to ride for the company, and the ticket only her phone was answered with. */
    private OnboardingApplication nadia;
    private String nadiasTicket;

    @BeforeEach
    void setUp() {
        applications = mock(OnboardingApplicationRepository.class);
        intake = mock(ApplicationIntake.class);
        verifications = mock(VerificationService.class);
        keycloak = mock(KeycloakAdminClient.class);
        PlatformClient platform = mock(PlatformClient.class);
        ApplicantDocumentService documents = mock(ApplicantDocumentService.class);

        OnboardingService onboarding = new OnboardingService(applications, intake, verifications,
                mock(ServiceProviderAnswers.class), mock(RuntimeService.class), mock(TaskService.class),
                keycloak, documents,
                new AutoApprovalPolicy(false, false, false, mock(AutoApprovalDecisionRepository.class),
                        mock(AutoApprovalAuditRepository.class)),
                mock(PlatformTransactionManager.class), mock(PartnerEditEntryRepository.class));
        mvc = MockMvcBuilders.standaloneSetup(new OnboardingController(onboarding, verifications,
                        platform, mock(CustomerSignUpService.class), documents,
                        mock(PayoutDetailsService.class), mock(PartnerManagementService.class)))
                .build();

        nadia = new OnboardingApplication(Kind.RIDER, "Nadia Haddad", "Nadia Haddad",
                "nadia@example.test", Instant.now(), null, null, null, null, company);
        nadiasTicket = nadia.issueAccountTicket(Instant.now());
        when(applications.findByTargetProviderIdAndStatusInOrderByCreatedAtAsc(eq(company), any()))
                .thenReturn(List.of(nadia));
        when(applications.findByReference(nadia.getReference())).thenReturn(Optional.of(nadia));
        when(applications.findByApplicantUserRef(anyString())).thenReturn(Optional.empty());
        when(platform.isStaffOf(company, COMPANY_OWNER)).thenReturn(true);

        Jwt jwt = Jwt.withTokenValue("token").header("alg", "none").subject(COMPANY_OWNER).build();
        SecurityContextHolder.getContext().setAuthentication(new JwtAuthenticationToken(jwt, List.of()));
    }

    @AfterEach
    void tearDown() {
        SecurityContextHolder.clearContext();
    }

    /** What the company's listing tells it — the reference is there, as it is meant to be. */
    private String referenceFromTheCompanysListing() throws Exception {
        String listing = mvc.perform(get("/api/onboarding/applications/for-company/{id}", company))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].accountTicket").doesNotExist())
                .andReturn().getResponse().getContentAsString();
        String reference = JsonPath.read(listing, "$[0].reference");
        assertThat(reference).isEqualTo(nadia.getReference());
        assertThat(listing).doesNotContain(nadiasTicket);
        return reference;
    }

    @Test
    @DisplayName("cannot set a passcode with the reference alone")
    void the_reference_alone_is_refused() throws Exception {
        String reference = referenceFromTheCompanysListing();

        mvc.perform(post("/api/onboarding/applications/{reference}/account", reference)
                        .contentType(MediaType.APPLICATION_JSON).content("{\"password\":\"111111\"}"))
                .andExpect(status().isUnprocessableEntity())
                .andExpect(jsonPath("$.code").value("sign-in-proof-missing"));

        verifyNoInteractions(keycloak);
        verify(intake, never()).attachApplicantAccount(any(), any(), any());
    }

    @Test
    @DisplayName("cannot set one with a made-up ticket, or with an email proof it does not hold")
    void guessing_is_refused() throws Exception {
        String reference = referenceFromTheCompanysListing();

        mvc.perform(post("/api/onboarding/applications/{reference}/account", reference)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"password\":\"111111\",\"accountTicket\":\"" + reference + "\"}"))
                .andExpect(status().isUnprocessableEntity())
                .andExpect(jsonPath("$.code").value("sign-in-proof-rejected"));
        mvc.perform(post("/api/onboarding/applications/{reference}/account", reference)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"password\":\"111111\",\"emailVerificationToken\":\"my-own-proof\"}"))
                .andExpect(status().isUnprocessableEntity())
                .andExpect(jsonPath("$.code").value("sign-in-proof-rejected"));

        verifyNoInteractions(keycloak);
        verify(intake, never()).attachApplicantAccount(any(), any(), any());
    }

    @Test
    @DisplayName("while the applicant, with the ticket her submission was answered with, gets her sign-in")
    void the_applicant_with_her_ticket_gets_in() throws Exception {
        when(keycloak.createApplicant("nadia@example.test", "Nadia", "Haddad", "DELIVERY", "482910",
                nadia.getId())).thenReturn("kc-nadia");
        when(intake.attachApplicantAccount(eq(nadia.getId()), eq("kc-nadia"), any())).thenReturn(nadia);

        mvc.perform(post("/api/onboarding/applications/{reference}/account", nadia.getReference())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"password\":\"482910\",\"accountTicket\":\"" + nadiasTicket + "\"}"))
                .andExpect(status().isCreated());
    }

    @Test
    @DisplayName("the ticket is answered once, to the submitter, and marked not to be stored on the way")
    void the_submission_carries_the_ticket() throws Exception {
        OnboardingService submitting = mock(OnboardingService.class);
        when(submitting.submit(any(), anyString(), anyString(), anyString(), anyString(),
                any(), any(), any(), any(), any()))
                .thenReturn(new ApplicationIntake.Recorded(nadia, nadiasTicket));
        MockMvc open = MockMvcBuilders.standaloneSetup(new OnboardingController(submitting,
                        verifications, mock(PlatformClient.class), mock(CustomerSignUpService.class),
                        mock(ApplicantDocumentService.class), mock(PayoutDetailsService.class),
                        mock(PartnerManagementService.class)))
                .build();

        open.perform(post("/api/onboarding/applications")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"kind\":\"RIDER\",\"businessName\":\"Nadia Haddad\","
                                + "\"contactName\":\"Nadia Haddad\",\"contactEmail\":\"nadia@example.test\","
                                + "\"emailVerificationToken\":\"proof\",\"targetProviderId\":\""
                                + company + "\"}"))
                .andExpect(status().isCreated())
                .andExpect(header().string("Cache-Control", "no-store"))
                .andExpect(jsonPath("$.reference").value(nadia.getReference()))
                .andExpect(jsonPath("$.accountTicket").value(nadiasTicket));

        // The receipt anybody holding the reference can read never carries it.
        when(submitting.byReference(nadia.getReference())).thenReturn(Optional.of(nadia));
        open.perform(get("/api/onboarding/applications/by-reference/{reference}", nadia.getReference()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.accountTicket").doesNotExist());
    }
}
