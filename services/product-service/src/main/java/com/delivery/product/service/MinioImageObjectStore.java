package com.delivery.product.service;

import java.io.ByteArrayInputStream;
import java.io.InputStream;

import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.stereotype.Component;

import io.minio.GetObjectArgs;
import io.minio.MinioClient;
import io.minio.PutObjectArgs;

/**
 * {@link ImageObjectStore} against MinIO.
 *
 * <p>Uses the <em>internal</em> client, the same one {@code StorageService} stats and removes with.
 * The presigning client is built against the public endpoint so its signatures match the host a
 * phone resolves; server-side traffic has no reason to leave the internal network, and routing a
 * few hundred kilobytes back out through the host to fetch an object this pod can already reach
 * would be a pointless round trip.
 *
 * <p>{@code @Qualifier} rather than the parameter name, for the reason spelled out in
 * {@code StorageAutoConfiguration}: there are two {@code MinioClient} beans, and name-based
 * disambiguation depends on a compiler flag that a pom edit can silently undo.
 */
@Component
public class MinioImageObjectStore implements ImageObjectStore {

    private final MinioClient client;

    public MinioImageObjectStore(@Qualifier("internalMinioClient") MinioClient internalMinioClient) {
        this.client = internalMinioClient;
    }

    @Override
    public byte[] read(String bucket, String objectKey) {
        try (InputStream in = client.getObject(GetObjectArgs.builder()
                .bucket(bucket)
                .object(objectKey)
                .build())) {
            return in.readAllBytes();
        } catch (Exception e) {
            throw new Thumbnailer.ThumbnailUnavailableException(
                    "could not read " + bucket + "/" + objectKey, e);
        }
    }

    @Override
    public void write(String bucket, String objectKey, byte[] bytes, String contentType) {
        try (InputStream in = new ByteArrayInputStream(bytes)) {
            // -1 for the part size lets the client choose; the object is a few tens of kilobytes,
            // so it is a single part either way.
            client.putObject(PutObjectArgs.builder()
                    .bucket(bucket)
                    .object(objectKey)
                    .stream(in, bytes.length, -1)
                    .contentType(contentType)
                    .build());
        } catch (Exception e) {
            throw new Thumbnailer.ThumbnailUnavailableException(
                    "could not write " + bucket + "/" + objectKey, e);
        }
    }
}
