package com.delivery.platform.storage;

import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.transaction.annotation.Transactional;

import io.minio.GetObjectArgs;
import io.minio.GetObjectResponse;
import io.minio.GetPresignedObjectUrlArgs;
import io.minio.MinioClient;
import io.minio.RemoveObjectArgs;
import io.minio.StatObjectArgs;
import io.minio.StatObjectResponse;
import io.minio.errors.ErrorResponseException;
import io.minio.http.Method;
import io.minio.messages.ErrorResponse;
import okhttp3.OkHttpClient;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Presigned URLs, and the rules that keep one from becoming a way into somebody else's data.
 *
 * <p>A presigned PUT is an unauthenticated grant of write access to one object key for the length of
 * its TTL. Everything protective about that sits in this class — the key is server-generated, the
 * content type is checked before a URL exists, the size cap is applied after the bytes land, and the
 * owner is checked on both confirm and delete. None of it was covered by a test.
 */
class StorageServiceTest {

    /** The first twelve bytes of a real file of each type. */
    private static final byte[] PNG_HEAD = {(byte) 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0x0D};
    private static final byte[] JPEG_HEAD = {(byte) 0xFF, (byte) 0xD8, (byte) 0xFF, (byte) 0xE0, 0, 0x10,
            'J', 'F', 'I', 'F', 0, 1};
    private static final byte[] PDF_HEAD = "%PDF-1.7\n%âã".getBytes(StandardCharsets.ISO_8859_1);
    private static final byte[] WEBP_HEAD = {'R', 'I', 'F', 'F', 0x24, 0, 0, 0, 'W', 'E', 'B', 'P'};

    private MinioClient internalClient;
    private MinioClient presignClient;
    private FileMetadataRepository repository;
    private StorageProperties properties;
    private StorageService storage;

    @BeforeEach
    void setUp() throws Exception {
        internalClient = mock(MinioClient.class);
        presignClient = mock(MinioClient.class);
        repository = mock(FileMetadataRepository.class);
        properties = new StorageProperties();
        storage = new StorageService(internalClient, presignClient, repository, properties);

        when(presignClient.getPresignedObjectUrl(any(GetPresignedObjectUrlArgs.class)))
                .thenReturn("http://localhost:9010/signed-url");
        when(repository.save(any(FileMetadata.class))).thenAnswer(call -> call.getArgument(0));
    }

    private GetPresignedObjectUrlArgs capturePresign() throws Exception {
        ArgumentCaptor<GetPresignedObjectUrlArgs> captor =
                ArgumentCaptor.forClass(GetPresignedObjectUrlArgs.class);
        verify(presignClient).getPresignedObjectUrl(captor.capture());
        return captor.getValue();
    }

    private FileMetadata captureSaved() {
        ArgumentCaptor<FileMetadata> captor = ArgumentCaptor.forClass(FileMetadata.class);
        verify(repository).save(captor.capture());
        return captor.getValue();
    }

    @Nested
    @DisplayName("issuing an upload URL")
    class Presigning {

        @Test
        void records_a_pending_row_owned_by_the_caller() {
            PresignedUpload upload = storage.presignUpload(
                    "merchant-sub", FilePurpose.PRODUCT_IMAGE, "image/png", "products/abc");

            FileMetadata saved = captureSaved();
            assertThat(saved.getOwnerId()).isEqualTo("merchant-sub");
            assertThat(saved.getBucket()).isEqualTo("product-images");
            assertThat(saved.getStatus()).isEqualTo(FileMetadata.Status.PENDING);
            assertThat(upload.uploadUrl()).isEqualTo("http://localhost:9010/signed-url");
        }

        @Test
        void signs_a_put_scoped_to_one_object_in_the_purpose_s_bucket() throws Exception {
            storage.presignUpload("m", FilePurpose.PRODUCT_IMAGE, "image/png", "products/abc");

            GetPresignedObjectUrlArgs args = capturePresign();
            assertThat(args.method()).isEqualTo(Method.PUT);
            assertThat(args.bucket()).isEqualTo("product-images");
            assertThat(args.object()).startsWith("products/abc/");
        }

        /**
         * The single most important property here. A client-supplied key would let a merchant sign
         * a PUT for another merchant's existing object and overwrite it, because the URL grants
         * write access to whatever key it was signed for.
         */
        @Test
        void the_filename_is_server_generated_and_unguessable() {
            storage.presignUpload("m", FilePurpose.PRODUCT_IMAGE, "image/png", "products/abc");
            FileMetadata first = captureSaved();

            String filename = first.getObjectKey().substring("products/abc/".length());
            assertThat(filename).endsWith(".png");
            assertThat(UUID.fromString(filename.replace(".png", ""))).isNotNull();
        }

        @Test
        void two_uploads_under_the_same_prefix_never_collide() {
            storage.presignUpload("m", FilePurpose.PRODUCT_IMAGE, "image/png", "products/abc");
            storage.presignUpload("m", FilePurpose.PRODUCT_IMAGE, "image/png", "products/abc");

            ArgumentCaptor<FileMetadata> captor = ArgumentCaptor.forClass(FileMetadata.class);
            verify(repository, org.mockito.Mockito.times(2)).save(captor.capture());
            assertThat(captor.getAllValues().get(0).getObjectKey())
                    .isNotEqualTo(captor.getAllValues().get(1).getObjectKey());
        }

        @Test
        void the_extension_follows_the_declared_content_type() {
            storage.presignUpload("m", FilePurpose.PRODUCT_IMAGE, "image/webp", "products/abc");

            assertThat(captureSaved().getObjectKey()).endsWith(".webp");
        }

        /** No URL should exist at all for a type the platform will not serve. */
        @Test
        void a_disallowed_content_type_is_refused_before_a_url_is_minted() throws Exception {
            assertThatThrownBy(() -> storage.presignUpload(
                    "m", FilePurpose.PRODUCT_IMAGE, "application/x-sh", "products/abc"))
                    .isInstanceOf(StorageException.class)
                    .hasMessageContaining("not allowed");

            verify(presignClient, never()).getPresignedObjectUrl(any());
            verify(repository, never()).save(any());
        }

        @Test
        void an_svg_is_refused_since_it_can_carry_script() throws Exception {
            assertThatThrownBy(() -> storage.presignUpload(
                    "m", FilePurpose.PRODUCT_IMAGE, "image/svg+xml", "products/abc"))
                    .isInstanceOf(StorageException.class);

            verify(presignClient, never()).getPresignedObjectUrl(any());
        }

        /**
         * A prefix is not a place to smuggle a path. No caller does this today, which is precisely
         * why it is worth pinning before one does.
         */
        @Test
        void a_traversing_key_prefix_is_refused() throws Exception {
            assertThatThrownBy(() -> storage.presignUpload(
                    "m", FilePurpose.PRODUCT_IMAGE, "image/png", "../../merchant-kyc"))
                    .isInstanceOf(StorageException.class)
                    .hasMessageContaining("Unsafe");

            verify(repository, never()).save(any());
        }

        @Test
        void an_absolute_key_prefix_is_refused() {
            assertThatThrownBy(() -> storage.presignUpload(
                    "m", FilePurpose.PRODUCT_IMAGE, "image/png", "/etc/passwd"))
                    .isInstanceOf(StorageException.class);
        }

        @Test
        void no_prefix_at_all_is_fine() {
            storage.presignUpload("m", FilePurpose.USER_AVATAR, "image/png", null);

            assertThat(captureSaved().getObjectKey()).doesNotContain("/");
        }

        /** The TTL is the whole lifetime of an unauthenticated write grant. */
        @Test
        void the_url_expires_on_the_configured_short_ttl() throws Exception {
            storage.presignUpload("m", FilePurpose.PRODUCT_IMAGE, "image/png", "products/abc");

            assertThat(capturePresign().expiry())
                    .isEqualTo((int) properties.getPresignTtl().toSeconds());
            assertThat(properties.getPresignTtl()).isLessThanOrEqualTo(java.time.Duration.ofMinutes(15));
        }

        /** Binding bucket to purpose is what stops a KYC document reaching a public bucket. */
        @Test
        void each_purpose_lands_in_its_own_bucket() throws Exception {
            storage.presignUpload("m", FilePurpose.MERCHANT_KYC, "image/png", "kyc/1");

            assertThat(capturePresign().bucket()).isEqualTo("merchant-kyc");
        }
    }

    /**
     * One allow-list per purpose. The global image list this replaced forced a service that needed
     * PDF for one purpose to accept PDF for all of them, its public product-images bucket included.
     */
    @Nested
    @DisplayName("content types, per purpose")
    class ContentTypesPerPurpose {

        @Test
        void a_product_image_still_refuses_a_pdf() throws Exception {
            assertThatThrownBy(() -> storage.presignUpload(
                    "m", FilePurpose.PRODUCT_IMAGE, "application/pdf", "products/abc"))
                    .isInstanceOf(StorageException.class)
                    .hasMessageContaining("not allowed for PRODUCT_IMAGE");

            verify(presignClient, never()).getPresignedObjectUrl(any());
            verify(repository, never()).save(any());
        }

        @org.junit.jupiter.params.ParameterizedTest
        @org.junit.jupiter.params.provider.ValueSource(strings = {
                "application/pdf", "image/jpeg", "image/png"})
        void an_order_attachment_may_be_a_pdf_a_jpeg_or_a_png(String contentType) throws Exception {
            storage.presignUpload("customer-sub", FilePurpose.ORDER_ATTACHMENT, contentType,
                    "attachments/customer-sub");

            assertThat(capturePresign().bucket()).isEqualTo("order-attachments");
            assertThat(captureSaved().getPurpose()).isEqualTo(FilePurpose.ORDER_ATTACHMENT);
        }

        /** WebP is a photo type every other purpose takes; a print shop's tools cannot be assumed to. */
        @org.junit.jupiter.params.ParameterizedTest
        @org.junit.jupiter.params.provider.ValueSource(strings = {
                "image/webp", "image/svg+xml", "application/zip", "application/postscript",
                "application/illustrator", "text/html"})
        void an_order_attachment_refuses_everything_else(String contentType) throws Exception {
            assertThatThrownBy(() -> storage.presignUpload("customer-sub",
                    FilePurpose.ORDER_ATTACHMENT, contentType, "attachments/customer-sub"))
                    .isInstanceOf(StorageException.class)
                    .hasMessageContaining("not allowed for ORDER_ATTACHMENT");

            verify(presignClient, never()).getPresignedObjectUrl(any());
            verify(repository, never()).save(any());
        }

        @Test
        void an_order_attachment_is_private() {
            assertThat(FilePurpose.ORDER_ATTACHMENT.isPubliclyReadable()).isFalse();
            assertThat(FilePurpose.ORDER_ATTACHMENT.bucket()).isEqualTo("order-attachments");
        }

        /** What onboarding-service used to get by widening the global list, now the purpose's own. */
        @Test
        void a_kyc_document_may_be_a_pdf() throws Exception {
            storage.presignUpload("applicant", FilePurpose.MERCHANT_KYC, "application/pdf",
                    "applications/1");

            assertThat(capturePresign().bucket()).isEqualTo("merchant-kyc");
        }

        @Test
        void a_missing_content_type_is_refused() {
            assertThatThrownBy(() -> storage.presignUpload(
                    "m", FilePurpose.ORDER_ATTACHMENT, null, "attachments/m"))
                    .isInstanceOf(StorageException.class);
        }

        @Test
        void a_configured_list_replaces_that_purpose_s_list_and_no_other() throws Exception {
            properties.getAllowedContentTypes().put(FilePurpose.ORDER_ATTACHMENT,
                    java.util.List.of("application/pdf"));

            assertThatThrownBy(() -> storage.presignUpload(
                    "m", FilePurpose.ORDER_ATTACHMENT, "image/jpeg", "attachments/m"))
                    .isInstanceOf(StorageException.class);
            storage.presignUpload("m", FilePurpose.PRODUCT_IMAGE, "image/jpeg", "products/abc");

            assertThat(capturePresign().bucket()).isEqualTo("product-images");
            assertThat(storage.allowedContentTypes(FilePurpose.ORDER_ATTACHMENT))
                    .containsExactly("application/pdf");
        }

        /**
         * onboarding-service still sets the old global list with PDF on it. On this version that
         * must widen nothing — the whole point of the change.
         */
        @Test
        @SuppressWarnings("deprecation")
        void the_retired_global_image_list_widens_no_purpose() {
            properties.setAllowedImageContentTypes(java.util.List.of(
                    "image/jpeg", "image/png", "image/webp", "application/pdf"));
            StorageService configured =
                    new StorageService(internalClient, presignClient, repository, properties);

            assertThatThrownBy(() -> configured.presignUpload(
                    "m", FilePurpose.PRODUCT_IMAGE, "application/pdf", "products/abc"))
                    .isInstanceOf(StorageException.class);
            assertThatThrownBy(() -> configured.presignUpload(
                    "m", FilePurpose.USER_AVATAR, "application/pdf", null))
                    .isInstanceOf(StorageException.class);
        }

        @Test
        void a_caller_can_read_the_list_it_will_be_held_to() {
            assertThat(storage.allowedContentTypes(FilePurpose.ORDER_ATTACHMENT))
                    .containsExactlyInAnyOrder("application/pdf", "image/jpeg", "image/png");
            assertThat(storage.allowedContentTypes(FilePurpose.PRODUCT_IMAGE))
                    .doesNotContain("application/pdf");
        }

        @Test
        void a_pdf_keeps_its_extension() {
            storage.presignUpload("m", FilePurpose.ORDER_ATTACHMENT, "application/pdf",
                    "attachments/m");

            assertThat(captureSaved().getObjectKey()).startsWith("attachments/m/").endsWith(".pdf");
        }
    }

    @Nested
    @DisplayName("confirming an upload")
    class Confirming {

        private final UUID fileId = UUID.randomUUID();

        private FileMetadata pending(String owner) {
            FileMetadata metadata = new FileMetadata(
                    "product-images", "products/abc/x.png", owner, "image/png",
                    FilePurpose.PRODUCT_IMAGE);
            when(repository.findById(any(UUID.class))).thenReturn(Optional.of(metadata));
            return metadata;
        }

        private FileMetadata pendingAs(String contentType, FilePurpose purpose) {
            FileMetadata metadata = new FileMetadata(purpose.bucket(), "docs/x", "applicant", contentType,
                    purpose);
            when(repository.findById(any(UUID.class))).thenReturn(Optional.of(metadata));
            return metadata;
        }

        /** A real PNG of {@code size} bytes, stored as one. */
        private void objectInBucketOfSize(long size) throws Exception {
            storedObject(size, "image/png", PNG_HEAD);
        }

        /** An object of {@code size} bytes stored as {@code storedType}, whose first bytes are {@code head}. */
        private void storedObject(long size, String storedType, byte[] head) throws Exception {
            StatObjectResponse stat = mock(StatObjectResponse.class);
            when(stat.size()).thenReturn(size);
            when(stat.contentType()).thenReturn(storedType);
            when(stat.etag()).thenReturn("etag-1");
            when(internalClient.statObject(any(StatObjectArgs.class))).thenReturn(stat);
            // A fresh stream per read, as storage would answer each request.
            when(internalClient.getObject(any(GetObjectArgs.class))).thenAnswer(call -> new GetObjectResponse(
                    okhttp3.Headers.of(), "bucket", "us-east-1", "key", new ByteArrayInputStream(head)));
        }

        private void refusedAs(UploadRefusedException.Reason reason,
                               org.assertj.core.api.ThrowableAssert.ThrowingCallable call) {
            assertThatThrownBy(call).isInstanceOfSatisfying(UploadRefusedException.class,
                    e -> assertThat(e.reason()).isEqualTo(reason));
        }

        @Test
        void marks_the_row_uploaded_with_the_real_size() throws Exception {
            FileMetadata metadata = pending("merchant-sub");
            objectInBucketOfSize(2048);

            FileMetadata confirmed = storage.confirmUpload(fileId, "merchant-sub");

            assertThat(confirmed.getStatus()).isEqualTo(FileMetadata.Status.UPLOADED);
            assertThat(confirmed.getSizeBytes()).isEqualTo(2048);
            assertThat(metadata.getStatus()).isEqualTo(FileMetadata.Status.UPLOADED);
        }

        /** Confirming somebody else's upload would attach their object to your product. */
        @Test
        void a_caller_who_does_not_own_the_file_is_refused() throws Exception {
            pending("other-merchant");

            assertThatThrownBy(() -> storage.confirmUpload(fileId, "merchant-sub"))
                    .isInstanceOf(StorageException.class)
                    .hasMessageContaining("does not belong");

            verify(internalClient, never()).statObject(any(StatObjectArgs.class));
        }

        @Test
        void an_unknown_file_id_is_refused() {
            when(repository.findById(any(UUID.class))).thenReturn(Optional.empty());

            assertThatThrownBy(() -> storage.confirmUpload(fileId, "merchant-sub"))
                    .isInstanceOf(StorageException.class)
                    .hasMessageContaining("No such file");
        }

        /**
         * The presigned URL cannot carry a size limit, so this is the only place the advertised cap
         * is real. An oversize object is removed rather than left occupying the bucket.
         */
        @Test
        void an_oversize_upload_is_deleted_and_refused() throws Exception {
            FileMetadata metadata = pending("merchant-sub");
            objectInBucketOfSize(properties.getMaxUploadSizeBytes() + 1);

            assertThatThrownBy(() -> storage.confirmUpload(fileId, "merchant-sub"))
                    .isInstanceOfSatisfying(UploadRefusedException.class,
                            e -> assertThat(e.reason()).isEqualTo(UploadRefusedException.Reason.TOO_LARGE))
                    .hasMessageContaining("exceeds the maximum");

            verify(internalClient).removeObject(any(RemoveObjectArgs.class));
            verify(internalClient, never()).getObject(any(GetObjectArgs.class));
            assertThat(metadata.getStatus()).isEqualTo(FileMetadata.Status.DELETED);
        }

        @Test
        void an_upload_exactly_at_the_limit_is_accepted() throws Exception {
            pending("merchant-sub");
            objectInBucketOfSize(properties.getMaxUploadSizeBytes());

            assertThat(storage.confirmUpload(fileId, "merchant-sub").getStatus())
                    .isEqualTo(FileMetadata.Status.UPLOADED);
        }

        /** A client that never actually PUT the bytes must not end up with a usable row. */
        @Test
        void an_upload_that_never_landed_is_refused() throws Exception {
            pending("merchant-sub");
            when(internalClient.statObject(any(StatObjectArgs.class)))
                    .thenThrow(new IllegalStateException("NoSuchKey"));

            assertThatThrownBy(() -> storage.confirmUpload(fileId, "merchant-sub"))
                    .isInstanceOf(StorageException.class)
                    .isNotInstanceOf(UploadRefusedException.class)
                    .hasMessageContaining("was not found");
        }

        /** A double-confirm is a retry, not an error, and must not re-stat the object. */
        @Test
        void confirming_twice_is_idempotent() throws Exception {
            FileMetadata metadata = pending("merchant-sub");
            objectInBucketOfSize(1024);
            storage.confirmUpload(fileId, "merchant-sub");

            FileMetadata again = storage.confirmUpload(fileId, "merchant-sub");

            assertThat(again).isSameAs(metadata);
            verify(internalClient, org.mockito.Mockito.times(1)).statObject(any(StatObjectArgs.class));
        }

        /** A type the allow-list checked at presign means nothing if the PUT stored something else. */
        @Test
        void an_object_stored_as_another_type_is_deleted_and_refused() throws Exception {
            FileMetadata metadata = pending("merchant-sub");
            storedObject(2048, "text/html", PNG_HEAD);

            refusedAs(UploadRefusedException.Reason.WRONG_TYPE,
                    () -> storage.confirmUpload(fileId, "merchant-sub"));

            verify(internalClient).removeObject(any(RemoveObjectArgs.class));
            verify(internalClient, never()).getObject(any(GetObjectArgs.class));
            assertThat(metadata.getStatus()).isEqualTo(FileMetadata.Status.DELETED);
        }

        /** The header is as easy to forge as to send: an HTML page PUT as image/png is still HTML. */
        @Test
        void bytes_that_are_not_the_declared_type_are_deleted_and_refused() throws Exception {
            FileMetadata metadata = pending("merchant-sub");
            storedObject(2048, "image/png", "<html><script>".getBytes(StandardCharsets.US_ASCII));

            refusedAs(UploadRefusedException.Reason.WRONG_TYPE,
                    () -> storage.confirmUpload(fileId, "merchant-sub"));

            verify(internalClient).removeObject(any(RemoveObjectArgs.class));
            assertThat(metadata.getStatus()).isEqualTo(FileMetadata.Status.DELETED);
        }

        @Test
        void a_pdf_a_jpeg_a_png_and_a_webp_each_pass_with_their_own_first_bytes() throws Exception {
            Map<String, byte[]> realFiles = Map.of("application/pdf", PDF_HEAD, "image/jpeg", JPEG_HEAD,
                    "image/png", PNG_HEAD, "image/webp", WEBP_HEAD);
            for (Map.Entry<String, byte[]> file : realFiles.entrySet()) {
                pendingAs(file.getKey(), FilePurpose.MERCHANT_KYC);
                storedObject(4096, file.getKey(), file.getValue());

                assertThat(storage.confirmUpload(fileId, "applicant").getStatus())
                        .as(file.getKey()).isEqualTo(FileMetadata.Status.UPLOADED);
            }
            verify(internalClient, never()).removeObject(any(RemoveObjectArgs.class));
        }

        /** A PDF's first bytes are not a PNG's, so the type declared is the type checked. */
        @Test
        void a_real_file_of_another_allowed_type_is_still_refused() throws Exception {
            pendingAs("application/pdf", FilePurpose.ORDER_ATTACHMENT);
            storedObject(4096, "application/pdf", PNG_HEAD);

            refusedAs(UploadRefusedException.Reason.WRONG_TYPE, () -> storage.confirmUpload(fileId, "applicant"));
        }

        /** A few bytes cross the network, never the file — and only bytes of the object that was measured. */
        @Test
        void only_the_first_bytes_of_the_measured_object_are_read() throws Exception {
            pending("merchant-sub");
            objectInBucketOfSize(9L * 1024 * 1024);

            storage.confirmUpload(fileId, "merchant-sub");

            ArgumentCaptor<GetObjectArgs> read = ArgumentCaptor.forClass(GetObjectArgs.class);
            verify(internalClient).getObject(read.capture());
            assertThat(read.getValue().offset()).isZero();
            assertThat(read.getValue().length()).isEqualTo(12L);
            assertThat(read.getValue().matchETag()).isEqualTo("etag-1");
        }

        @Test
        void a_type_stored_with_parameters_or_in_capitals_is_still_the_declared_one() throws Exception {
            pending("merchant-sub");
            storedObject(2048, "IMAGE/PNG; charset=binary", PNG_HEAD);

            assertThat(storage.confirmUpload(fileId, "merchant-sub").getStatus())
                    .isEqualTo(FileMetadata.Status.UPLOADED);
        }

        @Test
        void an_empty_object_is_no_type_at_all() throws Exception {
            FileMetadata metadata = pending("merchant-sub");
            storedObject(0, "image/png", new byte[0]);

            refusedAs(UploadRefusedException.Reason.WRONG_TYPE,
                    () -> storage.confirmUpload(fileId, "merchant-sub"));

            verify(internalClient, never()).getObject(any(GetObjectArgs.class));
            assertThat(metadata.getStatus()).isEqualTo(FileMetadata.Status.DELETED);
        }

        /** Every refusal has already deleted; rolling back would put the row back to PENDING. */
        @Test
        void a_refusal_keeps_its_deletion() throws Exception {
            for (String name : List.of("confirmUpload", "confirm")) {
                Transactional transactional = StorageService.class.getMethod(name, UUID.class, String.class)
                        .getAnnotation(Transactional.class);
                assertThat(transactional.noRollbackFor()).as(name)
                        .containsExactly(UploadRefusedException.class);
            }
        }

        @Test
        void confirm_answers_with_the_tag_of_the_bytes_that_were_checked() throws Exception {
            pending("merchant-sub");
            objectInBucketOfSize(2048);

            ConfirmedUpload confirmed = storage.confirm(fileId, "merchant-sub");

            assertThat(confirmed.etag()).isEqualTo("etag-1");
            assertThat(confirmed.file().getStatus()).isEqualTo(FileMetadata.Status.UPLOADED);
            assertThat(confirmed.file().getSizeBytes()).isEqualTo(2048);
        }

        /** Its URL may have been used again since the first time; a tag is only worth having for bytes that passed. */
        @Test
        void confirm_checks_an_upload_already_confirmed_again() throws Exception {
            pending("merchant-sub");
            objectInBucketOfSize(2048);

            storage.confirm(fileId, "merchant-sub");
            storage.confirm(fileId, "merchant-sub");

            verify(internalClient, times(2)).statObject(any(StatObjectArgs.class));
        }

        /** A URL that still works after its file was deleted must not be a way to bring the row back. */
        @Test
        void a_deleted_upload_is_never_confirmed_back_to_life() throws Exception {
            FileMetadata metadata = pending("merchant-sub");
            metadata.markDeleted();
            objectInBucketOfSize(2048);

            assertThatThrownBy(() -> storage.confirmUpload(fileId, "merchant-sub"))
                    .isInstanceOf(StorageException.class)
                    .hasMessageContaining("was deleted");
            assertThatThrownBy(() -> storage.confirm(fileId, "merchant-sub"))
                    .isInstanceOf(StorageException.class);

            verify(internalClient, never()).statObject(any(StatObjectArgs.class));
            assertThat(metadata.getStatus()).isEqualTo(FileMetadata.Status.DELETED);
        }
    }

    /**
     * A presigned PUT outlives its confirm, so "confirmed once" is not "still the file that was
     * checked". inspect is how a caller finds out before it trusts a file again.
     */
    @Nested
    @DisplayName("inspecting a file later")
    class Inspecting {

        private final FileMetadata artwork = new FileMetadata("order-attachments", "uploads/x.pdf",
                "customer", "application/pdf", FilePurpose.ORDER_ATTACHMENT);

        private ErrorResponseException storageSays(String code) {
            return new ErrorResponseException(new ErrorResponse(code, "message", "order-attachments",
                    "uploads/x.pdf", null, null, null), null, null);
        }

        @Test
        void says_what_the_key_holds_now_without_the_tag_s_quotes() throws Exception {
            StatObjectResponse stat = mock(StatObjectResponse.class);
            when(stat.size()).thenReturn(2048L);
            when(stat.etag()).thenReturn("\"etag-2\"");
            when(stat.contentType()).thenReturn("application/pdf");
            when(internalClient.statObject(any(StatObjectArgs.class))).thenReturn(stat);

            assertThat(storage.inspect(artwork)).contains(new StoredObject(2048, "etag-2", "application/pdf"));
        }

        @Test
        void a_key_holding_nothing_is_empty_rather_than_an_error() throws Exception {
            when(internalClient.statObject(any(StatObjectArgs.class))).thenThrow(storageSays("NoSuchKey"));

            assertThat(storage.inspect(artwork)).isEmpty();
        }

        /** "Could not ask" must never read as "it is gone", nor as "it is still there". */
        @Test
        void storage_that_cannot_answer_is_an_error() throws Exception {
            when(internalClient.statObject(any(StatObjectArgs.class))).thenThrow(new IOException("timed out"));
            assertThatThrownBy(() -> storage.inspect(artwork)).isInstanceOf(StorageException.class);

            when(internalClient.statObject(any(StatObjectArgs.class))).thenThrow(storageSays("AccessDenied"));
            assertThatThrownBy(() -> storage.inspect(artwork)).isInstanceOf(StorageException.class);
        }

        @Test
        void a_file_is_still_the_confirmed_one_only_with_the_same_length_and_tag() {
            StoredObject now = new StoredObject(2048, "etag-1", "application/pdf");

            assertThat(now.isStill(2048, "etag-1")).isTrue();
            assertThat(now.isStill(2048, "etag-2")).isFalse();
            assertThat(now.isStill(4096, "etag-1")).isFalse();
            assertThat(now.isStill(2048, null)).isFalse();
        }
    }

    @Nested
    @DisplayName("read URLs")
    class Reading {

        @Test
        void a_public_bucket_gets_a_plain_cacheable_url() throws Exception {
            FileMetadata metadata = new FileMetadata("product-images", "products/a/x.png",
                    "m", "image/png", FilePurpose.PRODUCT_IMAGE);

            assertThat(storage.readUrl(metadata))
                    .isEqualTo("http://localhost:9010/product-images/products/a/x.png");
            verify(presignClient, never()).getPresignedObjectUrl(any());
        }

        /**
         * Dispute evidence and KYC documents are private. A cacheable URL for these would leak them
         * to anyone who ever saw the link, which is the point of not using one.
         */
        @Test
        void a_private_bucket_gets_a_short_lived_signed_url() throws Exception {
            FileMetadata proof = new FileMetadata("delivery-proof", "proof/x.png",
                    "rider", "image/png", FilePurpose.DELIVERY_PROOF);

            assertThat(storage.readUrl(proof)).isEqualTo("http://localhost:9010/signed-url");

            GetPresignedObjectUrlArgs args = capturePresign();
            assertThat(args.method()).isEqualTo(Method.GET);
            assertThat(args.expiry()).isEqualTo((int) properties.getPresignTtl().toSeconds());
        }

        /**
         * A presigned PUT cannot bind a Content-Type, so the served type is pinned when the read URL
         * is signed, to the type the allow-list checked: HTML uploaded under a PDF's name must reach
         * the provider who opens it as a PDF, never render as a page in the storage origin.
         */
        @Test
        void a_private_file_is_served_as_the_type_that_was_checked() throws Exception {
            FileMetadata artwork = new FileMetadata("order-attachments", "attachments/c/x.pdf",
                    "customer", "application/pdf", FilePurpose.ORDER_ATTACHMENT);

            storage.readUrl(artwork);

            assertThat(capturePresign().extraQueryParams().get("response-content-type"))
                    .containsExactly("application/pdf");
        }

        @Test
        void every_private_purpose_is_signed_rather_than_served_directly() {
            for (FilePurpose purpose : FilePurpose.values()) {
                if (purpose.isPubliclyReadable()) {
                    continue;
                }
                FileMetadata metadata = new FileMetadata(purpose.bucket(), "k.png", "o",
                        "image/png", purpose);
                assertThat(storage.readUrl(metadata))
                        .as("%s must not be served from a plain URL", purpose)
                        .doesNotContain(purpose.bucket() + "/k.png");
            }
        }
    }

    @Nested
    @DisplayName("deleting")
    class Deleting {

        private final UUID fileId = UUID.randomUUID();

        @Test
        void removes_the_object_and_marks_the_row() throws Exception {
            FileMetadata metadata = new FileMetadata("product-images", "products/a/x.png",
                    "merchant-sub", "image/png", FilePurpose.PRODUCT_IMAGE);
            when(repository.findById(any(UUID.class))).thenReturn(Optional.of(metadata));

            storage.softDelete(fileId, "merchant-sub");

            verify(internalClient).removeObject(any(RemoveObjectArgs.class));
            assertThat(metadata.getStatus()).isEqualTo(FileMetadata.Status.DELETED);
        }

        @Test
        void a_caller_who_does_not_own_the_file_is_refused() throws Exception {
            FileMetadata metadata = new FileMetadata("product-images", "products/a/x.png",
                    "other-merchant", "image/png", FilePurpose.PRODUCT_IMAGE);
            when(repository.findById(any(UUID.class))).thenReturn(Optional.of(metadata));

            assertThatThrownBy(() -> storage.softDelete(fileId, "merchant-sub"))
                    .isInstanceOf(StorageException.class);

            verify(internalClient, never()).removeObject(any(RemoveObjectArgs.class));
            assertThat(metadata.getStatus()).isNotEqualTo(FileMetadata.Status.DELETED);
        }

        /**
         * The row's state wins over the object's. A user told their file is gone must not still see
         * it listed because the bucket call happened to fail.
         */
        @Test
        void a_bucket_failure_still_leaves_the_row_marked_deleted() throws Exception {
            FileMetadata metadata = new FileMetadata("product-images", "products/a/x.png",
                    "merchant-sub", "image/png", FilePurpose.PRODUCT_IMAGE);
            when(repository.findById(any(UUID.class))).thenReturn(Optional.of(metadata));
            org.mockito.Mockito.doThrow(new IllegalStateException("minio down"))
                    .when(internalClient).removeObject(any(RemoveObjectArgs.class));

            storage.softDelete(fileId, "merchant-sub");

            assertThat(metadata.getStatus()).isEqualTo(FileMetadata.Status.DELETED);
        }

        /** The half of a deletion made inside the caller's transaction: no storage call while it holds locks. */
        @Test
        void marking_deleted_leaves_the_bucket_alone() throws Exception {
            FileMetadata metadata = new FileMetadata("order-attachments", "uploads/x.pdf",
                    "customer", "application/pdf", FilePurpose.ORDER_ATTACHMENT);
            when(repository.findById(any(UUID.class))).thenReturn(Optional.of(metadata));

            assertThat(storage.markDeleted(fileId, "customer")).isSameAs(metadata);

            assertThat(metadata.getStatus()).isEqualTo(FileMetadata.Status.DELETED);
            verify(internalClient, never()).removeObject(any(RemoveObjectArgs.class));
            assertThatThrownBy(() -> storage.markDeleted(fileId, "somebody-else"))
                    .isInstanceOf(StorageException.class);
        }

        /** The other half, after commit: repeatable, and never a throw half way through a list. */
        @Test
        void removing_an_object_says_whether_storage_confirmed_it() throws Exception {
            FileMetadata metadata = new FileMetadata("order-attachments", "uploads/x.pdf",
                    "customer", "application/pdf", FilePurpose.ORDER_ATTACHMENT);

            assertThat(storage.removeObject(metadata)).isTrue();

            doThrow(new IOException("storage away")).when(internalClient).removeObject(any(RemoveObjectArgs.class));
            assertThat(storage.removeObject(metadata)).isFalse();
        }
    }

    /**
     * MinIO's client waits five minutes to connect, and five for each read and write. A hung storage
     * would hold whichever thread asked for that long — a request's, or a scheduled job's only one.
     */
    @Nested
    @DisplayName("waiting on storage")
    class Timeouts {

        @Test
        void storage_calls_give_up_in_seconds_not_minutes() {
            OkHttpClient http = StorageAutoConfiguration.httpClient(new StorageProperties());

            assertThat(http.connectTimeoutMillis()).isEqualTo(5_000);
            assertThat(http.readTimeoutMillis()).isEqualTo(30_000);
            assertThat(http.writeTimeoutMillis()).isEqualTo(30_000);
        }

        @Test
        void a_service_sets_its_own() {
            StorageProperties configured = new StorageProperties();
            configured.setConnectTimeout(Duration.ofSeconds(2));
            configured.setReadTimeout(Duration.ofSeconds(7));
            configured.setWriteTimeout(Duration.ofSeconds(9));

            OkHttpClient http = StorageAutoConfiguration.httpClient(configured);

            assertThat(http.connectTimeoutMillis()).isEqualTo(2_000);
            assertThat(http.readTimeoutMillis()).isEqualTo(7_000);
            assertThat(http.writeTimeoutMillis()).isEqualTo(9_000);
        }
    }

    @Nested
    @DisplayName("file signatures")
    class Signatures {

        /** A type confirm cannot check by its bytes is waved through, so no built-in list may carry one. */
        @Test
        void every_type_on_a_built_in_list_is_checked_by_its_bytes() {
            for (FilePurpose purpose : FilePurpose.values()) {
                for (String type : purpose.defaultContentTypes()) {
                    assertThat(FileSignature.isKnown(type)).as("%s for %s", type, purpose).isTrue();
                }
            }
        }

        @Test
        void a_short_or_missing_start_matches_nothing() {
            assertThat(FileSignature.matches("application/pdf", "%PD".getBytes(StandardCharsets.US_ASCII)))
                    .isFalse();
            assertThat(FileSignature.matches("image/png", null)).isFalse();
            assertThat(FileSignature.matches("image/webp", "RIFF1234WEBX".getBytes(StandardCharsets.US_ASCII)))
                    .isFalse();
        }

        @Test
        void each_type_is_told_from_the_others() {
            assertThat(FileSignature.matches("image/png", JPEG_HEAD)).isFalse();
            assertThat(FileSignature.matches("application/pdf", PNG_HEAD)).isFalse();
            assertThat(FileSignature.matches("image/jpeg", PDF_HEAD)).isFalse();
            assertThat(FileSignature.matches("image/webp", PNG_HEAD)).isFalse();
        }
    }
}
