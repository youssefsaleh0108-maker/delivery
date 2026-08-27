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
import com.delivery.onboarding.domain.ApplicantDocument;
import com.delivery.onboarding.domain.DocumentKind;
import com.delivery.onboarding.domain.OnboardingApplication;
import com.delivery.onboarding.domain.OnboardingApplication.Kind;
import com.delivery.onboarding.service.ApplicantDocumentService;
import com.delivery.onboarding.service.CustomerSignUpService;
import com.delivery.onboarding.service.OnboardingService;
import com.delivery.onboarding.service.PayoutDetailsService;
import com.delivery.onboarding.service.VerificationService;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * An applicant reaches their own identity documents and nobody else's.
 *
 * <p>These are scans of national ids and driving licences, so the guarantee is worth testing from
 * both directions. The applicant-facing API is addressed as {@code /applications/mine} and takes no
 * application id at all — so the test is not "the id is checked", it is "there is no id to tamper
 * with, and the application is resolved from the token every time". Underneath, the repository
 * lookup for a single document is scoped by application in the query rather than filtered after
 * loading, so the same guarantee holds for the reviewer paths that legitimately do take ids.
 */
class ApplicantDocumentAccessTest {

    private OnboardingService onboarding;
    private ApplicantDocumentService documents;
    private PayoutDetailsService payouts;
    private MockMvc mvc;

    /** Two applicants, each with their own application and their own papers. */
    private static final String SAM = "keycloak-sub-sam";
    private static final String ALEX = "keycloak-sub-alex";

    private OnboardingApplication samsApplication;
    private OnboardingApplication alexsApplication;

    @BeforeEach
    void setUp() {
        onboarding = mock(OnboardingService.class);
        documents = mock(ApplicantDocumentService.class);
        payouts = mock(PayoutDetailsService.class);
        mvc = MockMvcBuilders.standaloneSetup(new OnboardingController(
                        onboarding, mock(VerificationService.class), mock(PlatformClient.class),
                        mock(CustomerSignUpService.class), documents, payouts))
                .build();

        samsApplication = application(Kind.RIDER);
        alexsApplication = application(Kind.RIDER);

        when(onboarding.forApplicant(SAM)).thenReturn(Optional.of(samsApplication));
        when(onboarding.forApplicant(ALEX)).thenReturn(Optional.of(alexsApplication));
    }

    @AfterEach
    void tearDown() {
        SecurityContextHolder.clearContext();
    }

    private static OnboardingApplication application(Kind kind) {
        return new OnboardingApplication(kind, "Sam's Shakes", "Sam Salem", "sam@example.test",
                Instant.now(), null, null, null, null, null);
    }

    /** Signs the request as this Keycloak subject, the way a real token would. */
    private static void signedInAs(String subject) {
        Jwt jwt = Jwt.withTokenValue("token")
                .header("alg", "none")
                .subject(subject)
                .claim("preferred_username", subject)
                .build();
        SecurityContextHolder.getContext().setAuthentication(
                new JwtAuthenticationToken(jwt, List.of()));
    }

    private static ApplicantDocument document(UUID applicationId, DocumentKind kind) {
        return new ApplicantDocument(applicationId, kind, UUID.randomUUID(),
                "applications/" + applicationId + "/" + UUID.randomUUID() + ".jpg", "image/jpeg");
    }

    @Nested
    @DisplayName("listing documents")
    class Listing {

        @Test
        @DisplayName("returns the caller's own, resolved from their token and not from any id they sent")
        void returns_only_the_callers_own() throws Exception {
            ApplicantDocument sams = document(samsApplication.getId(), DocumentKind.NATIONAL_ID);
            when(documents.liveFor(samsApplication.getId())).thenReturn(List.of(sams));
            when(documents.viewUrl(any())).thenReturn(Optional.of("https://minio/presigned"));

            signedInAs(SAM);
            mvc.perform(get("/api/onboarding/applications/mine/documents"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.length()").value(1))
                    .andExpect(jsonPath("$[0].id").value(sams.getId().toString()));

            // The load was scoped to Sam's application. Alex's was never asked for, because the
            // request had no way to name it.
            verify(documents).liveFor(samsApplication.getId());
            verify(documents, never()).liveFor(alexsApplication.getId());
        }

        @Test
        @DisplayName("shows a different applicant an entirely different set on the identical URL")
        void the_same_url_answers_differently_per_caller() throws Exception {
            ApplicantDocument alexs = document(alexsApplication.getId(), DocumentKind.NATIONAL_ID);
            when(documents.liveFor(samsApplication.getId()))
                    .thenReturn(List.of(document(samsApplication.getId(), DocumentKind.NATIONAL_ID)));
            when(documents.liveFor(alexsApplication.getId())).thenReturn(List.of(alexs));

            signedInAs(ALEX);
            mvc.perform(get("/api/onboarding/applications/mine/documents"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$[0].id").value(alexs.getId().toString()));
        }

        @Test
        @DisplayName("never carries the reviewer's internal note")
        void never_carries_a_reviewers_internal_note() throws Exception {
            ApplicantDocument rejected = document(samsApplication.getId(), DocumentKind.DRIVING_LICENCE);
            rejected.reject("reviewer-1", "The photograph is too blurred to read",
                    "Third attempt — escalate if the next one is no better");
            when(documents.liveFor(samsApplication.getId())).thenReturn(List.of(rejected));

            signedInAs(SAM);
            mvc.perform(get("/api/onboarding/applications/mine/documents"))
                    .andExpect(status().isOk())
                    // The reason is theirs to see: they cannot fix what they are not told about.
                    .andExpect(jsonPath("$[0].rejectionReason")
                            .value("The photograph is too blurred to read"))
                    // The note is not, and there is no field on this shape to put it in.
                    .andExpect(jsonPath("$[0].reviewerNote").doesNotExist())
                    .andExpect(jsonPath("$[0].reviewedBy").doesNotExist());
        }

        @Test
        @DisplayName("is a 404, not somebody else's list, when the caller has no application")
        void is_a_404_when_the_caller_has_no_application() throws Exception {
            when(onboarding.forApplicant("stranger")).thenReturn(Optional.empty());

            signedInAs("stranger");
            mvc.perform(get("/api/onboarding/applications/mine/documents"))
                    .andExpect(status().isNotFound());

            verify(documents, never()).liveFor(any());
        }
    }

    @Nested
    @DisplayName("uploading")
    class Uploading {

        @Test
        @DisplayName("presigns against the caller's own application and their own Keycloak subject")
        void presigns_against_the_callers_own_application() throws Exception {
            when(documents.presign(any(), any(), any(), any())).thenReturn(
                    new com.delivery.platform.storage.PresignedUpload(
                            UUID.randomUUID(), "https://minio/put", "applications/x/y.jpg",
                            "merchant-kyc", "image/jpeg", Instant.now(), 10_485_760L));

            signedInAs(SAM);
            mvc.perform(post("/api/onboarding/applications/mine/documents/presign")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{\"kind\":\"NATIONAL_ID\",\"contentType\":\"image/jpeg\"}"))
                    .andExpect(status().isCreated());

            // Both arguments come from the token, never from the request body: the application Sam
            // owns, and the subject the object will be owned by.
            verify(documents).presign(eq(samsApplication), eq(SAM),
                    eq(DocumentKind.NATIONAL_ID), eq("image/jpeg"));
        }

        @Test
        @DisplayName("confirms an upload against the caller's own application, whatever file id was sent")
        void confirms_against_the_callers_own_application() throws Exception {
            UUID fileId = UUID.randomUUID();
            when(documents.confirm(any(), any(), any(), any()))
                    .thenReturn(document(samsApplication.getId(), DocumentKind.NATIONAL_ID));

            signedInAs(SAM);
            mvc.perform(post("/api/onboarding/applications/mine/documents/{fileId}/confirm", fileId)
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{\"kind\":\"NATIONAL_ID\"}"))
                    .andExpect(status().isCreated());

            // A file id is the one identifier this endpoint accepts, and it is checked against the
            // caller's ownership inside the service — never against an application id they chose.
            verify(documents).confirm(eq(samsApplication), eq(SAM), eq(fileId),
                    eq(DocumentKind.NATIONAL_ID));
        }
    }

    @Nested
    @DisplayName("payout details")
    class Payout {

        @Test
        @DisplayName("are read back for the caller's own application only")
        void are_read_back_for_the_callers_own_application_only() throws Exception {
            when(payouts.forApplication(samsApplication.getId())).thenReturn(Optional.empty());

            signedInAs(SAM);
            mvc.perform(get("/api/onboarding/applications/mine/payout"))
                    .andExpect(status().isNotFound());

            verify(payouts).forApplication(samsApplication.getId());
            verify(payouts, never()).forApplication(alexsApplication.getId());
        }
    }

    /**
     * The other half of the guarantee, one layer down.
     *
     * <p>The reviewer endpoints do take an application id and a document id, both from the URL. The
     * lookup is scoped by both in the query rather than fetched by id and compared afterwards —
     * which is the same check on a good day and a data leak on the day somebody deletes the
     * comparison. This pins the scoping so that a later refactor to {@code findById} fails here.
     */
    @Nested
    @DisplayName("a document fetched by id")
    class ScopedLookup {

        @Test
        @DisplayName("is looked up scoped to its application, and is absent when it belongs to another")
        void is_scoped_to_its_application() {
            com.delivery.onboarding.domain.ApplicantDocumentRepository repository =
                    mock(com.delivery.onboarding.domain.ApplicantDocumentRepository.class);
            ApplicantDocumentService service = new ApplicantDocumentService(
                    repository,
                    mock(com.delivery.platform.storage.StorageService.class),
                    mock(com.delivery.platform.storage.FileMetadataRepository.class),
                    java.util.Set.of("image/jpeg"));

            ApplicantDocument alexs = document(alexsApplication.getId(), DocumentKind.NATIONAL_ID);
            // The repository answers only for the pair it was asked about. Sam's application with
            // Alex's document id is not a pair, so it finds nothing.
            when(repository.findByIdAndApplicationId(alexs.getId(), alexsApplication.getId()))
                    .thenReturn(Optional.of(alexs));
            when(repository.findByIdAndApplicationId(alexs.getId(), samsApplication.getId()))
                    .thenReturn(Optional.empty());

            assertThat(service.require(alexsApplication.getId(), alexs.getId())).isEqualTo(alexs);

            org.assertj.core.api.Assertions.assertThatExceptionOfType(
                            ApplicantDocumentService.DocumentRuleException.class)
                    .isThrownBy(() -> service.require(samsApplication.getId(), alexs.getId()))
                    // Deliberately the same wording as a document that never existed: which
                    // documents another applicant uploaded is not something to confirm by guessing.
                    .withMessage("No such document");
        }
    }

    /** Kept honest: the masked and full payout shapes are different records, not one with a flag. */
    @Nested
    @DisplayName("a listing")
    class Listings {

        @Test
        @DisplayName("shows the last four digits of an account number and never the whole one")
        void masks_the_account_number() {
            com.delivery.onboarding.domain.PayoutDetails details =
                    new com.delivery.onboarding.domain.PayoutDetails(
                            UUID.randomUUID(), "Sam Salem",
                            com.delivery.onboarding.domain.Iban.parse("EG380019000500000000263180002"));

            OnboardingController.PayoutSummary summary =
                    OnboardingController.PayoutSummary.of(details);

            assertThat(summary.maskedIban()).isEqualTo("EG••••0002");
            assertThat(summary.maskedIban()).doesNotContain("EG380019000500000000263180002");
            // Nothing on the summary can hold the full number, whatever anybody later assigns.
            assertThat(OnboardingController.PayoutSummary.class.getRecordComponents())
                    .extracting(java.lang.reflect.RecordComponent::getName)
                    .containsExactly("accountHolder", "maskedIban", "verificationState");
        }
    }
}
