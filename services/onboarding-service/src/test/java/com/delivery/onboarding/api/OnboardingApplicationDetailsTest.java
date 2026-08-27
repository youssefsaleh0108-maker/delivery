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
import com.delivery.onboarding.domain.ApplicantDocument;
import com.delivery.onboarding.domain.DocumentKind;
import com.delivery.onboarding.domain.Iban;
import com.delivery.onboarding.domain.OnboardingApplication;
import com.delivery.onboarding.domain.OnboardingApplication.Kind;
import com.delivery.onboarding.domain.PayoutDetails;
import com.delivery.onboarding.service.ApplicantDocumentService;
import com.delivery.onboarding.service.CustomerSignUpService;
import com.delivery.onboarding.service.OnboardingService;
import com.delivery.onboarding.service.PayoutDetailsService;
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

    private ApplicantDocumentService documents;
    private PayoutDetailsService payouts;

    @BeforeEach
    void setUp() {
        onboarding = mock(OnboardingService.class);
        documents = mock(ApplicantDocumentService.class);
        payouts = mock(PayoutDetailsService.class);
        mvc = MockMvcBuilders.standaloneSetup(new OnboardingController(
                        onboarding, mock(VerificationService.class),
                        mock(PlatformClient.class), mock(CustomerSignUpService.class),
                        documents, payouts))
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

    /**
     * The same guarantee as {@code the_unauthenticated_receipt_does_not_leak_them}, extended to the
     * two things the redesigned wizards added after the {@code details} column: uploaded documents
     * and payout details.
     *
     * <p>Worth its own block because the reasoning is the same but the stakes are higher. The
     * reference is 160 random bits handed to one person — and then, in practice, forwarded: pasted
     * into a support thread, screenshotted, kept in a browser history. Everything the receipt
     * carries is readable by whoever ends up holding it, which is why the receipt is a fixed record
     * with no room in it for a bank account, a national id, or a URL that opens one.
     */
    @Nested
    @DisplayName("the unauthenticated receipt")
    class Receipt {

        @Test
        @DisplayName("carries no documents, no matter what was uploaded against the application")
        void carries_no_documents() throws Exception {
            OnboardingApplication application = application(WIZARD_DETAILS);
            when(onboarding.byReference("ref-1")).thenReturn(java.util.Optional.of(application));

            ApplicantDocument licence = new ApplicantDocument(application.getId(),
                    DocumentKind.DRIVING_LICENCE, UUID.randomUUID(),
                    "applications/" + application.getId() + "/scan.jpg", "image/jpeg");
            when(documents.liveFor(application.getId())).thenReturn(java.util.List.of(licence));

            mvc.perform(get("/api/onboarding/applications/by-reference/{reference}", "ref-1"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.documents").doesNotExist())
                    // Above all: nothing that would open the object. A presigned URL in a receipt
                    // that gets forwarded is somebody's driving licence in a chat thread.
                    .andExpect(jsonPath("$..viewUrl").doesNotExist())
                    .andExpect(jsonPath("$..objectKey").doesNotExist());

            // And the receipt does not even ask: an endpoint that loaded documents in order to
            // leave them out is one careless field away from putting them back in.
            verifyNoInteractions(documents);
        }

        @Test
        @DisplayName("carries no payout details, masked or otherwise")
        void carries_no_payout_details() throws Exception {
            OnboardingApplication application = application(WIZARD_DETAILS);
            when(onboarding.byReference("ref-2")).thenReturn(java.util.Optional.of(application));
            when(payouts.forApplication(application.getId())).thenReturn(java.util.Optional.of(
                    new PayoutDetails(application.getId(), "Sam Salem",
                            Iban.parse("EG380019000500000000263180002"))));

            mvc.perform(get("/api/onboarding/applications/by-reference/{reference}", "ref-2"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.payout").doesNotExist())
                    .andExpect(jsonPath("$.iban").doesNotExist())
                    .andExpect(jsonPath("$..iban").doesNotExist())
                    .andExpect(jsonPath("$..maskedIban").doesNotExist())
                    .andExpect(jsonPath("$..accountHolder").doesNotExist());

            verifyNoInteractions(payouts);
        }

        /**
         * The whole-body assertion, in case a field is added later that none of the paths above
         * happen to name. The receipt is a closed set: reference, status, business name, kind, when
         * it was submitted, and why it was refused.
         */
        @Test
        @DisplayName("is a closed set of six fields, so nothing new leaks into it by accident")
        void is_a_closed_set_of_fields() throws Exception {
            OnboardingApplication application = application(WIZARD_DETAILS);
            when(onboarding.byReference("ref-3")).thenReturn(java.util.Optional.of(application));

            String body = mvc.perform(
                            get("/api/onboarding/applications/by-reference/{reference}", "ref-3"))
                    .andExpect(status().isOk())
                    .andReturn().getResponse().getContentAsString();

            assertThat(JSON.readTree(body).fieldNames())
                    .toIterable()
                    .containsExactlyInAnyOrder("reference", "status", "businessName", "kind",
                            "submittedAt", "rejectionReason");
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
