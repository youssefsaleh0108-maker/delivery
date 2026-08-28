package com.delivery.onboarding.domain;

import java.time.Instant;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * A delivery company's settings: logo, dispatch regions, operating hours.
 *
 * <p>Keyed by the Order Manager provider id — the company itself (slug, staff, riders) lives
 * there; what lives here is what the carrier portal's settings screen edits, none of which any
 * dispatch decision reads. The row is created lazily on the first save: a company that never
 * opened its settings has no row, and the API renders that as empty settings rather than
 * inventing a record.
 */
@Entity
@Table(name = "provider_profiles")
public class ProviderProfile {

    @Id
    @Column(name = "provider_id", nullable = false, updatable = false)
    private UUID providerId;

    /** Object key in the public product-images bucket. Null until a logo is confirmed uploaded. */
    @Column(name = "logo_object_key", length = 512)
    private String logoObjectKey;

    /** Region names as the carrier writes them. Validated (non-blank, capped) at the service. */
    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "dispatch_regions", columnDefinition = "jsonb", nullable = false)
    private List<String> dispatchRegions = new ArrayList<>();

    /**
     * Day name to {@code {"open": "08:00", "close": "22:00"}}. A day absent means closed. Kept as
     * a plain map rather than a typed record so the stored shape is exactly the wire shape — the
     * validation that makes it trustworthy runs in the service before anything lands here.
     */
    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "operating_hours", columnDefinition = "jsonb", nullable = false)
    private Map<String, Map<String, String>> operatingHours = new LinkedHashMap<>();

    @Column(name = "updated_by", length = 64)
    private String updatedBy;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt = Instant.now();

    @Column(name = "created_at", nullable = false, insertable = false, updatable = false)
    private Instant createdAt;

    protected ProviderProfile() {
        // for JPA
    }

    public ProviderProfile(UUID providerId) {
        this.providerId = providerId;
    }

    public void updateSettings(List<String> dispatchRegions,
                               Map<String, Map<String, String>> operatingHours, String actor) {
        this.dispatchRegions = dispatchRegions;
        this.operatingHours = operatingHours;
        touched(actor);
    }

    public void updateLogo(String logoObjectKey, String actor) {
        this.logoObjectKey = logoObjectKey;
        touched(actor);
    }

    private void touched(String actor) {
        this.updatedBy = actor;
        this.updatedAt = Instant.now();
    }

    public UUID getProviderId() {
        return providerId;
    }

    public String getLogoObjectKey() {
        return logoObjectKey;
    }

    public List<String> getDispatchRegions() {
        return dispatchRegions;
    }

    public Map<String, Map<String, String>> getOperatingHours() {
        return operatingHours;
    }

    public String getUpdatedBy() {
        return updatedBy;
    }

    public Instant getUpdatedAt() {
        return updatedAt;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }
}
