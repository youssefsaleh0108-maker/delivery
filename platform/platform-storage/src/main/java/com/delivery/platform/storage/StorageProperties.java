package com.delivery.platform.storage;

import java.time.Duration;
import java.util.List;

import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "delivery.storage.minio")
public class StorageProperties {

    /** Internal endpoint, used for server-side operations (stat, remove, bucket checks). */
    private String endpoint = "http://localhost:9000";

    /**
     * The endpoint a browser or mobile client can actually reach. Presigned URLs are signed for
     * this host, not {@link #endpoint} — the signature covers the host header, so a URL signed for
     * the internal name is rejected when the client resolves it externally.
     */
    private String publicEndpoint = "http://localhost:9010";

    /** From Vault via the Config Server. No client ever holds these (Section 5). */
    private String accessKey;
    private String secretKey;

    private String region = "us-east-1";

    /**
     * How long a presigned URL stays valid. Deliberately short: Section 10 asks for tightly scoped
     * presigned URLs, and these grant write access to a specific object with no further auth.
     */
    private Duration presignTtl = Duration.ofMinutes(10);

    /** Upper bound enforced when the URL is issued, before any bytes move. */
    private long maxUploadSizeBytes = 10L * 1024 * 1024;

    private List<String> allowedImageContentTypes = List.of(
            "image/jpeg", "image/png", "image/webp");

    public String getEndpoint() {
        return endpoint;
    }

    public void setEndpoint(String endpoint) {
        this.endpoint = endpoint;
    }

    public String getPublicEndpoint() {
        return publicEndpoint;
    }

    public void setPublicEndpoint(String publicEndpoint) {
        this.publicEndpoint = publicEndpoint;
    }

    public String getAccessKey() {
        return accessKey;
    }

    public void setAccessKey(String accessKey) {
        this.accessKey = accessKey;
    }

    public String getSecretKey() {
        return secretKey;
    }

    public void setSecretKey(String secretKey) {
        this.secretKey = secretKey;
    }

    public String getRegion() {
        return region;
    }

    public void setRegion(String region) {
        this.region = region;
    }

    public Duration getPresignTtl() {
        return presignTtl;
    }

    public void setPresignTtl(Duration presignTtl) {
        this.presignTtl = presignTtl;
    }

    public long getMaxUploadSizeBytes() {
        return maxUploadSizeBytes;
    }

    public void setMaxUploadSizeBytes(long maxUploadSizeBytes) {
        this.maxUploadSizeBytes = maxUploadSizeBytes;
    }

    public List<String> getAllowedImageContentTypes() {
        return allowedImageContentTypes;
    }

    public void setAllowedImageContentTypes(List<String> allowedImageContentTypes) {
        this.allowedImageContentTypes = allowedImageContentTypes;
    }
}
