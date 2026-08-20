package com.delivery.notifications.api;

import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

import org.slf4j.MDC;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.delivery.notifications.service.NotificationDispatchService;

/**
 * Sending to an address rather than to a user.
 *
 * <p>For the two moments before somebody has an account: the one-time code that proves an address is
 * theirs, and the decision that follows their application. Every other notification on the platform
 * starts from a domain event and resolves a user; neither of these can, because the recipient
 * getting an account is the thing being decided.
 *
 * <p><strong>Not a public endpoint, and the reason is worth stating.</strong> An open "send text to
 * an address" API is an open mail relay with the platform's name on the envelope — free spam,
 * free phishing, and the sender reputation that carries every real notification. So this is
 * BACKOFFICE-only, which in practice means other services holding a platform token: no browser and
 * no applicant ever calls it, and the service that does calls it on their behalf after applying its
 * own rate limits.
 */
@RestController
@RequestMapping("/api/notifications")
public class DirectNotificationController {

    private final NotificationDispatchService dispatch;

    public DirectNotificationController(NotificationDispatchService dispatch) {
        this.dispatch = dispatch;
    }

    /**
     * @param channel   EMAIL or SMS. Not PUSH or IN_APP: both address a device or an account, which
     *                  is exactly what a recipient without an account does not have.
     * @param recipient the address itself
     * @param purpose   what this is for, recorded as the log row's event type
     */
    public record DirectRequest(
            @NotBlank @Pattern(regexp = "EMAIL|SMS",
                    message = "channel must be EMAIL or SMS") String channel,
            @NotBlank @Size(max = 255) String recipient,
            @Size(max = 200) String subject,
            @NotBlank @Size(max = 2000) String body,
            @NotBlank @Size(max = 64) String purpose) {
    }

    @PostMapping("/direct")
    @PreAuthorize("hasRole('BACKOFFICE')")
    public ResponseEntity<Map<String, String>> send(@Valid @RequestBody DirectRequest request) {
        UUID id = dispatch.sendDirect(
                request.channel(), request.recipient().trim(), request.subject(), request.body(),
                request.purpose(), MDC.get("correlationId"));
        return ResponseEntity.status(HttpStatus.ACCEPTED)
                .body(Map.of("notificationId", id.toString()));
    }
}
