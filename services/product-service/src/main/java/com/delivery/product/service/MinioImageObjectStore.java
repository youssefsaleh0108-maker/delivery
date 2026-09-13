package com.delivery.product.service;

import java.io.ByteArrayInputStream;
import java.io.InputStream;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.stereotype.Component;

import com.delivery.platform.storage.StorageProperties;

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
 *
 * <p><strong>A read never takes more than the upload limit.</strong> {@code StorageService} checks an
 * object's size once, at confirm, but the presigned PUT stays usable until it expires — so a
 * confirmed photo can be overwritten afterwards with something far larger, and reading it whole
 * would put all of it on the heap before the thumbnailer's pixel budget ever looked at it. So a read
 * asks storage for one byte past the limit and refuses the object if that byte arrives: the same cap
 * confirm enforces, applied again at the moment the bytes are used.
 */
@Component
public class MinioImageObjectStore implements ImageObjectStore {

    private final MinioClient client;
    private final long maxObjectBytes;

    @Autowired
    public MinioImageObjectStore(@Qualifier("internalMinioClient") MinioClient internalMinioClient,
                                 StorageProperties storage) {
        this(internalMinioClient, storage.getMaxUploadSizeBytes());
    }

    /** For tests: a caller-chosen limit. */
    MinioImageObjectStore(MinioClient client, long maxObjectBytes) {
        this.client = client;
        this.maxObjectBytes = maxObjectBytes;
    }

    @Override
    public byte[] read(String bucket, String objectKey) {
        long wanted = maxObjectBytes + 1;
        byte[] bytes;
        try (InputStream in = client.getObject(GetObjectArgs.builder()
                .bucket(bucket)
                .object(objectKey)
                // A range, so the rest of an oversized object never crosses the network at all...
                .offset(0L)
                .length(wanted)
                .build())) {
            // ...and a bounded read, in case storage ever answers a range with the whole object.
            bytes = in.readNBytes((int) Math.min(wanted, Integer.MAX_VALUE - 8));
        } catch (Exception e) {
            throw new Thumbnailer.ThumbnailUnavailableException(
                    "could not read " + bucket + "/" + objectKey, e);
        }
        if (bytes.length > maxObjectBytes) {
            throw new Thumbnailer.ThumbnailUnavailableException(bucket + "/" + objectKey
                    + " is larger than the " + maxObjectBytes + "-byte upload limit");
        }
        return bytes;
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
