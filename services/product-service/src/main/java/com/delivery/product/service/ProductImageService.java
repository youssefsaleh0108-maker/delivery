package com.delivery.product.service;

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

    private final ProductRepository products;
    private final StorageService storage;
    private final FileMetadataRepository files;
    private final OutboxRecorder outbox;
    private final int maxImagesPerProduct;

    public ProductImageService(
            ProductRepository products,
            StorageService storage,
            FileMetadataRepository files,
            OutboxRecorder outbox,
            @org.springframework.beans.factory.annotation.Value(
                    "${delivery.catalog.max-images-per-product:8}") int maxImagesPerProduct) {
        this.products = products;
        this.storage = storage;
        this.files = files;
        this.outbox = outbox;
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
     */
    @Transactional
    public Product confirmImage(UUID productId, String merchantId, UUID fileId) {
        Product product = requireOwned(productId, merchantId);
        FileMetadata metadata = storage.confirmUpload(fileId, merchantId);

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

        files.findByBucketAndObjectKey(FilePurpose.PRODUCT_IMAGE.bucket(), objectKey)
                .ifPresent(metadata -> storage.softDelete(metadata.getId(), merchantId));

        outbox.record(CatalogEvents.AGGREGATE_TYPE, product.getId().toString(),
                CatalogEvents.PRODUCT_UPDATED, CatalogEvents.ProductSnapshot.of(product));
        return product;
    }

    /**
     * Turns a single optional object key into a URL, for a store's logo or cover.
     *
     * <p>Returns null rather than throwing when the key is absent or its upload was never
     * confirmed: a store without artwork is a normal state, and the clients render a generated
     * monogram tile in its place.
     */
    @Transactional(readOnly = true)
    public String resolveUrl(String objectKey) {
        if (objectKey == null || objectKey.isBlank()) {
            return null;
        }
        List<String> resolved = resolveUrls(List.of(objectKey));
        return resolved.isEmpty() ? null : resolved.get(0);
    }

    /**
     * Turns stored object keys into URLs a client can load.
     *
     * <p>Batched into one repository call rather than one per key: a catalog page of 20 products
     * with 4 images each is 80 lookups if done naively.
     */
    @Transactional(readOnly = true)
    public List<String> resolveUrls(List<String> objectKeys) {
        if (objectKeys.isEmpty()) {
            return List.of();
        }

        Map<String, FileMetadata> byKey = files.findByObjectKeyIn(objectKeys).stream()
                .filter(metadata -> metadata.getStatus() == FileMetadata.Status.UPLOADED)
                .collect(Collectors.toMap(FileMetadata::getObjectKey, Function.identity(),
                        (first, second) -> first));

        // Preserve the product's display order, and drop keys whose metadata is missing or not yet
        // confirmed rather than emitting a URL that would 404 in the client.
        return objectKeys.stream()
                .map(byKey::get)
                .filter(java.util.Objects::nonNull)
                .map(storage::readUrl)
                .toList();
    }

    private Product requireOwned(UUID productId, String merchantId) {
        return products.findByIdAndMerchantId(productId, merchantId)
                .orElseThrow(() -> new ProductNotFoundException(productId));
    }
}
