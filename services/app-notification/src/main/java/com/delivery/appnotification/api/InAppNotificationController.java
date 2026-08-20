package com.delivery.appnotification.api;

import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.delivery.appnotification.domain.InAppMessage;
import com.delivery.appnotification.service.InAppMessageService;
import com.delivery.platform.security.CurrentUser;

/**
 * The REST side of in-app notifications — the polling fallback the brief pairs with the WebSocket,
 * and the way the inbox is loaded on open.
 *
 * <p>Every endpoint is scoped to the caller's own {@code sub}. There is no path or query parameter
 * naming a user anywhere in this controller, which is what makes reading someone else's inbox not
 * merely forbidden but unexpressible.
 */
@RestController
@RequestMapping("/api/notifications")
public class InAppNotificationController {

    /** Enough for the inbox screen; the client asks for fewer if it wants a preview. */
    private static final int MAX_LIMIT = 100;

    private final InAppMessageService messages;

    public InAppNotificationController(InAppMessageService messages) {
        this.messages = messages;
    }

    @GetMapping
    public List<MessageResponse> inbox(@RequestParam(defaultValue = "50") int limit) {
        int capped = Math.max(1, Math.min(limit, MAX_LIMIT));
        return messages.inbox(CurrentUser.requireId(), capped).stream()
                .map(InAppNotificationController::toResponse)
                .toList();
    }

    /**
     * The badge count.
     *
     * <p>Its own endpoint because it is polled far more often than the list — every app foreground,
     * on a timer — and returning fifty full message bodies to render a number would be most of this
     * service's traffic.
     */
    @GetMapping("/unread-count")
    public Map<String, Long> unreadCount() {
        return Map.of("unread", messages.unreadCount(CurrentUser.requireId()));
    }

    @PostMapping("/{id}/read")
    public ResponseEntity<Void> markRead(@PathVariable UUID id) {
        boolean updated = messages.markRead(id, CurrentUser.requireId());
        // 404 for both "no such message" and "not yours": telling the two apart would confirm that
        // an id exists, which is a small but free information leak.
        return updated
                ? ResponseEntity.noContent().build()
                : ResponseEntity.status(HttpStatus.NOT_FOUND).build();
    }

    @PostMapping("/read-all")
    public Map<String, Integer> markAllRead() {
        return Map.of("updated", messages.markAllRead(CurrentUser.requireId()));
    }

    private static MessageResponse toResponse(InAppMessage message) {
        return new MessageResponse(
                message.getId(),
                message.getOrderId(),
                message.getEventType(),
                message.getTitle(),
                message.getBody(),
                message.getMetadata(),
                message.getReadAt() != null,
                message.getReadAt(),
                message.getCreatedAt());
    }

    public record MessageResponse(
            UUID id,
            UUID orderId,
            String eventType,
            String title,
            String body,
            Map<String, String> metadata,
            boolean read,
            Instant readAt,
            Instant createdAt) {
    }
}
