package com.delivery.onboarding.service;

import java.util.Optional;
import java.util.Set;
import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.onboarding.domain.UserProfile;
import com.delivery.onboarding.domain.UserProfileRepository;
import com.delivery.platform.storage.FileMetadata;
import com.delivery.platform.storage.FileMetadataRepository;
import com.delivery.platform.storage.FilePurpose;
import com.delivery.platform.storage.PresignedUpload;
import com.delivery.platform.storage.StorageService;

/**
 * The account's own picture, through the same three-step presigned flow every other image uses.
 *
 * <p>Unlike store artwork this lands in the PRIVATE user-avatars bucket: a selfie is shown back
 * to its owner on their own account screen, not marketed to the public, so reads come out as
 * short-lived presigned URLs from {@link StorageService#readUrl} rather than plain public ones.
 *
 * <p>The owner is always the caller — there is no id in any signature that could name somebody
 * else's profile, which is the whole access-control story here.
 */
@Service
public class UserAvatarService {

    private static final Logger log = LoggerFactory.getLogger(UserAvatarService.class);

    /** Same allow-list as every merchant-supplied image; the storage layer re-checks. */
    private static final Set<String> AVATAR_CONTENT_TYPES =
            Set.of("image/jpeg", "image/png", "image/webp");

    private final UserProfileRepository profiles;
    private final StorageService storage;
    private final FileMetadataRepository files;

    public UserAvatarService(UserProfileRepository profiles, StorageService storage,
                             FileMetadataRepository files) {
        this.profiles = profiles;
        this.storage = storage;
        this.files = files;
    }

    /** Step 1: a one-shot URL to PUT the picture straight to storage. */
    @Transactional
    public PresignedUpload presign(String userRef, String contentType) {
        if (!AVATAR_CONTENT_TYPES.contains(contentType)) {
            throw new ProviderProfileService.ProfileRuleException(
                    "A profile picture must be a JPEG, PNG or WebP image, not " + contentType);
        }
        // Namespaced by owner so the bucket stays browsable, exactly like products/{id}.
        return storage.presignUpload(userRef, FilePurpose.USER_AVATAR, contentType,
                "users/" + userRef);
    }

    /**
     * Step 3: the bytes landed, so point the profile at them.
     *
     * <p>{@code confirmUpload} verifies the file belongs to the caller; the prefix check verifies
     * it was presigned for the caller's own folder — the same two-sided check the provider logo
     * runs, so one account cannot confirm its upload onto another's profile.
     *
     * <p>The picture being replaced is discarded, for the same reason {@link #remove} discards one:
     * somebody who changes their photo has stopped consenting to the old one, and a private object
     * nobody points at is still readable by whoever holds a presigned URL for it.
     */
    @Transactional
    public UserProfile confirm(String userRef, UUID fileId) {
        FileMetadata metadata = storage.confirmUpload(fileId, userRef);

        String expectedPrefix = "users/" + userRef + "/";
        if (!metadata.getObjectKey().startsWith(expectedPrefix)) {
            throw new ProviderProfileService.ProfileRuleException(
                    "That upload was not started for this account");
        }

        UserProfile profile = profiles.findById(userRef)
                .orElseGet(() -> new UserProfile(userRef));
        String replaced = profile.getAvatarObjectKey();
        profile.updateAvatar(metadata.getObjectKey());
        profiles.save(profile);

        // Only when it is a different object. Confirming the same upload twice is how a retried
        // request arrives, and deleting the object this call just adopted would leave the account
        // pointing at nothing.
        if (!metadata.getObjectKey().equals(replaced)) {
            discard(userRef, replaced);
        }

        log.info("User {} avatar updated", userRef);
        return profile;
    }

    /**
     * Removes the picture — from the profile, from {@code file_metadata} and from the bucket.
     *
     * <p>Clearing the reference alone was not deletion, whatever the account screen said. Reads of
     * this bucket are presigned GETs that stay valid for their whole TTL, so a URL minted just
     * before the click keeps serving the face for minutes afterwards, and the object and its row
     * outlive the account itself — a picture of a person we were asked to stop holding. Removing
     * the object is what makes the promise on the button true, and it is why this is a privacy
     * matter rather than the storage-cost one the provider logo can afford to be.
     *
     * <p>Deleting is possible here precisely because an avatar's uploader is always its subject:
     * the storage layer's ownership check passes for the account itself, where a company logo
     * uploaded by one staff member and removed by another would rightly be refused.
     */
    @Transactional
    public void remove(String userRef) {
        profiles.findById(userRef).ifPresent(profile -> {
            String removed = profile.getAvatarObjectKey();
            profile.clearAvatar();
            profiles.save(profile);
            discard(userRef, removed);
            log.info("User {} avatar removed", userRef);
        });
    }

    /**
     * Drops one avatar object and its metadata row.
     *
     * <p>A key with no row is not an error worth failing a removal over: it means the upload was
     * never confirmed or was cleaned up already, and either way there is nothing left to serve.
     */
    private void discard(String userRef, String objectKey) {
        if (objectKey == null) {
            return;
        }
        files.findByBucketAndObjectKey(FilePurpose.USER_AVATAR.bucket(), objectKey)
                .ifPresent(metadata -> storage.softDelete(metadata.getId(), userRef));
    }

    @Transactional(readOnly = true)
    public Optional<UserProfile> find(String userRef) {
        return profiles.findById(userRef);
    }

    /**
     * A URL the account can see its own picture at — presigned and short-lived, because the
     * bucket is private. Empty when there is no avatar or its upload was never confirmed.
     */
    @Transactional(readOnly = true)
    public Optional<String> avatarUrl(UserProfile profile) {
        if (profile.getAvatarObjectKey() == null) {
            return Optional.empty();
        }
        return files.findByBucketAndObjectKey(
                        FilePurpose.USER_AVATAR.bucket(), profile.getAvatarObjectKey())
                .filter(metadata -> metadata.getStatus() == FileMetadata.Status.UPLOADED)
                .map(storage::readUrl);
    }
}
