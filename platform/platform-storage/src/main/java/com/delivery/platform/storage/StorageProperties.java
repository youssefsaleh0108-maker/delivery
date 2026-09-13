package com.delivery.platform.storage;

import java.time.Duration;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

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

    /**
     * Per purpose, the content types an upload may declare — replacing that purpose's built-in
     * list ({@link FilePurpose#defaultContentTypes()}) and no other purpose's. Empty unless a service
     * configures it:
     *
     * <pre>
     * delivery.storage.minio.allowed-content-types:
     *   ORDER_ATTACHMENT: [application/pdf]
     * </pre>
     */
    private Map<FilePurpose, List<String>> allowedContentTypes = new LinkedHashMap<>();

    /**
     * No longer consulted (since 0.1.3). This one list, named for images, used to apply to every
     * purpose, so accepting a PDF anywhere meant accepting it everywhere — onboarding-service's
     * applicant documents let PDF into its public product-images bucket that way. Content types are
     * per purpose now: see {@link FilePurpose} and {@link #allowedContentTypes}.
     *
     * <p>Still bound, and null unless a service sets it, only so that a service which still does is
     * told so at startup by {@link StorageService} rather than silently behaving differently.
     *
     * @deprecated set {@code allowed-content-types.<PURPOSE>} instead, for the purpose that needs it
     */
    @Deprecated(since = "0.1.3")
    private List<String> allowedImageContentTypes;

    /**
     * The content types an upload for {@code purpose} may declare: the service's configured list for
     * that purpose when it has one, otherwise the purpose's own.
     */
    public List<String> allowedContentTypesFor(FilePurpose purpose) {
        List<String> configured = allowedContentTypes.get(purpose);
        return configured != null ? List.copyOf(configured) : purpose.defaultContentTypes();
    }

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

    public Map<FilePurpose, List<String>> getAllowedContentTypes() {
        return allowedContentTypes;
    }

    public void setAllowedContentTypes(Map<FilePurpose, List<String>> allowedContentTypes) {
        this.allowedContentTypes = allowedContentTypes;
    }

    /** @deprecated not consulted; see the field. */
    @Deprecated(since = "0.1.3")
    public List<String> getAllowedImageContentTypes() {
        return allowedImageContentTypes;
    }

    /** @deprecated not consulted; see the field. */
    @Deprecated(since = "0.1.3")
    public void setAllowedImageContentTypes(List<String> allowedImageContentTypes) {
        this.allowedImageContentTypes = allowedImageContentTypes;
    }
}
