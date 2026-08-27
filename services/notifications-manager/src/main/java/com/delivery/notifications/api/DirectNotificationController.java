package com.delivery.notifications.api;

import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

import org.slf4j.MDC;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.delivery.platform.notifications.NotificationCommand;
import com.delivery.notifications.link.NotificationLink;
import com.delivery.notifications.link.NotificationLinkTarget;
import com.delivery.notifications.service.NotificationDispatchService;
import com.delivery.notifications.service.RecipientDirectory;

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

    private static final Logger log = LoggerFactory.getLogger(DirectNotificationController.class);

    private final NotificationDispatchService dispatch;
    private final RecipientDirectory directory;

    public DirectNotificationController(NotificationDispatchService dispatch,
                                        RecipientDirectory directory) {
        this.dispatch = dispatch;
        this.directory = directory;
    }

    /**
     * @param channel   EMAIL or SMS. Not PUSH: a device is addressed by account, not by a string
     *                  the caller holds — see {@link #push}
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

    /**
     * A push to somebody who DOES have an account.
     *
     * <p>Its own shape because a device is not addressed the way a mailbox is. The caller names the
     * account; the device token is looked up here, from the same directory the order events use.
     * A caller that passed a token instead would have to have stored one, and storing device tokens
     * in two places is how they go stale in one of them.
     *
     * <p>The optional link is what makes a direct push worth tapping. Nothing can derive it on this
     * path — there is no order and no template, so the caller is the only thing that knows what its
     * message is about. A chat push naming its conversation and an approval naming its application
     * are the two that matter; without them both open the app's home screen and leave the user to
     * go and find the thing they were just told about.
     *
     * @param recipientId the Keycloak sub to reach
     * @param linkTarget  ORDER, CONVERSATION, APPLICATION, EARNINGS or ACCOUNT; omit for no link
     * @param linkId      which one — omitted for ACCOUNT, which takes none
     */
    public record DirectPushRequest(
            @NotBlank @Size(max = 64) String recipientId,
            @Size(max = 200) String subject,
            @NotBlank @Size(max = 2000) String body,
            @NotBlank @Size(max = 64) String purpose,
            @Size(max = 32) String linkTarget,
            @Size(max = 128) String linkId) {
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

    /**
     * Pushes to an account, resolving its device from the directory.
     *
     * <p>204 when the account has no device on file. That is not an error: somebody who has never
     * opened the app on a phone has no token, and the caller — an approval, say — has already
     * happened and must not fail over a notification.
     */
    @PostMapping("/direct/push")
    @PreAuthorize("hasRole('BACKOFFICE')")
    public ResponseEntity<Map<String, String>> push(@Valid @RequestBody DirectPushRequest request) {
        String device = directory.contactsFor(request.recipientId())
                .get(NotificationCommand.CHANNEL_PUSH);
        if (device == null || device.isBlank()) {
            log.info("No device on file for {}; nothing pushed", request.recipientId());
            return ResponseEntity.noContent().build();
        }

        // A target the platform does not recognise, or an id that is not routable, yields no link
        // rather than a 400. The push itself is the thing the caller asked for and it has already
        // succeeded upstream — an approval must not fail because somebody sent a target with a typo
        // in it. The message still arrives; it just opens the app rather than a screen.
        NotificationLink link = NotificationLinkTarget.of(request.linkTarget())
                .flatMap(target -> NotificationLink.of(target, request.linkId()))
                .orElse(null);
        if (link == null && request.linkTarget() != null && !request.linkTarget().isBlank()) {
            log.warn("Ignoring an unroutable link on a direct push for {}", request.purpose());
        }

        UUID id = dispatch.sendDirect(
                NotificationCommand.CHANNEL_PUSH, device, request.recipientId(), request.subject(),
                request.body(), request.purpose(), MDC.get("correlationId"), link);
        return ResponseEntity.status(HttpStatus.ACCEPTED)
                .body(Map.of("notificationId", id.toString()));
    }
}
