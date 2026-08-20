package com.delivery.platform.storage;

import java.time.Instant;
import java.util.UUID;

/**
 * A one-shot permission to write exactly one object.
 *
 * <p>The client PUTs the bytes straight to MinIO with this URL, bypassing the backend entirely —
 * Section 5 is explicit that large uploads should not stream through a service. It then calls the
 * confirm endpoint with {@link #fileId()} so the service can verify the object actually landed.
 */
public record PresignedUpload(
        UUID fileId,
        String uploadUrl,
        String objectKey,
        String bucket,
        String contentType,
        Instant expiresAt,
        long maxSizeBytes) {
}
