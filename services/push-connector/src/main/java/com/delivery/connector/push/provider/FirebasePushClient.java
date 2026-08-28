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
import com.google.firebase.messaging.AndroidConfig;
import com.google.firebase.messaging.AndroidNotification;
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
                    // The Android channel, named by the sender.
                    //
                    // Without it every push lands on fcm_fallback_notification_channel — one
                    // undifferentiated bucket, which is what a real handset showed. Android's
                    // per-channel controls are how somebody silences promotions while keeping "your
                    // rider is outside", so a single fallback channel makes the preference grid this
                    // platform enforces server-side unrepresentable on the device.
                    //
                    // The id comes from the category Notifications Manager already resolved, so the
                    // channel cannot disagree with the rules that decided to send at all. An unknown
                    // or absent category falls back to order updates rather than inventing a channel
                    // the app has not created — Android silently drops a notification whose channel
                    // does not exist, which would be worse than the wrong bucket.
                    .setAndroidConfig(AndroidConfig.builder()
                            .setNotification(AndroidNotification.builder()
                                    .setChannelId(channelFor(data.get("category")))
                                    .build())
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

    /**
     * The Android notification channel for a category.
     *
     * <p>These ids are a CONTRACT with the mobile app: it creates channels with exactly these ids at
     * startup, and Android drops a notification addressed to a channel that does not exist. Renaming
     * one here without shipping an app that creates it means silent, total loss of that category on
     * every device — so the ids are constants with this comment on them rather than a string built
     * from the enum name.
     */
    private static String channelFor(String category) {
        if (category == null) {
            return CHANNEL_ORDERS;
        }
        return switch (category) {
            case "CHAT" -> CHANNEL_CHAT;
            case "PROMOTIONS" -> CHANNEL_PROMOTIONS;
            case "ACCOUNT" -> CHANNEL_ACCOUNT;
            // ORDER_UPDATES and anything this connector has not been taught about. Order updates is
            // the safe default: it is the category a delivery app exists to deliver, and a message
            // arriving in the wrong bucket beats one that never arrives.
            default -> CHANNEL_ORDERS;
        };
    }

    static final String CHANNEL_ORDERS = "youdrop_order_updates";
    static final String CHANNEL_CHAT = "youdrop_chat";
    static final String CHANNEL_PROMOTIONS = "youdrop_promotions";
    static final String CHANNEL_ACCOUNT = "youdrop_account";

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
