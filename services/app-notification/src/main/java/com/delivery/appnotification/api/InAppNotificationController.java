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

    /**
     * A screenful, not an inbox. Someone with two days of orders behind them was being sent fifty
     * rendered messages to fill a list that shows a handful.
     */
    private static final int DEFAULT_SIZE = 20;

    private final InAppMessageService messages;

    public InAppNotificationController(InAppMessageService messages) {
        this.messages = messages;
    }

    /**
     * One page of the caller's inbox, in the envelope every other list on the platform returns.
     *
     * <p>{@code page} and {@code size} were previously accepted and ignored, so a client that asked
     * for the second page silently got the first one again.
     */
    @GetMapping
    public PageResponse<MessageResponse> inbox(
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "" + DEFAULT_SIZE) int size) {

        return PageResponse.of(messages
                .inbox(CurrentUser.requireId(), Math.max(0, page),
                        Math.max(1, Math.min(size, MAX_LIMIT)))
                .map(InAppNotificationController::toResponse));
    }

    /**
     * The same inbox as a bare array, for a caller that asks with {@code limit}.
     *
     * <p>The shipped app parses this response as a list and would fail on an envelope, so the old
     * shape is kept for the old parameter rather than broken from under phones that are already in
     * pockets. Nothing new should use it: it cannot say how many messages there are, which is the
     * reason the paged form above exists.
     */
    @GetMapping(params = "limit")
    public List<MessageResponse> inbox(@RequestParam int limit) {
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

    /** Envelope for paged results, so clients aren't coupled to Spring's Page serialisation. */
    public record PageResponse<T>(
            List<T> content,
            int page,
            int size,
            long totalElements,
            int totalPages) {

        public static <T> PageResponse<T> of(org.springframework.data.domain.Page<T> page) {
            return new PageResponse<>(
                    page.getContent(),
                    page.getNumber(),
                    page.getSize(),
                    page.getTotalElements(),
                    page.getTotalPages());
        }
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
