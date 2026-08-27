package com.delivery.notifications.api;

import java.util.ArrayList;
import java.util.List;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

import com.delivery.notifications.domain.NotificationCategory;
import com.delivery.notifications.service.NotificationPreferenceService;
import com.delivery.platform.notifications.NotificationCommand;
import com.delivery.platform.security.CurrentUser;

/**
 * The settings screen's notification preferences row.
 *
 * <p>The user's own settings are addressed as {@code /mine} rather than by a path id, on the same
 * reasoning as the notification log's own view: with no id in the route there is nothing for a
 * caller to change, and ownership comes from the token's {@code sub} rather than from something the
 * client sent (Section 3). Support gets a separate, read-only, BACKOFFICE-gated view — reading
 * somebody's settings answers "why did they not get it", and writing them on their behalf is a
 * consent decision nobody in an operations seat should be able to make.
 */
@RestController
@RequestMapping("/api/notification-preferences")
public class NotificationPreferenceController {

    /**
     * A cap, because the grid is a known size and a request larger than it is not a settings screen.
     * Every category on every channel is sixteen; the allowance is generous enough that adding a
     * category does not need a code change here, and small enough that this is not an endpoint for
     * writing arbitrary volumes of rows.
     */
    private static final int MAX_CHANGES = 64;

    private final NotificationPreferenceService preferences;

    public NotificationPreferenceController(NotificationPreferenceService preferences) {
        this.preferences = preferences;
    }

    /**
     * The caller's complete grid, defaults filled in.
     *
     * <p>Authenticated but unrestricted by role: every user of the platform has notification
     * settings, and a customer, a rider and a merchant all reach their own the same way.
     */
    @GetMapping("/mine")
    public List<NotificationPreferenceService.Setting> mine() {
        return preferences.settingsFor(CurrentUser.requireId());
    }

    /**
     * Saves the caller's changes.
     *
     * <p>A partial update — the body carries only what the user touched — rather than the whole
     * grid. Two devices open on the settings screen would otherwise have the second save silently
     * revert whatever the first changed, because a whole-grid PUT cannot tell a value the user set
     * from one it merely read a moment ago.
     */
    @PutMapping("/mine")
    public ResponseEntity<List<NotificationPreferenceService.Setting>> update(
            @Valid @RequestBody PreferenceUpdate request) {

        List<NotificationPreferenceService.Change> changes = new ArrayList<>();
        for (ChangeRequest change : request.changes()) {
            // Parsed here rather than bound directly to the enums, so an unknown value is a 400 with
            // our wording. The user's string is deliberately NOT repeated back: it is untrusted
            // input, and an error body is rendered somewhere by somebody sooner or later.
            NotificationCategory category = NotificationCategory.of(change.category())
                    .orElseThrow(() -> new ResponseStatusException(
                            HttpStatus.BAD_REQUEST, "unknown notification category"));
            String channel = channel(change.channel());
            changes.add(new NotificationPreferenceService.Change(
                    category, channel, change.enabled()));
        }

        try {
            preferences.apply(CurrentUser.requireId(), changes);
        } catch (IllegalArgumentException e) {
            // Turning off an account-critical category. Refused with the reason rather than accepted
            // and ignored — see NotificationPreferenceService#apply. The message is our own text.
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, e.getMessage());
        }

        // The saved grid comes back, so a client never has to guess what its own write produced —
        // and sees immediately that a locked category stayed on.
        return ResponseEntity.ok(preferences.settingsFor(CurrentUser.requireId()));
    }

    /**
     * One user's settings, for support.
     *
     * <p>Read-only on purpose. "Why did this customer not get the SMS" is answered by looking, and
     * an operator quietly re-enabling marketing for somebody who turned it off is the failure this
     * endpoint must not be able to cause.
     */
    @GetMapping("/{recipientId}")
    @PreAuthorize("hasRole('BACKOFFICE')")
    public List<NotificationPreferenceService.Setting> forRecipient(
            @PathVariable @Size(max = 64) String recipientId) {
        return preferences.settingsFor(recipientId);
    }

    private static String channel(String supplied) {
        String candidate = supplied == null ? "" : supplied.trim()
                .toUpperCase(java.util.Locale.ROOT);
        if (!NotificationPreferenceService.CHANNELS.contains(candidate)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "unknown channel");
        }
        return candidate;
    }

    /**
     * @param changes only the settings the user touched
     */
    public record PreferenceUpdate(
            @NotEmpty @Size(max = MAX_CHANGES) List<@Valid ChangeRequest> changes) {
    }

    /**
     * @param category one of {@link NotificationCategory}
     * @param channel  one of {@link NotificationCommand}'s channel constants
     */
    public record ChangeRequest(
            @NotNull @Size(max = 32) String category,
            @NotNull @Size(max = 16) String channel,
            @NotNull Boolean enabled) {
    }
}
