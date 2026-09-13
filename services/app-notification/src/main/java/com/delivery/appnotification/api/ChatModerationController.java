package com.delivery.appnotification.api;

import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import org.slf4j.MDC;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.delivery.appnotification.domain.ChatRoomMessage;
import com.delivery.appnotification.service.RoomModerationService;
import com.delivery.platform.observability.CorrelationIdFilter;
import com.delivery.platform.security.CurrentUser;

/**
 * The back office's moderation queue for neighbourhood rooms.
 *
 * <p>BACKOFFICE only, on the class, so no method can be added here without it. Under
 * {@code /api/chat/backoffice} beside the transcript endpoint, and like it: the actor is always the
 * token's subject, every action requires a stated reason, and every action is audited in the same
 * transaction (see {@code RoomModerationService}). Staff address a reported <em>message</em>; no
 * endpoint here takes an account id.
 */
// Deliberately NOT @Validated — see ChatBackofficeController for why it would turn a 400 into a 500.
@RestController
@RequestMapping("/api/chat/backoffice/moderation")
@PreAuthorize("hasRole('BACKOFFICE')")
public class ChatModerationController {

    private final RoomModerationService moderation;

    public ChatModerationController(RoomModerationService moderation) {
        this.moderation = moderation;
    }

    /** Reported messages awaiting a decision, oldest wait first. */
    @GetMapping("/reports")
    public List<RoomModerationService.ReportedMessage> queue() {
        return moderation.openQueue();
    }

    /** Removes the message from the room for everyone and closes its reports. */
    @PostMapping("/messages/{messageId}/hide")
    public HiddenView hide(@PathVariable UUID messageId, @Valid @RequestBody ReasonRequest request) {
        ChatRoomMessage message = moderation.hide(messageId, CurrentUser.requireId(),
                request.reason().strip(), MDC.get(CorrelationIdFilter.MDC_KEY));
        return new HiddenView(message.getId(), message.getHiddenAt());
    }

    /** Closes the reports and leaves the message. */
    @PostMapping("/messages/{messageId}/dismiss")
    public ResponseEntity<Void> dismiss(@PathVariable UUID messageId,
                                        @Valid @RequestBody ReasonRequest request) {
        moderation.dismiss(messageId, CurrentUser.requireId(), request.reason().strip(),
                MDC.get(CorrelationIdFilter.MDC_KEY));
        return ResponseEntity.noContent().build();
    }

    /** Mutes the message's author in that room for {@code hours}, at most a year. */
    @PostMapping("/messages/{messageId}/mute-author")
    public MutedView muteAuthor(@PathVariable UUID messageId, @Valid @RequestBody MuteRequest request) {
        Instant until = moderation.muteAuthor(messageId, CurrentUser.requireId(),
                Duration.ofHours(request.hours()), request.reason().strip(),
                MDC.get(CorrelationIdFilter.MDC_KEY));
        return new MutedView(messageId, until);
    }

    @PostMapping("/messages/{messageId}/unmute-author")
    public ResponseEntity<Void> unmuteAuthor(@PathVariable UUID messageId,
                                             @Valid @RequestBody ReasonRequest request) {
        moderation.unmuteAuthor(messageId, CurrentUser.requireId(), request.reason().strip(),
                MDC.get(CorrelationIdFilter.MDC_KEY));
        return ResponseEntity.noContent().build();
    }

    /** @param reason recorded in the audit row; required, and capped at the column's width */
    public record ReasonRequest(@NotBlank @Size(min = 3, max = 200) String reason) {
    }

    public record MuteRequest(@Min(1) @Max(8760) int hours,
                              @NotBlank @Size(min = 3, max = 200) String reason) {
    }

    public record HiddenView(UUID messageId, Instant hiddenAt) {
    }

    public record MutedView(UUID messageId, Instant mutedUntil) {
    }
}
