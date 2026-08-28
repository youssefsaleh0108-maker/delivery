package com.delivery.onboarding.api;

import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.delivery.onboarding.client.PlatformClient;
import com.delivery.onboarding.domain.ProviderProfile;
import com.delivery.onboarding.service.OnboardingService;
import com.delivery.onboarding.service.ProviderProfileService;
import com.delivery.platform.security.CurrentUser;
import com.delivery.platform.storage.PresignedUpload;
import com.delivery.platform.storage.StorageException;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

/**
 * A delivery company's own settings: logo, dispatch regions, operating hours.
 *
 * <p>Writes are CARRIER-only and, on every endpoint, checked against Order Manager's record that
 * the caller actually runs this company — the provider id in the path is the caller's claim, not
 * evidence, exactly as on the applicant-review endpoints. BACKOFFICE can read any company's
 * profile (support looking at what a carrier is looking at) and can change none of it: these are
 * the company's own settings, and a support edit would be indistinguishable from the company's.
 */
@RestController
@RequestMapping("/api/onboarding/providers/{providerId}/profile")
public class ProviderProfileController {

    /** For refusing a storage message that may name an object key. See the handler below. */
    private static final org.slf4j.Logger LOG =
            org.slf4j.LoggerFactory.getLogger(ProviderProfileController.class);

    private final ProviderProfileService profiles;
    private final PlatformClient platform;

    public ProviderProfileController(ProviderProfileService profiles, PlatformClient platform) {
        this.profiles = profiles;
        this.platform = platform;
    }

    // ---------------------------------------------------------------- shapes

    /**
     * The whole settings form, replaced wholesale — PUT semantics, so a deleted region stays
     * deleted. Deep validation (day names, HH:mm, open before close, region caps) lives in the
     * service, where the rules are written once.
     *
     * @param operatingHours day name to {@code {"open": "08:00", "close": "22:00"}}; a day absent
     *                       means closed that day
     */
    public record ProfileRequest(
            @NotNull @Size(max = ProviderProfileService.MAX_REGIONS) List<String> dispatchRegions,
            @NotNull Map<String, Map<String, String>> operatingHours) {
    }

    /**
     * What everyone reads back. {@code logoUrl} is the plain public URL (the bucket is
     * public-read, like store artwork) and null while there is no confirmed logo. A company that
     * never saved settings reads as empty lists — never a 404, because the settings screen has to
     * render something to edit.
     */
    public record ProfileView(UUID providerId, String logoUrl,
                              List<String> dispatchRegions,
                              Map<String, Map<String, String>> operatingHours,
                              String updatedBy, Instant updatedAt) {

        static ProfileView empty(UUID providerId) {
            return new ProfileView(providerId, null, List.of(), Map.of(), null, null);
        }
    }

    /** The client declares what it intends to upload; the service decides where it may go. */
    public record LogoPresignRequest(@NotBlank @Size(max = 128) String contentType) {
    }

    public record LogoConfirmRequest(@NotNull UUID fileId) {
    }

    // ---------------------------------------------------------------- reading

    /**
     * The company's settings. CARRIER staff of this company, or BACKOFFICE reading any —
     * the ownership check is skipped exactly and only for a caller whose BACKOFFICE role already
     * entitles them to every application's far more sensitive record.
     */
    @GetMapping
    @PreAuthorize("hasAnyRole('CARRIER', 'BACKOFFICE')")
    public ProfileView profile(@PathVariable UUID providerId) {
        if (!CurrentUser.hasRole("BACKOFFICE")) {
            requireRuns(providerId);
        }
        return profiles.forProvider(providerId)
                .map(this::view)
                .orElseGet(() -> ProfileView.empty(providerId));
    }

    // ---------------------------------------------------------------- writing

    /** Replaces regions and hours. CARRIER staff of this company only. */
    @PutMapping
    @PreAuthorize("hasRole('CARRIER')")
    public ProfileView save(@PathVariable UUID providerId,
                            @Valid @RequestBody ProfileRequest request) {
        requireRuns(providerId);
        return view(profiles.save(providerId, CurrentUser.requireId(),
                request.dispatchRegions(), request.operatingHours()));
    }

    /**
     * Step 1 of the logo upload: a one-shot presigned PUT into the public product-images bucket.
     * (Step 2 is the client's own PUT straight to storage, which never touches this service.)
     */
    @PostMapping("/logo/presign")
    @PreAuthorize("hasRole('CARRIER')")
    public ResponseEntity<OnboardingController.PresignUploadResponse> presignLogo(
            @PathVariable UUID providerId, @Valid @RequestBody LogoPresignRequest request) {
        requireRuns(providerId);
        PresignedUpload upload = profiles.presignLogo(
                providerId, CurrentUser.requireId(), request.contentType());
        return ResponseEntity.status(HttpStatus.CREATED)
                .body(OnboardingController.PresignUploadResponse.of(upload));
    }

    /** Step 3: the bytes landed; point the profile at them and hand back the public URL. */
    @PostMapping("/logo/confirm")
    @PreAuthorize("hasRole('CARRIER')")
    public ProfileView confirmLogo(@PathVariable UUID providerId,
                                   @Valid @RequestBody LogoConfirmRequest request) {
        requireRuns(providerId);
        return view(profiles.confirmLogo(providerId, CurrentUser.requireId(), request.fileId()));
    }

    // ---------------------------------------------------------------- assembling

    private ProfileView view(ProviderProfile profile) {
        return new ProfileView(profile.getProviderId(),
                profiles.logoUrl(profile).orElse(null),
                profile.getDispatchRegions(), profile.getOperatingHours(),
                profile.getUpdatedBy(), profile.getUpdatedAt());
    }

    /** 403 unless this caller runs this company — same check, same reason as everywhere else. */
    private void requireRuns(UUID providerId) {
        if (!platform.isStaffOf(providerId, CurrentUser.requireId())) {
            throw new OnboardingService.NotYourCompanyException(
                    "That is not your delivery company");
        }
    }

    // ---------------------------------------------------------------- answers

    @ExceptionHandler(OnboardingService.NotYourCompanyException.class)
    public ResponseEntity<Map<String, String>> notYours(
            OnboardingService.NotYourCompanyException e) {
        return ResponseEntity.status(HttpStatus.FORBIDDEN).body(Map.of("message", e.getMessage()));
    }

    /** 422: the settings cannot be saved as asked, and the message says what to fix. */
    @ExceptionHandler(ProviderProfileService.ProfileRuleException.class)
    public ResponseEntity<Map<String, String>> rule(
            ProviderProfileService.ProfileRuleException e) {
        return ResponseEntity.unprocessableEntity().body(Map.of("message", e.getMessage()));
    }

    /**
     * 422 with a generic message, matching how the document endpoints answer the same exception:
     * a storage failure is far more often the client's (never uploaded, too large) than MinIO's,
     * and platform-storage's own messages can name object keys, which nobody outside needs.
     */
    @ExceptionHandler(StorageException.class)
    public ResponseEntity<Map<String, String>> storage(StorageException e) {
        LOG.warn("A logo storage operation failed", e);
        return ResponseEntity.unprocessableEntity().body(Map.of(
                "message", "That upload could not be completed. Upload the file again."));
    }
}
