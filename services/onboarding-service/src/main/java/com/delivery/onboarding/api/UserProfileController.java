package com.delivery.onboarding.api;

import java.util.Map;
import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.delivery.onboarding.service.ProviderProfileService;
import com.delivery.onboarding.service.UserAvatarService;
import com.delivery.platform.security.CurrentUser;
import com.delivery.platform.storage.PresignedUpload;
import com.delivery.platform.storage.StorageException;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

/**
 * The signed-in account's own profile — today just the avatar.
 *
 * <p>Every endpoint is {@code /me}: the owner is always {@link CurrentUser#requireId()} and never
 * a path variable, so there is no ownership check to get wrong. Any signed-in role may set a
 * picture; a face is not a customer-only feature.
 */
@RestController
@RequestMapping("/api/profile/me")
public class UserProfileController {

    private static final Logger LOG = LoggerFactory.getLogger(UserProfileController.class);

    private final UserAvatarService avatars;

    public UserProfileController(UserAvatarService avatars) {
        this.avatars = avatars;
    }

    /** What the account screen renders: a short-lived viewing URL, or null for the monogram. */
    public record ProfileView(String avatarUrl) {
    }

    public record AvatarPresignRequest(@NotBlank @Size(max = 128) String contentType) {
    }

    public record AvatarConfirmRequest(@NotNull UUID fileId) {
    }

    @GetMapping
    @PreAuthorize("isAuthenticated()")
    public ProfileView mine() {
        String userRef = CurrentUser.requireId();
        return new ProfileView(avatars.find(userRef)
                .flatMap(avatars::avatarUrl)
                .orElse(null));
    }

    /** Step 1 of the same three-step flow every other image upload uses. */
    @PostMapping("/avatar/presign")
    @PreAuthorize("isAuthenticated()")
    public ResponseEntity<OnboardingController.PresignUploadResponse> presign(
            @Valid @RequestBody AvatarPresignRequest request) {
        PresignedUpload upload =
                avatars.presign(CurrentUser.requireId(), request.contentType());
        return ResponseEntity.status(HttpStatus.CREATED)
                .body(OnboardingController.PresignUploadResponse.of(upload));
    }

    /** Step 3: the bytes landed. Answers with the fresh viewing URL. */
    @PostMapping("/avatar/confirm")
    @PreAuthorize("isAuthenticated()")
    public ProfileView confirm(@Valid @RequestBody AvatarConfirmRequest request) {
        String userRef = CurrentUser.requireId();
        return new ProfileView(
                avatars.avatarUrl(avatars.confirm(userRef, request.fileId())).orElse(null));
    }

    @DeleteMapping("/avatar")
    @PreAuthorize("isAuthenticated()")
    public ProfileView remove() {
        avatars.remove(CurrentUser.requireId());
        return new ProfileView(null);
    }

    /** 422: the picture cannot be taken as sent, and the message says what to fix. */
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
        LOG.warn("An avatar storage operation failed", e);
        return ResponseEntity.unprocessableEntity().body(Map.of(
                "message", "That upload could not be completed. Pick the picture again."));
    }
}
