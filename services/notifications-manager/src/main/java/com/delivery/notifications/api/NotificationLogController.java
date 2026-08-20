package com.delivery.notifications.api;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.delivery.notifications.domain.NotificationLog;
import com.delivery.notifications.domain.NotificationLogRepository;
import com.delivery.platform.security.CurrentUser;

/**
 * The operator's answer to "why didn't this arrive" (Section 10).
 *
 * <p>Two views, and the split is deliberate. Backoffice can see any notification, including the
 * failure reason and which provider it went through — that is the whole point of keeping the log.
 * A customer can see only their own, and only that it was sent: exposing "SMTP relay rejected
 * 550 mailbox full" to an end user leaks infrastructure detail and helps nobody.
 */
@RestController
@RequestMapping("/api/notification-log")
public class NotificationLogController {

    private final NotificationLogRepository logs;

    public NotificationLogController(NotificationLogRepository logs) {
        this.logs = logs;
    }

    /** Everything sent about one order. The usual starting point for a support question. */
    @GetMapping("/orders/{orderId}")
    @PreAuthorize("hasRole('BACKOFFICE')")
    public List<LogEntry> forOrder(@PathVariable UUID orderId) {
        return logs.findByOrderIdOrderByCreatedAtDesc(orderId).stream()
                .map(NotificationLogController::detailed)
                .toList();
    }

    /** Everything sent to one user. */
    @GetMapping("/recipients/{recipientId}")
    @PreAuthorize("hasRole('BACKOFFICE')")
    public List<LogEntry> forRecipient(@PathVariable String recipientId) {
        return logs.findByRecipientIdOrderByCreatedAtDesc(recipientId).stream()
                .map(NotificationLogController::detailed)
                .toList();
    }

    /**
     * The caller's own notification history.
     *
     * <p>Scoped by the token's {@code sub} rather than a path parameter, so there is no id for a
     * caller to change — ownership is enforced in service code, not by the route (Section 3).
     */
    @GetMapping("/mine")
    public List<LogEntry> mine() {
        return logs.findByRecipientIdOrderByCreatedAtDesc(CurrentUser.requireId()).stream()
                .map(NotificationLogController::redacted)
                .toList();
    }

    private static LogEntry detailed(NotificationLog entry) {
        return new LogEntry(
                entry.getId(), entry.getOrderId(), entry.getChannel(), entry.getRecipient(),
                entry.getEventType(), entry.getSubject(), entry.getBody(),
                entry.getStatus().name(), entry.getProvider(), entry.getFailureReason(),
                entry.getCreatedAt(), entry.getSentAt());
    }

    /**
     * The same row without the operational detail: no recipient address (it may be a device token),
     * no provider, no failure reason.
     */
    private static LogEntry redacted(NotificationLog entry) {
        return new LogEntry(
                entry.getId(), entry.getOrderId(), entry.getChannel(), null,
                entry.getEventType(), entry.getSubject(), entry.getBody(),
                entry.getStatus().name(), null, null,
                entry.getCreatedAt(), entry.getSentAt());
    }

    public record LogEntry(
            UUID id,
            UUID orderId,
            String channel,
            String recipient,
            String eventType,
            String subject,
            String body,
            String status,
            String provider,
            String failureReason,
            Instant createdAt,
            Instant sentAt) {
    }
}
