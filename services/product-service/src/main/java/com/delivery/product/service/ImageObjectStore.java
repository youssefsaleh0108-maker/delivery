package com.delivery.product.service;

/**
 * Reading and writing object bytes, which the presigned flow otherwise never needs.
 *
 * <p>{@code StorageService} deliberately exposes no byte-level operations: the entire point of
 * presigning is that image bytes go from the client straight to MinIO and never through a service
 * (Section 5). Producing a derivative is the one job that genuinely has to touch the bytes, and it
 * happens once per upload on a merchant write path, not on any customer read path — so this is a
 * narrow exception to that rule rather than a hole in it.
 *
 * <p>An interface rather than a {@code MinioClient} injected directly, so the thumbnail flow can be
 * tested end to end without a bucket.
 */
public interface ImageObjectStore {

    /**
     * @throws RuntimeException if the object is missing or unreadable; callers treat that the same
     *                          way they treat an undecodable image
     */
    byte[] read(String bucket, String objectKey);

    void write(String bucket, String objectKey, byte[] bytes, String contentType);
}
