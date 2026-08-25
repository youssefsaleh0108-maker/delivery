package com.delivery.connector.push.provider;

import java.io.ByteArrayInputStream;
import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.atomic.AtomicReference;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import com.delivery.platform.notifications.DeliveryOutcome;
import com.delivery.platform.notifications.NotificationCommand;
import com.delivery.platform.notifications.ProviderClient;
import com.google.auth.oauth2.GoogleCredentials;
import com.google.firebase.FirebaseApp;
import com.google.firebase.FirebaseOptions;
import com.google.firebase.messaging.FirebaseMessaging;
import com.google.firebase.messaging.FirebaseMessagingException;
import com.google.firebase.messaging.Message;
import com.google.firebase.messaging.MessagingErrorCode;
import com.google.firebase.messaging.Notification;

/**
 * Firebase Cloud Messaging.
 *
 * <p>Initialised lazily rather than at startup. The service-account JSON is a Vault-backed secret
 * resolved through the Config Server, and it is legitimately empty in an environment that has no
 * Firebase project yet — failing startup on that would mean the connector could not run at all in
 * dev, taking the whole push path down with it.
 *
 * <p>{@code UNREGISTERED} is classified permanent and is the case that matters most: it means the
 * app was uninstalled or the token was rotated. Retrying it can never succeed, and treating it as
 * transient is how a platform ends up burning its retry budget on devices that no longer exist.
 */
@Component
public class FirebasePushClient implements ProviderClient {

    public static final String NAME = "FIREBASE";

    private static final Logger log = LoggerFactory.getLogger(FirebasePushClient.class);
    private static final String APP_NAME = "delivery-push-connector";

    private final String serviceAccountJson;
    private final AtomicReference<FirebaseMessaging> messaging = new AtomicReference<>();

    public FirebasePushClient(
            @Value("${delivery.push.firebase.service-account-json:}") String serviceAccountJson) {
        this.serviceAccountJson = serviceAccountJson;
    }

    @Override
    public String name() {
        return NAME;
    }

    @Override
    public DeliveryOutcome send(NotificationCommand command) {
        FirebaseMessaging fcm;
        try {
            fcm = messaging();
        } catch (IllegalStateException e) {
            return DeliveryOutcome.permanentFailure(NAME, e.getMessage());
        } catch (Exception e) {
            log.error("Could not initialise Firebase", e);
            return DeliveryOutcome.transientFailure(NAME, "Firebase init failed: " + e.getMessage());
        }

        try {
            Map<String, String> data = new HashMap<>(
                    command.metadata() == null ? Map.of() : command.metadata());
            // Lets the app correlate a tapped notification back to the platform's record of it.
            data.put("notificationId", command.notificationId());

            Message message = Message.builder()
                    .setToken(command.recipient())
                    .setNotification(Notification.builder()
                            .setTitle(command.subject() == null ? "Delivery" : command.subject())
                            .setBody(command.body())
                            .build())
                    .putAllData(data)
                    .build();

            return DeliveryOutcome.sent(NAME, fcm.send(message));

        } catch (FirebaseMessagingException e) {
            return classify(e);

        } catch (Exception e) {
            log.warn("FCM send failed for {}: {}", command.notificationId(), e.getMessage());
            return DeliveryOutcome.transientFailure(NAME, e.getMessage());
        }
    }

    private FirebaseMessaging messaging() throws Exception {
        FirebaseMessaging existing = messaging.get();
        if (existing != null) {
            return existing;
        }
        if (serviceAccountJson.isBlank()) {
            throw new IllegalStateException(
                    "Firebase service-account credentials are not provisioned in Vault");
        }

        synchronized (this) {
            if (messaging.get() == null) {
                FirebaseApp app = FirebaseApp.getApps().stream()
                        .filter(candidate -> APP_NAME.equals(candidate.getName()))
                        .findFirst()
                        .orElseGet(() -> FirebaseApp.initializeApp(options(), APP_NAME));
                messaging.set(FirebaseMessaging.getInstance(app));
                log.info("Firebase initialised");
            }
        }
        return messaging.get();
    }

    private FirebaseOptions options() {
        try {
            return FirebaseOptions.builder()
                    .setCredentials(GoogleCredentials.fromStream(new ByteArrayInputStream(
                            serviceAccountJson.getBytes(StandardCharsets.UTF_8))))
                    .build();
        } catch (Exception e) {
            throw new IllegalStateException("Firebase credentials are unreadable", e);
        }
    }

    /**
     * A dead token is permanent; a quota or availability problem is not.
     *
     * <p>Getting this wrong in the permanent direction drops real notifications, and in the
     * transient direction retries every uninstalled app forever.
     *
     * <p>Three of the permanent codes condemn the TOKEN rather than the message, and are reported as
     * such so the platform stops addressing a device that is gone. {@code THIRD_PARTY_AUTH_ERROR} is
     * deliberately not among them: it means this sender's APNs credentials are wrong, which is our
     * configuration problem, and discarding every Apple token on the strength of it would turn a
     * fixable outage into permanent data loss.
     */
    private DeliveryOutcome classify(FirebaseMessagingException e) {
        MessagingErrorCode code = e.getMessagingErrorCode();
        boolean tokenIsDead = code == MessagingErrorCode.UNREGISTERED
                || code == MessagingErrorCode.INVALID_ARGUMENT
                || code == MessagingErrorCode.SENDER_ID_MISMATCH;
        boolean permanent = tokenIsDead || code == MessagingErrorCode.THIRD_PARTY_AUTH_ERROR;

        String reason = (code == null ? "UNKNOWN" : code.name()) + ": " + e.getMessage();
        if (tokenIsDead) {
            return DeliveryOutcome.invalidAddress(NAME, reason);
        }
        return permanent
                ? DeliveryOutcome.permanentFailure(NAME, reason)
                : DeliveryOutcome.transientFailure(NAME, reason);
    }
}
