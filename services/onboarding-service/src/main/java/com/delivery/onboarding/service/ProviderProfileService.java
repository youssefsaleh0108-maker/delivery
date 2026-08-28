package com.delivery.onboarding.service;

import java.time.DayOfWeek;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import java.util.regex.Pattern;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.onboarding.domain.ProviderProfile;
import com.delivery.onboarding.domain.ProviderProfileRepository;
import com.delivery.platform.storage.FileMetadata;
import com.delivery.platform.storage.FileMetadataRepository;
import com.delivery.platform.storage.FilePurpose;
import com.delivery.platform.storage.PresignedUpload;
import com.delivery.platform.storage.StorageService;

/**
 * The carrier settings screen's real fields: logo, dispatch regions, operating hours.
 *
 * <p>The logo goes through the same three-step presigned flow product images use, into the same
 * publicly-readable product-images bucket, and for the same reason: company artwork is made to be
 * shown, and a plain CDN-cacheable URL is the right shape for it. Nothing else about the KYC
 * document flow applies here — a logo is not identity papers.
 *
 * <p>Whether the caller may touch this provider at all is decided in the controller, against
 * Order Manager's record of who runs what, before any method here runs. This service owns what
 * the values may be.
 */
@Service
public class ProviderProfileService {

    private static final Logger log = LoggerFactory.getLogger(ProviderProfileService.class);

    /** "08:00" — the shape the validation note in the API promises. */
    private static final Pattern TIME = Pattern.compile("^([01]\\d|2[0-3]):[0-5]\\d$");

    /**
     * Logos are images, full stop. Narrower than the platform storage list on purpose: that list
     * had PDF added for KYC documents, and a "logo" that is a PDF renders as a broken tile in
     * every client. SVG stays out for the reason the storage config documents — it is script.
     */
    private static final Set<String> LOGO_CONTENT_TYPES =
            Set.of("image/jpeg", "image/png", "image/webp");

    /** Enough for any real coverage map; small enough that the field cannot become a dumping ground. */
    public static final int MAX_REGIONS = 20;
    public static final int MAX_REGION_LENGTH = 80;

    private final ProviderProfileRepository profiles;
    private final StorageService storage;
    private final FileMetadataRepository files;

    public ProviderProfileService(ProviderProfileRepository profiles, StorageService storage,
                                  FileMetadataRepository files) {
        this.profiles = profiles;
        this.storage = storage;
        this.files = files;
    }

    /** Thrown when the settings cannot be saved as asked. Answers 422; the message is actionable. */
    public static class ProfileRuleException extends RuntimeException {
        public ProfileRuleException(String message) {
            super(message);
        }
    }

    // ---------------------------------------------------------------- reading

    /**
     * The profile, or empty when the company never saved one. The caller renders empty as empty
     * settings — no row is invented for a company that never opened the screen.
     */
    @Transactional(readOnly = true)
    public Optional<ProviderProfile> forProvider(UUID providerId) {
        return profiles.findById(providerId);
    }

    /**
     * A URL a client can show the logo from — the plain public URL, since the bucket is
     * public-read. Empty when there is no logo, or when its upload was never confirmed.
     */
    @Transactional(readOnly = true)
    public Optional<String> logoUrl(ProviderProfile profile) {
        if (profile.getLogoObjectKey() == null) {
            return Optional.empty();
        }
        return files.findByBucketAndObjectKey(
                        FilePurpose.PRODUCT_IMAGE.bucket(), profile.getLogoObjectKey())
                .filter(metadata -> metadata.getStatus() == FileMetadata.Status.UPLOADED)
                .map(storage::readUrl);
    }

    // ---------------------------------------------------------------- settings

    /**
     * Replaces the settings wholesale — PUT semantics, because the settings screen submits the
     * whole form and a partial merge would resurrect values the carrier just deleted.
     *
     * <p>Everything is validated before anything is written, and the stored values are the
     * normalised ones (trimmed regions, upper-cased day names), so two spellings of the same
     * settings are one stored shape.
     */
    @Transactional
    public ProviderProfile save(UUID providerId, String actor, List<String> dispatchRegions,
                                Map<String, Map<String, String>> operatingHours) {
        List<String> regions = validatedRegions(dispatchRegions);
        Map<String, Map<String, String>> hours = validatedHours(operatingHours);

        ProviderProfile profile = profiles.findById(providerId)
                .orElseGet(() -> new ProviderProfile(providerId));
        profile.updateSettings(regions, hours, actor);
        profiles.save(profile);

        log.info("Provider {} settings saved by {}", providerId, actor);
        return profile;
    }

    // ---------------------------------------------------------------- the logo

    /** Step 1 of the same three-step flow product images use. Ownership was checked by the caller. */
    @Transactional
    public PresignedUpload presignLogo(UUID providerId, String uploaderUserRef,
                                       String contentType) {
        if (!LOGO_CONTENT_TYPES.contains(contentType)) {
            throw new ProfileRuleException(
                    "A logo must be a JPEG, PNG or WebP image, not " + contentType);
        }
        // Namespaced by provider so the bucket stays browsable, exactly like products/{id}.
        return storage.presignUpload(uploaderUserRef, FilePurpose.PRODUCT_IMAGE, contentType,
                "providers/" + providerId);
    }

    /**
     * Step 3: the bytes landed, so point the profile at them.
     *
     * <p>{@code confirmUpload} verifies the file belongs to the caller; the prefix check verifies
     * it was presigned for <em>this</em> provider — the same two-sided check the document flow
     * runs, so staff of two companies cannot confirm one company's upload onto the other.
     *
     * <p>A replaced logo's object is left in the bucket rather than deleted: the old file may have
     * been uploaded by a different staff member, whom the storage layer's ownership check would
     * rightly refuse to delete for, and an orphaned public image is a storage cost, not a leak.
     */
    @Transactional
    public ProviderProfile confirmLogo(UUID providerId, String uploaderUserRef, UUID fileId) {
        FileMetadata metadata = storage.confirmUpload(fileId, uploaderUserRef);

        String expectedPrefix = "providers/" + providerId + "/";
        if (!metadata.getObjectKey().startsWith(expectedPrefix)) {
            throw new ProfileRuleException("That upload was not started for this company");
        }

        ProviderProfile profile = profiles.findById(providerId)
                .orElseGet(() -> new ProviderProfile(providerId));
        profile.updateLogo(metadata.getObjectKey(), uploaderUserRef);
        profiles.save(profile);

        log.info("Provider {} logo updated by {}", providerId, uploaderUserRef);
        return profile;
    }

    // ---------------------------------------------------------------- validation

    /**
     * Trimmed, non-blank, capped, and no duplicates. Duplicates are refused rather than silently
     * collapsed because the form should show the carrier what they typed, not a corrected version
     * of it.
     */
    private static List<String> validatedRegions(List<String> raw) {
        if (raw == null) {
            return List.of();
        }
        if (raw.size() > MAX_REGIONS) {
            throw new ProfileRuleException(
                    "At most " + MAX_REGIONS + " dispatch regions can be listed");
        }
        List<String> regions = new ArrayList<>();
        for (String region : raw) {
            String trimmed = region == null ? "" : region.trim();
            if (trimmed.isEmpty()) {
                throw new ProfileRuleException("A dispatch region cannot be blank");
            }
            if (trimmed.length() > MAX_REGION_LENGTH) {
                throw new ProfileRuleException("A dispatch region name is capped at "
                        + MAX_REGION_LENGTH + " characters");
            }
            if (regions.stream().anyMatch(existing -> existing.equalsIgnoreCase(trimmed))) {
                throw new ProfileRuleException("'" + trimmed + "' is listed twice");
            }
            regions.add(trimmed);
        }
        return List.copyOf(regions);
    }

    /**
     * Known days, HH:mm on a 24-hour clock, open strictly before close. A day absent means closed
     * — there is no "closed" marker to validate, absence is the marker. Day names are normalised
     * to upper case so "monday" and "MONDAY" are one key.
     */
    private static Map<String, Map<String, String>> validatedHours(
            Map<String, Map<String, String>> raw) {
        if (raw == null) {
            return Map.of();
        }
        Map<String, Map<String, String>> hours = new LinkedHashMap<>();
        for (Map.Entry<String, Map<String, String>> entry : raw.entrySet()) {
            String day = entry.getKey() == null ? ""
                    : entry.getKey().trim().toUpperCase(Locale.ROOT);
            try {
                DayOfWeek.valueOf(day);
            } catch (IllegalArgumentException e) {
                throw new ProfileRuleException("'" + entry.getKey() + "' is not a day of the week");
            }
            if (hours.containsKey(day)) {
                throw new ProfileRuleException(day + " is listed twice");
            }

            Map<String, String> window = entry.getValue();
            String open = window == null ? null : window.get("open");
            String close = window == null ? null : window.get("close");
            if (open == null || close == null
                    || (window.size() != 2)) {
                throw new ProfileRuleException(
                        day + " must have exactly an open and a close time");
            }
            if (!TIME.matcher(open).matches() || !TIME.matcher(close).matches()) {
                throw new ProfileRuleException(
                        day + " times must be HH:mm on a 24-hour clock");
            }
            // String comparison is time comparison for zero-padded HH:mm — that is why the
            // pattern insists on the padding.
            if (open.compareTo(close) >= 0) {
                throw new ProfileRuleException(
                        day + " must open before it closes (" + open + "–" + close + ")");
            }
            hours.put(day, Map.of("open", open, "close", close));
        }
        return Map.copyOf(hours);
    }
}
