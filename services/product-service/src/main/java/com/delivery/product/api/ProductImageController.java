package com.delivery.product.api;

import java.util.UUID;

import jakarta.validation.Valid;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.delivery.platform.security.CurrentUser;
import com.delivery.platform.storage.PresignedUpload;
import com.delivery.product.api.dto.CatalogDtos.PresignUploadRequest;
import com.delivery.product.api.dto.CatalogDtos.PresignUploadResponse;
import com.delivery.product.service.ProductImageService;

/**
 * Product image upload endpoints.
 *
 * <p>Note there is no multipart endpoint here. Image bytes go directly from the client to MinIO via
 * the presigned URL and never traverse this service (Section 5) — which is why the Gateway's
 * request size limits and this service's thread pool are unaffected by a merchant uploading a
 * 10 MB photo.
 */
@RestController
@RequestMapping("/api/products/{productId}/images")
@PreAuthorize("hasRole('MERCHANT')")
public class ProductImageController {

    private final ProductImageService images;

    public ProductImageController(ProductImageService images) {
        this.images = images;
    }

    /** Step 1: get a one-shot URL to PUT one image to. */
    @PostMapping("/presign")
    public ResponseEntity<PresignUploadResponse> presign(
            @PathVariable UUID productId,
            @Valid @RequestBody PresignUploadRequest request) {

        PresignedUpload upload = images.presign(
                productId, CurrentUser.requireId(), request.contentType());

        return ResponseEntity.status(HttpStatus.CREATED).body(new PresignUploadResponse(
                upload.fileId(),
                upload.uploadUrl(),
                upload.objectKey(),
                upload.contentType(),
                upload.expiresAt(),
                upload.maxSizeBytes()));
    }

    /**
     * Step 3: tell the service the bytes landed.
     *
     * <p>(Step 2 is the client's own PUT straight to MinIO.) Until this is called the image is not
     * attached to the product, so an abandoned upload leaves a stray object and a PENDING metadata
     * row but never a broken product listing.
     */
    @PostMapping("/{fileId}/confirm")
    public ResponseEntity<Void> confirm(@PathVariable UUID productId, @PathVariable UUID fileId) {
        images.confirmImage(productId, CurrentUser.requireId(), fileId);
        return ResponseEntity.noContent().build();
    }

    @DeleteMapping
    public ResponseEntity<Void> remove(@PathVariable UUID productId,
                                       @RequestParam String objectKey) {
        images.removeImage(productId, CurrentUser.requireId(), objectKey);
        return ResponseEntity.noContent().build();
    }
}
