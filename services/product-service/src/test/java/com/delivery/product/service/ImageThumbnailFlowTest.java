package com.delivery.product.service;

import java.awt.Color;
import java.awt.Graphics2D;
import java.awt.image.BufferedImage;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

import javax.imageio.ImageIO;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import com.delivery.platform.outbox.OutboxRecorder;
import com.delivery.platform.storage.FileMetadata;
import com.delivery.platform.storage.FileMetadataRepository;
import com.delivery.platform.storage.FilePurpose;
import com.delivery.platform.storage.StorageService;
import com.delivery.product.domain.Product;
import com.delivery.product.domain.ProductRepository;
import com.delivery.product.domain.Store;
import com.delivery.product.domain.StoreRepository;
import com.delivery.product.service.ProductImageService.ImageUrl;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

/**
 * The confirm step, end to end, with a bucket standing in for MinIO.
 *
 * <p>Two guarantees are being held down here, and the second matters more than the first. One: a
 * confirmed upload gains a small derivative beside it, and the list surfaces are handed its URL.
 * Two: <em>nothing</em> about producing that derivative can cost a merchant their photo. A corrupt
 * file, a format ImageIO refuses, a decompression bomb, an unreachable object — every one of them
 * has to end with the product still holding its picture and the response still carrying a URL that
 * loads.
 */
class ImageThumbnailFlowTest {

    private static final String MERCHANT = "merchant-sub";
    private static final String BUCKET = FilePurpose.PRODUCT_IMAGE.bucket();
    private static final UUID PRODUCT = UUID.randomUUID();
    private static final UUID STORE = UUID.randomUUID();

    /** A bucket: keys to bytes, and a note of every write so "untouched" can be asserted. */
    private static final class FakeObjectStore implements ImageObjectStore {

        private final Map<String, byte[]> objects = new LinkedHashMap<>();
        private final List<String> writes = new ArrayList<>();
        private boolean unreachable;

        @Override
        public byte[] read(String bucket, String objectKey) {
            if (unreachable) {
                throw new IllegalStateException("MinIO is not answering");
            }
            byte[] bytes = objects.get(objectKey);
            if (bytes == null) {
                throw new IllegalStateException("no such object: " + objectKey);
            }
            return bytes;
        }

        @Override
        public void write(String bucket, String objectKey, byte[] bytes, String contentType) {
            objects.put(objectKey, bytes);
            writes.add(objectKey);
        }
    }

    /** Just enough of the metadata table to resolve URLs against. */
    private static final class FakeFiles {

        private final Map<String, FileMetadata> rows = new HashMap<>();

        FileMetadata uploaded(String objectKey, String contentType) {
            FileMetadata metadata =
                    new FileMetadata(BUCKET, objectKey, MERCHANT, contentType, FilePurpose.PRODUCT_IMAGE);
            metadata.markUploaded(1234L);
            rows.put(objectKey, metadata);
            return metadata;
        }
    }

    private FakeObjectStore bucket;
    private FakeFiles table;
    private FileMetadataRepository files;
    private StorageService storage;
    private ProductRepository products;
    private StoreRepository stores;
    private ProductImageService productImages;
    private StoreImageService storeImages;

    @BeforeEach
    void setUp() {
        bucket = new FakeObjectStore();
        table = new FakeFiles();
        files = mock(FileMetadataRepository.class);
        storage = mock(StorageService.class);
        products = mock(ProductRepository.class);
        stores = mock(StoreRepository.class);

        when(files.save(any(FileMetadata.class))).thenAnswer(call -> {
            FileMetadata saved = call.getArgument(0);
            table.rows.put(saved.getObjectKey(), saved);
            return saved;
        });
        when(files.findByObjectKeyIn(any())).thenAnswer(call -> {
            List<String> keys = call.getArgument(0);
            return keys.stream().map(table.rows::get).filter(java.util.Objects::nonNull).toList();
        });
        when(files.findByBucketAndObjectKey(anyString(), anyString())).thenAnswer(call ->
                Optional.ofNullable(table.rows.get(call.getArgument(1, String.class))));
        when(storage.readUrl(any(FileMetadata.class))).thenAnswer(call ->
                "https://cdn.example/" + BUCKET + "/"
                        + call.getArgument(0, FileMetadata.class).getObjectKey());

        ThumbnailService thumbnails =
                new ThumbnailService(bucket, files, new Thumbnailer(40_000_000L));
        productImages = new ProductImageService(
                products, storage, files, mock(OutboxRecorder.class), thumbnails, 8);
        storeImages = new StoreImageService(stores, storage, thumbnails);
    }

    // ---------------------------------------------------------------- fixtures

    private static byte[] photo(int width, int height) {
        BufferedImage image = new BufferedImage(width, height, BufferedImage.TYPE_INT_RGB);
        Graphics2D g = image.createGraphics();
        g.setColor(Color.ORANGE);
        g.fillRect(0, 0, width, height);
        g.setColor(Color.BLUE);
        g.fillOval(width / 4, height / 4, width / 2, height / 2);
        g.dispose();
        try {
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            ImageIO.write(image, "jpg", out);
            return out.toByteArray();
        } catch (IOException e) {
            throw new AssertionError(e);
        }
    }

    private static BufferedImage read(byte[] bytes) {
        try {
            return ImageIO.read(new ByteArrayInputStream(bytes));
        } catch (IOException e) {
            throw new AssertionError(e);
        }
    }

    /** Puts bytes in the bucket, records their PENDING-then-UPLOADED row, and returns the key. */
    private String uploadedProductImage(byte[] bytes) {
        String key = "products/" + PRODUCT + "/" + UUID.randomUUID() + ".jpg";
        bucket.objects.put(key, bytes);
        bucket.writes.clear();

        FileMetadata metadata = table.uploaded(key, "image/jpeg");
        when(storage.confirmUpload(any(UUID.class), anyString())).thenReturn(metadata);
        return key;
    }

    private Product product() {
        Product product = new Product(MERCHANT, STORE, "Falafel wrap", "With pickles",
                new BigDecimal("6.50"), null);
        when(products.findByIdAndMerchantId(PRODUCT, MERCHANT)).thenReturn(Optional.of(product));
        return product;
    }

    private Store store() {
        Store store = new Store(MERCHANT, "My Store", Store.Vertical.RESTAURANT);
        when(stores.findByIdAndMerchantId(STORE, MERCHANT)).thenReturn(Optional.of(store));
        return store;
    }

    private String thumbOf(String key) {
        return Thumbnailer.thumbKeyFor(key);
    }

    // ---------------------------------------------------------------- happy path

    @Nested
    @DisplayName("confirming a product image")
    class ProductImages {

        @Test
        void produces_a_derivative_beside_the_original() {
            product();
            String key = uploadedProductImage(photo(1600, 1200));

            productImages.confirmImage(PRODUCT, MERCHANT, UUID.randomUUID());

            assertThat(bucket.writes).containsExactly(thumbOf(key));
            assertThat(bucket.objects).containsKey(thumbOf(key));
        }

        @Test
        void the_derivative_is_320_on_its_long_edge_with_the_ratio_intact() {
            product();
            String key = uploadedProductImage(photo(1600, 1200));

            productImages.confirmImage(PRODUCT, MERCHANT, UUID.randomUUID());

            BufferedImage thumb = read(bucket.objects.get(thumbOf(key)));
            assertThat(thumb.getWidth()).isEqualTo(Thumbnailer.LONG_EDGE_PX);
            assertThat(thumb.getHeight()).isEqualTo(240);
        }

        /** The point of a derivative is that it is a second object, not a replacement. */
        @Test
        void the_original_is_left_byte_for_byte_alone() {
            product();
            byte[] original = photo(1600, 1200);
            String key = uploadedProductImage(original);

            productImages.confirmImage(PRODUCT, MERCHANT, UUID.randomUUID());

            assertThat(bucket.objects.get(key)).isEqualTo(original);
            assertThat(bucket.objects.get(thumbOf(key)).length).isLessThan(original.length);
        }

        @Test
        void the_derivative_is_recorded_as_an_uploaded_jpeg_owned_by_the_same_merchant() {
            product();
            String key = uploadedProductImage(photo(1600, 1200));

            productImages.confirmImage(PRODUCT, MERCHANT, UUID.randomUUID());

            FileMetadata recorded = table.rows.get(thumbOf(key));
            assertThat(recorded).isNotNull();
            assertThat(recorded.getStatus()).isEqualTo(FileMetadata.Status.UPLOADED);
            assertThat(recorded.getContentType()).isEqualTo("image/jpeg");
            assertThat(recorded.getOwnerId()).isEqualTo(MERCHANT);
            assertThat(recorded.getSizeBytes())
                    .isEqualTo((long) bucket.objects.get(thumbOf(key)).length);
        }

        /** Confirm is idempotent upstream, so it has to be idempotent here too. */
        @Test
        void confirming_twice_does_not_write_a_second_derivative() {
            product();
            String key = uploadedProductImage(photo(800, 600));

            productImages.confirmImage(PRODUCT, MERCHANT, UUID.randomUUID());
            productImages.confirmImage(PRODUCT, MERCHANT, UUID.randomUUID());

            assertThat(bucket.writes).containsExactly(thumbOf(key));
        }
    }

    // ---------------------------------------------------------------- failure is not fatal

    @Nested
    @DisplayName("when the derivative cannot be made")
    class FailureIsNotFatal {

        /** The merchant's photo is the thing being protected. Everything else is an optimisation. */
        @Test
        void an_undecodable_file_still_confirms_and_still_attaches_the_picture() {
            Product product = product();
            String key = uploadedProductImage("this is not a photograph".getBytes(StandardCharsets.UTF_8));

            productImages.confirmImage(PRODUCT, MERCHANT, UUID.randomUUID());

            assertThat(product.getImageRefs()).containsExactly(key);
            assertThat(bucket.writes).isEmpty();
        }

        @Test
        void a_source_over_the_pixel_budget_still_confirms() {
            Product product = product();
            ThumbnailService tiny = new ThumbnailService(bucket, files, new Thumbnailer(1_000L));
            ProductImageService images = new ProductImageService(
                    products, storage, files, mock(OutboxRecorder.class), tiny, 8);
            String key = uploadedProductImage(photo(800, 600));

            images.confirmImage(PRODUCT, MERCHANT, UUID.randomUUID());

            assertThat(product.getImageRefs()).containsExactly(key);
            assertThat(bucket.objects).doesNotContainKey(thumbOf(key));
        }

        @Test
        void a_bucket_that_will_not_answer_still_confirms() {
            Product product = product();
            String key = uploadedProductImage(photo(800, 600));
            bucket.unreachable = true;

            productImages.confirmImage(PRODUCT, MERCHANT, UUID.randomUUID());

            assertThat(product.getImageRefs()).containsExactly(key);
        }

        /**
         * And the response for that product still carries a loadable URL in the thumbnail slot —
         * the full-size one. A failed derivative degrades to slow, never to broken.
         */
        @Test
        void the_list_url_falls_back_to_the_full_size_image() {
            product();
            String key = uploadedProductImage("not a photograph".getBytes(StandardCharsets.UTF_8));

            productImages.confirmImage(PRODUCT, MERCHANT, UUID.randomUUID());

            List<ImageUrl> resolved = productImages.resolveImages(List.of(key));
            assertThat(resolved).hasSize(1);
            assertThat(resolved.get(0).thumb()).isEqualTo(resolved.get(0).full());
        }
    }

    // ---------------------------------------------------------------- store artwork

    @Nested
    @DisplayName("confirming store artwork")
    class StoreArtwork {

        @Test
        void a_cover_gets_the_same_derivative_as_a_product_photo() {
            store();
            String key = uploadedProductImage(photo(1920, 1080));

            storeImages.confirm(STORE, MERCHANT, StoreImageService.Slot.COVER, UUID.randomUUID());

            assertThat(bucket.writes).containsExactly(thumbOf(key));
            assertThat(read(bucket.objects.get(thumbOf(key))).getWidth())
                    .isEqualTo(Thumbnailer.LONG_EDGE_PX);
        }

        @Test
        void a_logo_gets_one_too() {
            store();
            String key = uploadedProductImage(photo(512, 512));

            storeImages.confirm(STORE, MERCHANT, StoreImageService.Slot.LOGO, UUID.randomUUID());

            assertThat(bucket.objects).containsKey(thumbOf(key));
        }

        @Test
        void an_undecodable_cover_still_attaches_to_the_store() {
            Store store = store();
            String key = uploadedProductImage("nope".getBytes(StandardCharsets.UTF_8));

            storeImages.confirm(STORE, MERCHANT, StoreImageService.Slot.COVER, UUID.randomUUID());

            assertThat(store.getCoverRef()).isEqualTo(key);
        }
    }

    // ---------------------------------------------------------------- resolving

    @Nested
    @DisplayName("resolving URLs for a response")
    class Resolving {

        @Test
        void an_image_with_a_derivative_reports_two_different_urls() {
            product();
            String key = uploadedProductImage(photo(1600, 1200));
            productImages.confirmImage(PRODUCT, MERCHANT, UUID.randomUUID());

            ImageUrl resolved = productImages.resolveImage(key);

            assertThat(resolved.full()).endsWith(key);
            assertThat(resolved.thumb()).endsWith(thumbOf(key));
            assertThat(resolved.thumb()).isNotEqualTo(resolved.full());
        }

        /**
         * The whole installed base. Every image uploaded before this existed has no derivative and
         * never will unless someone backfills, so the fallback is the normal case for a long time.
         */
        @Test
        void an_image_uploaded_before_thumbnailing_existed_falls_back_to_full_size() {
            String legacy = "products/" + PRODUCT + "/" + UUID.randomUUID() + ".jpg";
            table.uploaded(legacy, "image/jpeg");

            ImageUrl resolved = productImages.resolveImage(legacy);

            assertThat(resolved.full()).endsWith(legacy);
            assertThat(resolved.thumb()).isEqualTo(resolved.full());
        }

        @Test
        void the_two_lists_stay_index_aligned_when_only_some_images_have_derivatives() {
            product();
            String withThumb = uploadedProductImage(photo(1600, 1200));
            productImages.confirmImage(PRODUCT, MERCHANT, UUID.randomUUID());
            String withoutThumb = "products/" + PRODUCT + "/" + UUID.randomUUID() + ".jpg";
            table.uploaded(withoutThumb, "image/jpeg");

            List<ImageUrl> resolved =
                    productImages.resolveImages(List.of(withThumb, withoutThumb));

            assertThat(resolved).hasSize(2);
            assertThat(resolved.get(0).thumb()).endsWith(thumbOf(withThumb));
            assertThat(resolved.get(1).thumb()).endsWith(withoutThumb);
        }

        /** Unchanged from before: an unconfirmed key is dropped, not emitted as a dead URL. */
        @Test
        void a_key_with_no_confirmed_upload_is_dropped_from_both_lists() {
            assertThat(productImages.resolveImages(List.of("products/x/never-uploaded.jpg")))
                    .isEmpty();
        }

        @Test
        void a_store_with_no_artwork_resolves_to_nothing_rather_than_to_an_empty_url() {
            assertThat(productImages.resolveImage(null)).isNull();
            assertThat(productImages.resolveImage("  ")).isNull();
            assertThat(ImageUrl.fullOf(null)).isNull();
            assertThat(ImageUrl.thumbOf(null)).isNull();
        }

        /** Originals and derivatives are fetched together; the browse path must not double up. */
        @Test
        void both_sizes_come_out_of_a_single_metadata_lookup() {
            product();
            String key = uploadedProductImage(photo(800, 600));
            productImages.confirmImage(PRODUCT, MERCHANT, UUID.randomUUID());

            productImages.resolveImages(List.of(key));

            org.mockito.Mockito.verify(files, org.mockito.Mockito.times(1))
                    .findByObjectKeyIn(List.of(key, thumbOf(key)));
        }
    }

    // ---------------------------------------------------------------- removal

    @Nested
    @DisplayName("removing an image")
    class Removal {

        @Test
        void takes_the_derivative_with_it() {
            Product product = product();
            String key = uploadedProductImage(photo(800, 600));
            productImages.confirmImage(PRODUCT, MERCHANT, UUID.randomUUID());
            assertThat(product.getImageRefs()).containsExactly(key);

            productImages.removeImage(PRODUCT, MERCHANT, key);

            org.mockito.Mockito.verify(storage)
                    .softDelete(table.rows.get(key).getId(), MERCHANT);
            org.mockito.Mockito.verify(storage)
                    .softDelete(table.rows.get(thumbOf(key)).getId(), MERCHANT);
        }

        /** A pre-existing image has no derivative to delete, and that is not an error. */
        @Test
        void an_image_with_no_derivative_removes_cleanly() {
            Product product = product();
            String legacy = "products/" + PRODUCT + "/" + UUID.randomUUID() + ".jpg";
            product.addImage(legacy);
            table.uploaded(legacy, "image/jpeg");

            productImages.removeImage(PRODUCT, MERCHANT, legacy);

            assertThat(product.getImageRefs()).isEmpty();
        }
    }
}
