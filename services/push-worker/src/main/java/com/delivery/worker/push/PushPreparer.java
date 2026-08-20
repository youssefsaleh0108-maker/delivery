package com.delivery.worker.push;

import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.Map;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import com.delivery.platform.notifications.ChannelPreparer;
import com.delivery.platform.notifications.NotificationCommand;

/**
 * Push-specific work: token sanity, payload shaping and the deep link.
 *
 * <p>Truncation rather than rejection is the right call for push, unlike SMS. A push notification
 * is a glance on a lock screen — a shortened title still does its job, while an oversized payload
 * is refused outright by FCM and the customer sees nothing. SMS is the opposite: it is billed per
 * segment and read in full, so there the long message is the bug.
 *
 * <p>The deep link is added here because it is a property of the notification, not of Firebase: if
 * a second push provider were ever added, the app would still expect the same {@code deepLink} key.
 */
@Component
public class PushPreparer implements ChannelPreparer {

    private static final Logger log = LoggerFactory.getLogger(PushPreparer.class);

    /** FCM caps the whole message at 4KB; these keep the visible parts well inside it. */
    private static final int MAX_TITLE = 64;
    private static final int MAX_BODY = 240;

    /**
     * FCM registration tokens have no fixed length, but they are never short. This only catches
     * placeholders and truncated values — the connector's UNREGISTERED classification is what
     * handles a token that is well-formed but dead.
     */
    private static final int MIN_TOKEN_LENGTH = 32;

    private final String deepLinkPrefix;

    public PushPreparer(@Value("${delivery.push.deep-link-prefix:delivery://orders/}") String prefix) {
        this.deepLinkPrefix = prefix;
    }

    @Override
    public Prepared prepare(NotificationCommand command) {
        String token = command.recipient() == null ? "" : command.recipient().trim();

        if (token.length() < MIN_TOKEN_LENGTH) {
            return Prepared.reject("device token is too short to be a real FCM token");
        }

        String body = command.body() == null ? "" : command.body().strip();
        if (body.isEmpty()) {
            return Prepared.reject("empty push body");
        }

        String title = truncate(
                command.subject() == null || command.subject().isBlank() ? "Delivery" : command.subject(),
                MAX_TITLE);
        String shortBody = truncate(body, MAX_BODY);

        Map<String, String> data = new HashMap<>(
                command.metadata() == null ? Map.of() : command.metadata());

        // Tapping the notification should land on the order it is about, not the app's home screen.
        String orderId = data.get("orderId");
        if (orderId != null && !data.containsKey("deepLink")) {
            data.put("deepLink", deepLinkPrefix + orderId);
        }

        if (payloadSize(title, shortBody, data) > MAX_PAYLOAD_BYTES) {
            // Only reachable if metadata is large; the visible fields are already capped.
            log.warn("Push {} exceeds the FCM payload limit even after truncation",
                    command.notificationId());
            return Prepared.reject("payload exceeds the FCM 4KB limit");
        }

        return Prepared.ready(new NotificationCommand(
                command.notificationId(),
                command.channel(),
                token,
                title,
                shortBody,
                data,
                command.correlationId(),
                command.createdAt()));
    }

    private static final int MAX_PAYLOAD_BYTES = 4096;

    private static String truncate(String value, int max) {
        return value.length() <= max ? value : value.substring(0, max - 1) + "…";
    }

    private static int payloadSize(String title, String body, Map<String, String> data) {
        int size = title.getBytes(StandardCharsets.UTF_8).length
                + body.getBytes(StandardCharsets.UTF_8).length;
        for (Map.Entry<String, String> entry : data.entrySet()) {
            size += entry.getKey().getBytes(StandardCharsets.UTF_8).length;
            size += entry.getValue() == null
                    ? 0 : entry.getValue().getBytes(StandardCharsets.UTF_8).length;
        }
        return size;
    }
}
