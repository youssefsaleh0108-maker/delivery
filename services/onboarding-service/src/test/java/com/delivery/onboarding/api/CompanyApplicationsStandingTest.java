package com.delivery.onboarding.api;

import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import com.delivery.onboarding.client.PlatformClient;
import com.delivery.onboarding.domain.OnboardingApplication;
import com.delivery.onboarding.domain.OnboardingApplication.Kind;
import com.delivery.onboarding.service.ApplicantDocumentService;
import com.delivery.onboarding.service.CustomerSignUpService;
import com.delivery.onboarding.service.OnboardingService;
import com.delivery.onboarding.service.PartnerManagementService;
import com.delivery.onboarding.service.PayoutDetailsService;
import com.delivery.onboarding.service.VerificationService;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * A delivery company's applications listing carries each rider's standing — read in one query, and
 * only for a company the caller runs.
 *
 * <p>The carrier's Riders HR directory used to follow this listing with one standing request per
 * rider: over eighty requests for a fleet of forty on every load, straight into the gateway's
 * per-address rate limit, which the page then drew as nobody being suspended.
 */
@DisplayName("a company's applications listing, with each rider's standing")
class CompanyApplicationsStandingTest {

    private static final String OWNER = "keycloak-sub-owner";

    private OnboardingService onboarding;
    private PlatformClient platform;
    private PartnerManagementService partners;
    private MockMvc mvc;

    private final UUID myCompany = UUID.randomUUID();
    private final UUID rivalCompany = UUID.randomUUID();

    @BeforeEach
    void setUp() {
        onboarding = mock(OnboardingService.class);
        platform = mock(PlatformClient.class);
        partners = mock(PartnerManagementService.class);
        mvc = MockMvcBuilders.standaloneSetup(new OnboardingController(
                        onboarding, mock(VerificationService.class), platform,
                        mock(CustomerSignUpService.class), mock(ApplicantDocumentService.class),
                        mock(PayoutDetailsService.class), partners))
                .build();

        when(platform.isStaffOf(myCompany, OWNER)).thenReturn(true);
        when(platform.isStaffOf(rivalCompany, OWNER)).thenReturn(false);

        Jwt jwt = Jwt.withTokenValue("token").header("alg", "none").subject(OWNER).build();
        SecurityContextHolder.getContext().setAuthentication(new JwtAuthenticationToken(jwt, List.of()));
    }

    @AfterEach
    void tearDown() {
        SecurityContextHolder.clearContext();
    }

    private OnboardingApplication rider(String name) {
        return new OnboardingApplication(Kind.RIDER, name, name, "rider@example.test",
                Instant.now(), null, null, null, null, myCompany);
    }

    @Test
    @DisplayName("every application on the listing says whether its partner is suspended")
    void the_listing_carries_the_standing() throws Exception {
        OnboardingApplication suspended = rider("Nadia Haddad");
        OnboardingApplication active = rider("Karim Aoun");
        when(onboarding.allFor(myCompany)).thenReturn(List.of(suspended, active));
        when(partners.suspendedByApplication(List.of(suspended.getId(), active.getId())))
                .thenReturn(Map.of(suspended.getId(), true, active.getId(), false));

        mvc.perform(get("/api/onboarding/applications/for-company/{providerId}", myCompany)
                        .param("all", "true"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].suspended").value(true))
                .andExpect(jsonPath("$[1].suspended").value(false));

        // One read for the whole listing, never one per application.
        verify(partners).suspendedByApplication(List.of(suspended.getId(), active.getId()));
        verify(partners, never()).standing(any());
    }

    @Test
    @DisplayName("a company the caller does not run is refused, and no standing is read for it")
    void another_company_is_refused() throws Exception {
        mvc.perform(get("/api/onboarding/applications/for-company/{providerId}", rivalCompany)
                        .param("all", "true"))
                .andExpect(status().isForbidden());

        verifyNoInteractions(partners);
        verify(onboarding, never()).allFor(any());
    }
}
