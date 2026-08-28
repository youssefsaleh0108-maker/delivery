package com.delivery.product.service;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.function.Function;
import java.util.stream.Collectors;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.platform.outbox.OutboxRecorder;
import com.delivery.platform.storage.FileMetadata;
import com.delivery.platform.storage.FileMetadataRepository;
import com.delivery.platform.storage.FilePurpose;
import com.delivery.platform.storage.PresignedUpload;
import com.delivery.platform.storage.StorageService;
import com.delivery.product.domain.Product;
import com.delivery.product.domain.ProductRepository;
import com.delivery.product.event.CatalogEvents;
import com.delivery.product.service.CatalogService.CatalogRuleViolationException;
import com.delivery.product.service.CatalogService.ProductNotFoundException;

/**
 * Product image upload, as a three-step flow (Section 5).
 *
 * <ol>
 *   <li>The merchant asks for a presigned PUT. Ownership is checked here, before any URL exists.</li>
 *   <li>The client PUTs the bytes <em>straight to MinIO</em> — the image never passes through this
 *       service, which is the point of presigning.</li>
 *   <li>The client confirms. Only then is the object verified to exist, size-checked, and attached
 *       to the product.</li>
 * </ol>
 *
 * <p>Step 3 is what makes the flow safe to trust: without it a merchant could hold an image
 * reference on a product for bytes that were never uploaded.
 */
@Service
public class ProductImageService {

    /**
     * One image, at both the sizes a client might want it.
     *
     * <p>{@code thumb} is never null when {@code full} is not: when no derivative exists — every
     * image uploaded before thumbnailing did, and any whose generation failed — it holds the
     * full-size URL. See {@link #resolveImages} for why that fallback lives here.
     */
    public record ImageUrl(String full, String thumb) {

        /** Null-tolerant readers, for the store slots where "no artwork" is a normal state. */
        public static String fullOf(ImageUrl url) {
            return url == null ? null : url.full();
        }

        public static String thumbOf(ImageUrl url) {
            return url == null ? null : url.thumb();
        }
    }

    private final ProductRepository products;
    private final StorageService storage;
    private final FileMetadataRepository files;
    private final OutboxRecorder outbox;
    private final ThumbnailService thumbnails;
    private final int maxImagesPerProduct;

    public ProductImageService(
            ProductRepository products,
            StorageService storage,
            FileMetadataRepository files,
            OutboxRecorder outbox,
            ThumbnailService thumbnails,
            @org.springframework.beans.factory.annotation.Value(
                    "${delivery.catalog.max-images-per-product:8}") int maxImagesPerProduct) {
        this.products = products;
        this.storage = storage;
        this.files = files;
        this.outbox = outbox;
        this.thumbnails = thumbnails;
        this.maxImagesPerProduct = maxImagesPerProduct;
    }

    @Transactional
    public PresignedUpload presign(UUID productId, String merchantId, String contentType) {
        Product product = requireOwned(productId, merchantId);

        if (product.getImageRefs().size() >= maxImagesPerProduct) {
            throw new CatalogRuleViolationException(
                    "A product may have at most " + maxImagesPerProduct + " images");
        }

        // Namespacing the key by product id keeps the bucket browsable and makes an orphaned-object
        // sweep straightforward later.
        return storage.presignUpload(
                merchantId, FilePurpose.PRODUCT_IMAGE, contentType, "products/" + productId);
    }

    /**
     * Attaches a confirmed upload to the product.
     *
     * <p>The ownership check runs twice by design: {@code confirmUpload} verifies the <em>file</em>
     * belongs to the caller, and {@code requireOwned} verifies the <em>product</em> does. Skipping
     * the second would let a merchant staple their own image onto a competitor's listing.
     *
     * <p>The list-sized derivative is produced here, once, rather than on every read. It cannot
     * fail this call — see {@link ThumbnailService#createFor}.
     */
    @Transactional
    public Product confirmImage(UUID productId, String merchantId, UUID fileId) {
        Product product = requireOwned(productId, merchantId);
        FileMetadata metadata = storage.confirmUpload(fileId, merchantId);

        thumbnails.createFor(metadata);

        product.addImage(metadata.getObjectKey());
        outbox.record(CatalogEvents.AGGREGATE_TYPE, product.getId().toString(),
                CatalogEvents.PRODUCT_UPDATED, CatalogEvents.ProductSnapshot.of(product));
        return product;
    }

    @Transactional
    public Product removeImage(UUID productId, String merchantId, String objectKey) {
        Product product = requireOwned(productId, merchantId);

        if (!product.removeImage(objectKey)) {
            throw new CatalogRuleViolationException(
                    "Product " + productId + " has no image " + objectKey);
        }

        String bucket = FilePurpose.PRODUCT_IMAGE.bucket();
        files.findByBucketAndObjectKey(bucket, objectKey)
                .ifPresent(metadata -> storage.softDelete(metadata.getId(), merchantId));
        // The derivative goes with its original. It is unreachable once the original's metadata is
        // gone — resolveImages only ever offers a thumbnail beside a full-size URL — but leaving
        // the row and the object behind would make every later orphan sweep wrong about what it
        // had collected.
        files.findByBucketAndObjectKey(bucket, Thumbnailer.thumbKeyFor(objectKey))
                .ifPresent(metadata -> storage.softDelete(metadata.getId(), merchantId));

        outbox.record(CatalogEvents.AGGREGATE_TYPE, product.getId().toString(),
                CatalogEvents.PRODUCT_UPDATED, CatalogEvents.ProductSnapshot.of(product));
        return product;
    }

    /**
     * Turns a single optional object key into a full-size URL, for artwork that has only one size
     * — a banner, or a category tile.
     *
     * <p>Returns null rather than throwing when the key is absent or its upload was never
     * confirmed: artwork nobody has uploaded yet is a normal state, and the clients render a
     * generated tile in its place. Callers that draw the same picture at two sizes want
     * {@link #resolveImage} instead.
     */
    @Transactional(readOnly = true)
    public String resolveUrl(String objectKey) {
        return ImageUrl.fullOf(resolveImage(objectKey));
    }

    /** The single-key form of {@link #resolveImages}. Null when there is no artwork to show. */
    @Transactional(readOnly = true)
    public ImageUrl resolveImage(String objectKey) {
        if (objectKey == null || objectKey.isBlank()) {
            return null;
        }
        List<ImageUrl> resolved = resolveImages(List.of(objectKey));
        return resolved.isEmpty() ? null : resolved.get(0);
    }

    /**
     * Turns stored object keys into the URLs a client can load, full-size and list-sized.
     *
     * <p>Batched into one repository call rather than one per key: a catalog page of 20 products
     * with 4 images each is 80 lookups if done naively. Originals and derivatives are fetched
     * together in that same call, so adding thumbnails costs no extra round trip — only a longer
     * {@code IN} list.
     *
     * <p><strong>The missing-thumbnail fallback lives here, on the server, and not in the
     * clients.</strong> Only this service can answer whether a derivative actually exists: the key
     * is a pure function of the original's, so a client could certainly guess the URL, but a
     * guessed URL for an image uploaded before thumbnailing existed — or one whose generation
     * failed — is a 404 and a broken tile, and the client would have to load the image to find
     * out. Deciding it here also means the several apps already in the wild get the right picture
     * without shipping a release. The clients still degrade if the field is absent altogether, but
     * that is a guard against an old server, not a second copy of this rule.
     */
    @Transactional(readOnly = true)
    public List<ImageUrl> resolveImages(List<String> objectKeys) {
        if (objectKeys.isEmpty()) {
            return List.of();
        }

        List<String> wanted = new ArrayList<>(objectKeys.size() * 2);
        wanted.addAll(objectKeys);
        objectKeys.forEach(key -> wanted.add(Thumbnailer.thumbKeyFor(key)));

        Map<String, FileMetadata> byKey = files.findByObjectKeyIn(wanted).stream()
                .filter(metadata -> metadata.getStatus() == FileMetadata.Status.UPLOADED)
                .collect(Collectors.toMap(FileMetadata::getObjectKey, Function.identity(),
                        (first, second) -> first));

        // Preserve the product's display order, and drop keys whose metadata is missing or not yet
        // confirmed rather than emitting a URL that would 404 in the client.
        List<ImageUrl> resolved = new ArrayList<>(objectKeys.size());
        for (String key : objectKeys) {
            FileMetadata original = byKey.get(key);
            if (original == null) {
                continue;
            }
            String full = storage.readUrl(original);
            FileMetadata thumb = byKey.get(Thumbnailer.thumbKeyFor(key));
            resolved.add(new ImageUrl(full, thumb == null ? full : storage.readUrl(thumb)));
        }
        return resolved;
    }

    private Product requireOwned(UUID productId, String merchantId) {
        return products.findByIdAndMerchantId(productId, merchantId)
                .orElseThrow(() -> new ProductNotFoundException(productId));
    }
}
