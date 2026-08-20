package com.delivery.platform.storage;

import java.util.Optional;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

import io.minio.GetPresignedObjectUrlArgs;
import io.minio.MinioClient;
import io.minio.RemoveObjectArgs;
import io.minio.StatObjectArgs;
import io.minio.StatObjectResponse;
import io.minio.http.Method;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
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

        private void objectInBucketOfSize(long size) throws Exception {
            StatObjectResponse stat = mock(StatObjectResponse.class);
            when(stat.size()).thenReturn(size);
            when(internalClient.statObject(any(StatObjectArgs.class))).thenReturn(stat);
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
                    .isInstanceOf(StorageException.class)
                    .hasMessageContaining("exceeds the maximum");

            verify(internalClient).removeObject(any(RemoveObjectArgs.class));
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
    }
}
