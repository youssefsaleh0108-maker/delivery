package com.delivery.onboarding.service;

import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import com.delivery.onboarding.domain.ApplicantDocument;
import com.delivery.onboarding.domain.ApplicantDocumentRepository;
import com.delivery.onboarding.domain.DocumentKind;
import com.delivery.onboarding.domain.OnboardingApplication;
import com.delivery.onboarding.domain.OnboardingApplication.Kind;
import com.delivery.platform.storage.FileMetadata;
import com.delivery.platform.storage.FileMetadataRepository;
import com.delivery.platform.storage.FilePurpose;
import com.delivery.platform.storage.PresignedUpload;
import com.delivery.platform.storage.StorageService;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatExceptionOfType;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

/**
 * Uploading, replacing and deciding one applicant's identity documents.
 *
 * <p>The three guarantees worth holding here are all about what the bytes are allowed to be and
 * where they are allowed to land: a document only ever goes to the private KYC bucket, a
 * replacement never leaves two current versions of the same paper, and a decision on a document is
 * made once and stays on the record.
 */
class ApplicantDocumentServiceTest {

    private static final String APPLICANT = "keycloak-sub-sam";

    private ApplicantDocumentRepository repository;
    private StorageService storage;
    private FileMetadataRepository files;
    private ApplicantDocumentService service;

    private OnboardingApplication riderApplication;

    @BeforeEach
    void setUp() {
        repository = mock(ApplicantDocumentRepository.class);
        storage = mock(StorageService.class);
        files = mock(FileMetadataRepository.class);
        service = new ApplicantDocumentService(repository, storage, files,
                Set.of("image/jpeg", "image/png", "application/pdf"));

        riderApplication = new OnboardingApplication(Kind.RIDER, "Sam Salem", "Sam Salem",
                "sam@example.test", Instant.now(), null, null, null, null, null);
    }

    private FileMetadata landedFile(UUID applicationId, String contentType) {
        return new FileMetadata(FilePurpose.MERCHANT_KYC.bucket(),
                "applications/" + applicationId + "/" + UUID.randomUUID() + ".jpg",
                APPLICANT, contentType, FilePurpose.MERCHANT_KYC);
    }

    @Nested
    @DisplayName("asking for somewhere to upload to")
    class Presigning {

        @Test
        @DisplayName("puts the object in the private KYC bucket, under the applicant's own application")
        void presigns_into_the_kyc_bucket_under_the_application() {
            when(storage.presignUpload(anyString(), any(), anyString(), anyString()))
                    .thenReturn(new PresignedUpload(UUID.randomUUID(), "https://minio/put",
                            "key", "merchant-kyc", "image/jpeg", Instant.now(), 1L));

            service.presign(riderApplication, APPLICANT, DocumentKind.DRIVING_LICENCE, "image/jpeg");

            // MERCHANT_KYC is chosen here and never passed in — it is what binds these objects to a
            // bucket with no public read policy, which is the whole basis of the presigned-only rule.
            verify(storage).presignUpload(eq(APPLICANT), eq(FilePurpose.MERCHANT_KYC),
                    eq("image/jpeg"), eq("applications/" + riderApplication.getId()));
        }

        @Test
        @DisplayName("refuses a document the applicant's kind is never asked for, before any URL exists")
        void refuses_a_document_that_does_not_belong_to_this_kind_of_applicant() {
            assertThatExceptionOfType(ApplicantDocumentService.DocumentRuleException.class)
                    .isThrownBy(() -> service.presign(riderApplication, APPLICANT,
                            DocumentKind.COMMERCIAL_REGISTRATION, "image/jpeg"))
                    .withMessageContaining("does not ask for");

            // No write access to anything in the KYC bucket was handed out while working out that
            // the request made no sense.
            verifyNoInteractions(storage);
        }

        @Test
        @DisplayName("refuses a file type that is not a photo or a PDF")
        void refuses_an_unsupported_file_type() {
            assertThatExceptionOfType(ApplicantDocumentService.DocumentRuleException.class)
                    .isThrownBy(() -> service.presign(riderApplication, APPLICANT,
                            DocumentKind.NATIONAL_ID, "image/svg+xml"))
                    .withMessageContaining("photo or a PDF");

            verifyNoInteractions(storage);
        }

        @Test
        @DisplayName("refuses once the application has been decided, so the evidence cannot change afterwards")
        void refuses_after_a_decision() {
            riderApplication.approve("reviewer-1");

            assertThatExceptionOfType(ApplicantDocumentService.DocumentRuleException.class)
                    .isThrownBy(() -> service.presign(riderApplication, APPLICANT,
                            DocumentKind.NATIONAL_ID, "image/jpeg"))
                    .withMessageContaining("already been decided");
        }
    }

    @Nested
    @DisplayName("confirming that the bytes landed")
    class Confirming {

        @Test
        @DisplayName("records the document against the application the upload was presigned for")
        void records_the_document() {
            FileMetadata metadata = landedFile(riderApplication.getId(), "image/jpeg");
            when(storage.confirmUpload(metadata.getId(), APPLICANT)).thenReturn(metadata);
            when(repository.findByApplicationIdAndKindAndSupersededAtIsNull(any(), any()))
                    .thenReturn(Optional.empty());

            ApplicantDocument document = service.confirm(riderApplication, APPLICANT,
                    metadata.getId(), DocumentKind.NATIONAL_ID);

            assertThat(document.getApplicationId()).isEqualTo(riderApplication.getId());
            assertThat(document.getKind()).isEqualTo(DocumentKind.NATIONAL_ID);
            assertThat(document.getStatus()).isEqualTo(ApplicantDocument.Status.PENDING);
            verify(repository).save(document);
        }

        /**
         * The gap the object-key check closes: a caller who legitimately presigned against one
         * application cannot then confirm the same file against another, which is reachable for
         * anybody who has held two applications.
         */
        @Test
        @DisplayName("refuses a file that was presigned for a different application")
        void refuses_a_file_presigned_for_another_application() {
            FileMetadata elsewhere = landedFile(UUID.randomUUID(), "image/jpeg");
            when(storage.confirmUpload(elsewhere.getId(), APPLICANT)).thenReturn(elsewhere);

            assertThatExceptionOfType(ApplicantDocumentService.DocumentRuleException.class)
                    .isThrownBy(() -> service.confirm(riderApplication, APPLICANT,
                            elsewhere.getId(), DocumentKind.NATIONAL_ID))
                    .withMessageContaining("not started for this application");

            verify(repository, never()).save(any());
        }

        @Test
        @DisplayName("supersedes the previous version rather than overwriting it, so the old verdict survives")
        void a_replacement_supersedes_the_previous_upload() {
            ApplicantDocument previous = new ApplicantDocument(riderApplication.getId(),
                    DocumentKind.DRIVING_LICENCE, UUID.randomUUID(), "old-key", "image/jpeg");
            previous.reject("reviewer-1", "Too blurred to read", null);

            FileMetadata replacement = landedFile(riderApplication.getId(), "image/jpeg");
            when(storage.confirmUpload(replacement.getId(), APPLICANT)).thenReturn(replacement);
            when(repository.findByApplicationIdAndKindAndSupersededAtIsNull(
                    riderApplication.getId(), DocumentKind.DRIVING_LICENCE))
                    .thenReturn(Optional.of(previous));

            ApplicantDocument current = service.confirm(riderApplication, APPLICANT,
                    replacement.getId(), DocumentKind.DRIVING_LICENCE);

            assertThat(previous.isLive()).isFalse();
            // The refusal and its reason are still readable on the superseded row — which is what
            // makes "why was this rejected three times" answerable later.
            assertThat(previous.getStatus()).isEqualTo(ApplicantDocument.Status.REJECTED);
            assertThat(previous.getRejectionReason()).isEqualTo("Too blurred to read");

            assertThat(current.isLive()).isTrue();
            assertThat(current.getStatus()).isEqualTo(ApplicantDocument.Status.PENDING);
            // Flushed before the insert, or the partial unique index refuses the very upload the
            // supersede was performed to make room for.
            verify(repository).flush();
        }
    }

    @Nested
    @DisplayName("a reviewer's verdict")
    class Reviewing {

        @Test
        @DisplayName("records who reached it and when, and refuses a rejection with no reason")
        void records_who_and_when() {
            ApplicantDocument document = new ApplicantDocument(riderApplication.getId(),
                    DocumentKind.NATIONAL_ID, UUID.randomUUID(), "key", "image/jpeg");
            when(repository.findByIdAndApplicationId(document.getId(), riderApplication.getId()))
                    .thenReturn(Optional.of(document));

            service.approve(riderApplication.getId(), document.getId(), "reviewer-1", "clear scan");

            assertThat(document.getStatus()).isEqualTo(ApplicantDocument.Status.APPROVED);
            assertThat(document.getReviewedBy()).isEqualTo("reviewer-1");
            assertThat(document.getReviewedAt()).isNotNull();
            assertThat(document.getReviewerNote()).isEqualTo("clear scan");
        }

        @Test
        @DisplayName("cannot be reached twice, so an audit trail never describes a decision nobody took")
        void cannot_be_reached_twice() {
            ApplicantDocument document = new ApplicantDocument(riderApplication.getId(),
                    DocumentKind.NATIONAL_ID, UUID.randomUUID(), "key", "image/jpeg");
            document.approve("reviewer-1", null);
            when(repository.findByIdAndApplicationId(document.getId(), riderApplication.getId()))
                    .thenReturn(Optional.of(document));

            assertThatExceptionOfType(ApplicantDocumentService.DocumentRuleException.class)
                    .isThrownBy(() -> service.reject(riderApplication.getId(), document.getId(),
                            "reviewer-2", "changed my mind", null))
                    .withMessageContaining("already approved");
        }

        @Test
        @DisplayName("is refused on a version that has already been replaced")
        void is_refused_on_a_superseded_version() {
            ApplicantDocument old = new ApplicantDocument(riderApplication.getId(),
                    DocumentKind.NATIONAL_ID, UUID.randomUUID(), "key", "image/jpeg");
            old.supersede();
            when(repository.findByIdAndApplicationId(old.getId(), riderApplication.getId()))
                    .thenReturn(Optional.of(old));

            assertThatExceptionOfType(ApplicantDocumentService.DocumentRuleException.class)
                    .isThrownBy(() -> service.approve(riderApplication.getId(), old.getId(),
                            "reviewer-1", null))
                    .withMessageContaining("replaced by a newer upload");
        }
    }

    /**
     * The allow-list is configured as a comma-separated property and injected as a {@code Set}.
     *
     * <p>Worth a test because the failure mode is a service that will not start, discovered at
     * deploy time rather than here: the conversion below is exactly what {@code @Value} performs,
     * and it only works while the property stays a scalar. Written as a YAML list instead, the
     * placeholder resolves to nothing and the bean cannot be constructed.
     */
    @Test
    @DisplayName("is configured as a comma-separated property that Spring can bind to a Set")
    void the_configured_allow_list_binds() {
        Set<String> bound = new org.springframework.core.convert.support.DefaultConversionService()
                .convert("image/jpeg,image/png,image/webp,application/pdf",
                        org.springframework.core.convert.TypeDescriptor.valueOf(String.class),
                        org.springframework.core.convert.TypeDescriptor.collection(
                                Set.class,
                                org.springframework.core.convert.TypeDescriptor.valueOf(String.class)))
                instanceof Set<?> set ? castToStrings(set) : Set.of();

        assertThat(bound).containsExactlyInAnyOrder(
                "image/jpeg", "image/png", "image/webp", "application/pdf");
    }

    @SuppressWarnings("unchecked")
    private static Set<String> castToStrings(Set<?> set) {
        return (Set<String>) set;
    }

    @Nested
    @DisplayName("what is outstanding on an application")
    class Outstanding {

        @Test
        @DisplayName("names every live document that is not approved, and nothing else")
        void names_the_live_documents_that_are_not_approved() {
            ApplicantDocument approved = document(DocumentKind.NATIONAL_ID);
            approved.approve("reviewer-1", null);
            ApplicantDocument rejected = document(DocumentKind.DRIVING_LICENCE);
            rejected.reject("reviewer-1", "Too blurred", null);
            ApplicantDocument pending = document(DocumentKind.VEHICLE_REGISTRATION);

            when(repository.findByApplicationIdAndSupersededAtIsNullOrderByKindAsc(
                    riderApplication.getId()))
                    .thenReturn(List.of(approved, rejected, pending));

            assertThat(service.outstandingSummary(riderApplication.getId()))
                    .isEqualTo("DRIVING_LICENCE=REJECTED, VEHICLE_REGISTRATION=PENDING");
        }

        @Test
        @DisplayName("is null when every document was approved, and when there were none at all")
        void is_null_when_there_is_nothing_to_say() {
            ApplicantDocument approved = document(DocumentKind.NATIONAL_ID);
            approved.approve("reviewer-1", null);

            when(repository.findByApplicationIdAndSupersededAtIsNullOrderByKindAsc(
                    riderApplication.getId()))
                    .thenReturn(List.of(approved), List.of());

            assertThat(service.outstandingSummary(riderApplication.getId())).isNull();
            assertThat(service.outstandingSummary(riderApplication.getId())).isNull();
        }

        private ApplicantDocument document(DocumentKind kind) {
            return new ApplicantDocument(riderApplication.getId(), kind, UUID.randomUUID(),
                    "key-" + kind, "image/jpeg");
        }
    }
}
