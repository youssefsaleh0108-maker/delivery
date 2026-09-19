package com.delivery.onboarding.api;

import java.util.List;
import java.util.UUID;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.orm.ObjectOptimisticLockingFailureException;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import com.delivery.onboarding.client.PlatformClient;
import com.delivery.onboarding.domain.OnboardingApplication;
import com.delivery.onboarding.service.ApplicantDocumentService;
import com.delivery.onboarding.service.CustomerSignUpService;
import com.delivery.onboarding.service.OnboardingService;
import com.delivery.onboarding.service.PartnerManagementService;
import com.delivery.onboarding.service.PayoutDetailsService;
import com.delivery.onboarding.service.VerificationService;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * A write that lost a race on an application is a 409 whichever controller it came through.
 *
 * <p>The answer lived on {@link OnboardingController} alone, so back office correcting a record
 * through {@link PartnerManagementController} while a sign-in was being recorded got a bare 500.
 * Both controllers are driven here with the advice registered the way Spring registers it, scope
 * and all, and both must answer in the one shape the portal and the app already read.
 */
class ApplicationChangedAdviceTest {

    private static final String BACKOFFICE = "backoffice-1";

    private final UUID id = UUID.randomUUID();

    private PartnerManagementService partners;
    private OnboardingService onboarding;

    @BeforeEach
    void setUp() {
        partners = mock(PartnerManagementService.class);
        onboarding = mock(OnboardingService.class);
        Jwt jwt = Jwt.withTokenValue("token").header("alg", "none").subject(BACKOFFICE).build();
        SecurityContextHolder.getContext().setAuthentication(new JwtAuthenticationToken(jwt, List.of()));
    }

    @AfterEach
    void tearDown() {
        SecurityContextHolder.clearContext();
    }

    private static ObjectOptimisticLockingFailureException lostTheRace(UUID id) {
        return new ObjectOptimisticLockingFailureException(OnboardingApplication.class, id);
    }

    @Test
    @DisplayName("back office's PATCH that raced another write is a 409, not a 500")
    void a_partner_record_edit_that_lost_the_race() throws Exception {
        when(partners.edit(eq(id), eq(BACKOFFICE), any())).thenThrow(lostTheRace(id));
        MockMvc mvc = MockMvcBuilders.standaloneSetup(
                        new PartnerManagementController(partners, onboarding, mock(PlatformClient.class)))
                .setControllerAdvice(new ApplicationChangedAdvice())
                .build();

        mvc.perform(patch("/api/onboarding/applications/{id}", id)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"contactEmail\":\"new@example.test\"}"))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("application-changed"))
                .andExpect(jsonPath("$.message").value("This application changed while you were "
                        + "working on it. Open it again to see where it stands."));
    }

    @Test
    @DisplayName("and the review endpoints answer in exactly the shape they always did")
    void a_decision_that_lost_the_race() throws Exception {
        when(onboarding.approve(id, BACKOFFICE, false)).thenThrow(lostTheRace(id));
        MockMvc mvc = MockMvcBuilders.standaloneSetup(new OnboardingController(onboarding,
                        mock(VerificationService.class), mock(PlatformClient.class),
                        mock(CustomerSignUpService.class), mock(ApplicantDocumentService.class),
                        mock(PayoutDetailsService.class), partners))
                .setControllerAdvice(new ApplicationChangedAdvice())
                .build();

        mvc.perform(post("/api/onboarding/applications/{id}/approve", id))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("application-changed"))
                .andExpect(jsonPath("$.message").value("This application changed while you were "
                        + "working on it. Open it again to see where it stands."));
    }
}
