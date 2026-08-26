package com.delivery.onboarding.api;

import java.time.Instant;
import java.util.Map;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import com.delivery.onboarding.client.PlatformClient;
import com.delivery.onboarding.domain.OnboardingApplication;
import com.delivery.onboarding.domain.OnboardingApplication.Kind;
import com.delivery.onboarding.service.CustomerSignUpService;
import com.delivery.onboarding.service.OnboardingService;
import com.delivery.onboarding.service.VerificationService;

import com.fasterxml.jackson.databind.ObjectMapper;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * The free-form {@code details} document the redesigned wizards attach to an application.
 *
 * <p>Three things are worth pinning. It round-trips: what a wizard sends is what the backoffice
 * reads back, key for key, because that document — vehicle, region, IBAN — is what a reviewer
 * decides on. It is optional: applications predating the wizards, and callers that never send it,
 * must keep working unchanged. And it is bounded: size is the only validation, so the one check
 * there is has to actually hold, or this becomes an unauthenticated endpoint accepting unlimited
 * payloads into the database.
 */
class OnboardingApplicationDetailsTest {

    private static final ObjectMapper JSON = new ObjectMapper();

    private OnboardingService onboarding;
    private MockMvc mvc;

    @BeforeEach
    void setUp() {
        onboarding = mock(OnboardingService.class);
        mvc = MockMvcBuilders.standaloneSetup(new OnboardingController(
                        onboarding, mock(VerificationService.class),
                        mock(PlatformClient.class), mock(CustomerSignUpService.class)))
                .build();
    }

    private static final Map<String, Object> WIZARD_DETAILS = Map.of(
            "vehicleType", "MOTORCYCLE",
            "vehiclePlate", "س ص ع 1234",
            "workRegion", "Nasr City",
            "dateOfBirth", "1998-04-12",
            "nationalId", "29804120103456",
            "payout", Map.of("accountHolder", "Sam Salem", "iban", "EG380019000500000000263180002"));

    /** A committed-looking application, as the service layer would hand back. */
    private static OnboardingApplication application(Map<String, Object> details) {
        return new OnboardingApplication(Kind.MERCHANT, "Sam's Shakes", "Sam Salem",
                "sam@example.test", Instant.now(), null, null, "corner shop", details, null);
    }

    private static String requestBody(Map<String, Object> details) throws Exception {
        Map<String, Object> body = new java.util.HashMap<>(Map.of(
                "kind", "MERCHANT",
                "businessName", "Sam's Shakes",
                "contactName", "Sam Salem",
                "contactEmail", "sam@example.test",
                "emailVerificationToken", "proof-token"));
        if (details != null) {
            body.put("details", details);
        }
        return JSON.writeValueAsString(body);
    }

    @Nested
    @DisplayName("submitting with details")
    class WithDetails {

        @Test
        void details_reach_the_service_exactly_as_sent() throws Exception {
            when(onboarding.submit(any(), anyString(), anyString(), anyString(), anyString(),
                    any(), any(), any(), any(), any()))
                    .thenReturn(application(WIZARD_DETAILS));

            mvc.perform(post("/api/onboarding/applications")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(requestBody(WIZARD_DETAILS)))
                    .andExpect(status().isCreated());

            @SuppressWarnings("unchecked")
            ArgumentCaptor<Map<String, Object>> captor = ArgumentCaptor.forClass(Map.class);
            verify(onboarding).submit(eq(Kind.MERCHANT), eq("Sam's Shakes"), eq("Sam Salem"),
                    eq("sam@example.test"), eq("proof-token"), any(), any(), any(),
                    captor.capture(), any());
            assertThat(captor.getValue()).isEqualTo(WIZARD_DETAILS);
        }

        /** The reviewer's half of the round-trip: what was sent is what the portal reads. */
        @Test
        void the_backoffice_detail_endpoint_returns_them() throws Exception {
            OnboardingApplication application = application(WIZARD_DETAILS);
            when(onboarding.byId(any(UUID.class))).thenReturn(java.util.Optional.of(application));

            mvc.perform(get("/api/onboarding/applications/{id}", application.getId()))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.details.vehicleType").value("MOTORCYCLE"))
                    .andExpect(jsonPath("$.details.workRegion").value("Nasr City"))
                    .andExpect(jsonPath("$.details.payout.iban")
                            .value("EG380019000500000000263180002"));
        }

        /**
         * The applicant's receipt is readable by whoever holds the reference — including somebody
         * it was forwarded to — so the IBAN and the national id must not be in it.
         */
        @Test
        void the_unauthenticated_receipt_does_not_leak_them() throws Exception {
            when(onboarding.submit(any(), anyString(), anyString(), anyString(), anyString(),
                    any(), any(), any(), any(), any()))
                    .thenReturn(application(WIZARD_DETAILS));

            mvc.perform(post("/api/onboarding/applications")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(requestBody(WIZARD_DETAILS)))
                    .andExpect(status().isCreated())
                    .andExpect(jsonPath("$.details").doesNotExist());
        }
    }

    @Nested
    @DisplayName("submitting without details")
    class WithoutDetails {

        /** Every caller that predates the wizards keeps working, and the field comes back null. */
        @Test
        void still_works_and_the_view_carries_null() throws Exception {
            OnboardingApplication application = application(null);
            when(onboarding.submit(any(), anyString(), anyString(), anyString(), anyString(),
                    any(), any(), any(), any(), any()))
                    .thenReturn(application);

            mvc.perform(post("/api/onboarding/applications")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(requestBody(null)))
                    .andExpect(status().isCreated());

            when(onboarding.byId(any(UUID.class))).thenReturn(java.util.Optional.of(application));
            mvc.perform(get("/api/onboarding/applications/{id}", application.getId()))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.details").value(org.hamcrest.Matchers.nullValue()));
        }
    }

    @Nested
    @DisplayName("oversized details")
    class Oversized {

        /**
         * 400 and nothing spent: the size check is bean validation, so it fails before the
         * verification tokens are consumed — an applicant refused here can immediately retry with
         * a smaller payload using the same proof.
         */
        @Test
        void are_refused_with_400_before_the_service_is_touched() throws Exception {
            Map<String, Object> oversized = Map.of("blob", "x".repeat(17 * 1024));

            mvc.perform(post("/api/onboarding/applications")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(requestBody(oversized)))
                    .andExpect(status().isBadRequest());

            verifyNoInteractions(onboarding);
        }

        /** The budget itself: just under passes, so the limit is 16KB and not accidentally less. */
        @Test
        void just_under_the_budget_passes() throws Exception {
            when(onboarding.submit(any(), anyString(), anyString(), anyString(), anyString(),
                    any(), any(), any(), any(), any()))
                    .thenReturn(application(null));

            Map<String, Object> nearLimit = Map.of("blob", "x".repeat(15 * 1024));
            mvc.perform(post("/api/onboarding/applications")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(requestBody(nearLimit)))
                    .andExpect(status().isCreated());
        }
    }
}
