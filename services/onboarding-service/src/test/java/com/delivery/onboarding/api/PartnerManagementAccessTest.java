package com.delivery.onboarding.api;

import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import com.delivery.onboarding.client.PlatformClient;
import com.delivery.onboarding.domain.OnboardingApplication;
import com.delivery.onboarding.domain.OnboardingApplication.Kind;
import com.delivery.onboarding.domain.PartnerStatusChange;
import com.delivery.onboarding.service.OnboardingService;
import com.delivery.onboarding.service.PartnerManagementService;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * A carrier reaches the standing of their own riders and nobody else's.
 *
 * <p>Suspension is the sharpest tool a company holds over a rider, so the ownership chain gets the
 * same from-both-directions treatment as documents: the company id in the URL is checked against
 * Order Manager's staff record, the application id is checked to belong to that company, and only
 * then does anything change. The edit endpoint's contract — blank fields refused, empty audit
 * returned empty — is pinned here too, because the portal builds against these statuses.
 */
class PartnerManagementAccessTest {

    private static final String OWNER = "keycloak-sub-owner";

    private PartnerManagementService partners;
    private OnboardingService onboarding;
    private PlatformClient platform;
    private MockMvc mvc;

    private final UUID myCompany = UUID.randomUUID();
    private final UUID rivalCompany = UUID.randomUUID();
    private OnboardingApplication riderApplication;

    @BeforeEach
    void setUp() {
        partners = mock(PartnerManagementService.class);
        onboarding = mock(OnboardingService.class);
        platform = mock(PlatformClient.class);
        mvc = MockMvcBuilders.standaloneSetup(
                new PartnerManagementController(partners, onboarding, platform)).build();

        riderApplication = new OnboardingApplication(Kind.RIDER, "Rider", "Riding Rida",
                "rida@example.test", Instant.now(), null, null, null, null, myCompany);

        when(platform.isStaffOf(myCompany, OWNER)).thenReturn(true);
        when(platform.isStaffOf(rivalCompany, OWNER)).thenReturn(false);
        when(onboarding.requireBelongsTo(riderApplication.getId(), myCompany))
                .thenReturn(riderApplication);
    }

    @AfterEach
    void tearDown() {
        SecurityContextHolder.clearContext();
    }

    private static void signedInAs(String subject) {
        Jwt jwt = Jwt.withTokenValue("token")
                .header("alg", "none")
                .subject(subject)
                .build();
        SecurityContextHolder.getContext().setAuthentication(
                new JwtAuthenticationToken(jwt, List.of()));
    }

    private static String companyPath(UUID providerId, UUID applicationId, String action) {
        return "/api/onboarding/applications/for-company/" + providerId + "/" + applicationId
                + "/" + action;
    }

    @Nested
    @DisplayName("a company suspending its own rider")
    class CompanySuspension {

        @Test
        void the_owner_can_suspend_a_rider_who_applied_to_their_company() throws Exception {
            when(partners.suspend(eq(riderApplication.getId()), eq(OWNER),
                    eq(PartnerStatusChange.Reason.POLICY_VIOLATION), any()))
                    .thenReturn(PartnerStatusChange.suspension(riderApplication.getId(),
                            "rider-sub", PartnerStatusChange.Reason.POLICY_VIOLATION,
                            null, OWNER));

            signedInAs(OWNER);
            mvc.perform(post(companyPath(myCompany, riderApplication.getId(), "suspend"))
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{\"reason\": \"POLICY_VIOLATION\"}"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.suspended").value(true))
                    .andExpect(jsonPath("$.lastChange.reason").value("POLICY_VIOLATION"));
        }

        /** The company id in the URL is a claim; Order Manager's staff record is the evidence. */
        @Test
        void a_company_the_caller_does_not_run_is_a_403_and_nothing_changes() throws Exception {
            signedInAs(OWNER);
            mvc.perform(post(companyPath(rivalCompany, riderApplication.getId(), "suspend"))
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{\"reason\": \"FRAUD\"}"))
                    .andExpect(status().isForbidden());

            verify(partners, never()).suspend(any(), anyString(), any(), any());
        }

        /** Running A does not reach a rider who applied to B, even with valid ids for both. */
        @Test
        void a_rider_who_applied_elsewhere_is_unreachable_even_from_a_company_you_run()
                throws Exception {
            UUID elsewhereApplication = UUID.randomUUID();
            when(onboarding.requireBelongsTo(elsewhereApplication, myCompany))
                    .thenThrow(new OnboardingService.ApplicationRuleException(
                            "No such application"));

            signedInAs(OWNER);
            mvc.perform(post(companyPath(myCompany, elsewhereApplication, "suspend"))
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{\"reason\": \"FRAUD\"}"))
                    .andExpect(status().isUnprocessableEntity());

            verify(partners, never()).suspend(any(), anyString(), any(), any());
        }

        @Test
        void a_suspension_without_a_typed_reason_is_a_400() throws Exception {
            signedInAs(OWNER);
            mvc.perform(post(companyPath(myCompany, riderApplication.getId(), "suspend"))
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{\"note\": \"no reason given\"}"))
                    .andExpect(status().isBadRequest());

            verify(partners, never()).suspend(any(), anyString(), any(), any());
        }

        @Test
        void reinstating_takes_no_body_at_all() throws Exception {
            when(partners.unsuspend(eq(riderApplication.getId()), eq(OWNER), any()))
                    .thenReturn(Optional.of(PartnerStatusChange.reinstatement(
                            riderApplication.getId(), "rider-sub", null, OWNER)));

            signedInAs(OWNER);
            mvc.perform(post(companyPath(myCompany, riderApplication.getId(), "unsuspend")))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.suspended").value(false));
        }
    }

    @Nested
    @DisplayName("the backoffice edit contract")
    class Editing {

        @Test
        void an_edit_reports_the_updated_record() throws Exception {
            OnboardingApplication merchant = new OnboardingApplication(Kind.MERCHANT,
                    "Sam's Diner", "Sam Salem", "sam@example.test", Instant.now(),
                    null, null, null, null, null);
            when(partners.edit(eq(merchant.getId()), anyString(), any())).thenReturn(merchant);

            signedInAs("backoffice-1");
            mvc.perform(patch("/api/onboarding/applications/{id}", merchant.getId())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{\"businessName\": \"Sam's Diner\"}"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.businessName").value("Sam's Diner"));
        }

        /** There is no way to blank a field: none of these is optional on a live partner record. */
        @Test
        void a_whitespace_only_field_is_refused_before_the_service_is_asked() throws Exception {
            signedInAs("backoffice-1");
            mvc.perform(patch("/api/onboarding/applications/{id}", UUID.randomUUID())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{\"businessName\": \"   \"}"))
                    .andExpect(status().isUnprocessableEntity());

            verify(partners, never()).edit(any(), anyString(), any());
        }

        @Test
        void an_audit_of_an_untouched_record_is_an_empty_list_not_an_invented_one() throws Exception {
            UUID id = UUID.randomUUID();
            when(partners.editsOf(id)).thenReturn(List.of());

            signedInAs("backoffice-1");
            mvc.perform(get("/api/onboarding/applications/{id}/audit", id))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.length()").value(0));
        }
    }
}
