package com.delivery.connector.push.provider;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

import com.delivery.platform.notifications.DeliveryOutcome;
import com.delivery.platform.notifications.NotificationCommand;
import com.delivery.platform.notifications.ProviderClient;

/**
 * The dev push provider: records what would have been sent, and reports success.
 *
 * <p>Unlike the SMS dev-passthrough, which really delivers over SMTP, there is nothing a push
 * notification can be redirected to without a Firebase project — no protocol to fall back on. So
 * this logs rather than delivers, which is a genuine gap: it exercises the queue, the worker's
 * payload shaping, the resilience wrapper and the receipt path, but not FCM itself.
 *
 * <p>That gap is why {@link FirebasePushClient} is built and deployed alongside it rather than
 * deferred. The first real Firebase send should be a settings change in staging, not the first time
 * the code runs.
 */
@Component
public class DevLogPushClient implements ProviderClient {

    public static final String NAME = "DEV_LOG";

    private static final Logger log = LoggerFactory.getLogger(DevLogPushClient.class);

    @Override
    public String name() {
        return NAME;
    }

    @Override
    public DeliveryOutcome send(NotificationCommand command) {
        log.info("PUSH (dev) to token {}: [{}] {} | data={} | notificationId={}",
                maskToken(command.recipient()), command.subject(), command.body(),
                command.metadata(), command.notificationId());

        return DeliveryOutcome.sent(NAME, "devlog-" + command.notificationId());
    }

    /**
     * Device tokens are credentials — anyone holding one can push to that device. Logging them in
     * full would put them in log aggregation and backups for the lifetime of the retention policy.
     */
    private static String maskToken(String token) {
        if (token == null || token.length() <= 8) {
            return "********";
        }
        return token.substring(0, 4) + "…" + token.substring(token.length() - 4);
    }
}
