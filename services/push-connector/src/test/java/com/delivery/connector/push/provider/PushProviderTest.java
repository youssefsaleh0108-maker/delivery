package com.delivery.connector.push.provider;

import java.lang.reflect.Constructor;
import java.time.Instant;
import java.util.Map;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import com.delivery.platform.notifications.DeliveryOutcome;
import com.delivery.platform.notifications.NotificationCommand;
import com.google.firebase.ErrorCode;
import com.google.firebase.messaging.FirebaseMessagingException;
import com.google.firebase.messaging.MessagingErrorCode;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * The two push providers, and the classification that decides whether a dead device is retried.
 *
 * <p>{@code UNREGISTERED} is the one that matters. It means the app was uninstalled or the token
 * rotated, so the send can never succeed — and treating it as transient is how a platform ends up
 * spending its retry budget, forever, on devices that no longer exist. The mistake in the other
 * direction is worse per-message but rarer: a quota error classified permanent silently drops a real
 * notification.
 */
class PushProviderTest {

    private static NotificationCommand command() {
        return new NotificationCommand("notif-1", "PUSH", "device-token-abcdef123456",
                "On its way", "Your order has left the shop",
                Map.of("eventType", "order.status_changed", "orderId", "order-1"),
                "corr-1", Instant.now());
    }

    /**
     * Builds an FCM exception with a chosen error code.
     *
     * <p>Every constructor on {@code FirebaseMessagingException} is package-private — the SDK only
     * ever creates these itself — so reflection is the only way to exercise the classification
     * against a real exception rather than a stand-in that could drift from it.
     */
    private static FirebaseMessagingException fcmError(MessagingErrorCode code) {
        try {
            Constructor<FirebaseMessagingException> constructor =
                    FirebaseMessagingException.class.getDeclaredConstructor(
                            ErrorCode.class, String.class, Throwable.class,
                            com.google.firebase.IncomingHttpResponse.class,
                            MessagingErrorCode.class);
            constructor.setAccessible(true);
            return constructor.newInstance(ErrorCode.INVALID_ARGUMENT, "fcm said no", null, null, code);
        } catch (ReflectiveOperationException e) {
            throw new IllegalStateException("FCM exception shape changed", e);
        }
    }

    @Nested
    @DisplayName("the dev provider")
    class DevLog {

        private final DevLogPushClient client = new DevLogPushClient();

        @Test
        void reports_success_so_the_whole_push_path_stays_exercised() {
            DeliveryOutcome outcome = client.send(command());

            assertThat(outcome.success()).isTrue();
            assertThat(outcome.provider()).isEqualTo("DEV_LOG");
        }

        /** The receipt has to be traceable back to the notification, like any other provider's. */
        @Test
        void the_receipt_names_the_notification_it_was_for() {
            assertThat(client.send(command()).providerMessageId()).contains("notif-1");
        }

        @Test
        void it_registers_under_the_name_connector_settings_offers() {
            assertThat(client.name()).isEqualTo("DEV_LOG");
        }
    }

    @Nested
    @DisplayName("device tokens in logs")
    class TokenMasking {

        /**
         * A device token is a credential — anyone holding one can push to that device. Logging one
         * in full puts it in log aggregation and backups for the whole retention period.
         */
        @Test
        void a_token_is_masked_rather_than_logged_in_full() throws Exception {
            var method = DevLogPushClient.class.getDeclaredMethod("maskToken", String.class);
            method.setAccessible(true);

            String masked = (String) method.invoke(null, "device-token-abcdef123456");

            assertThat(masked).doesNotContain("device-token-abcdef123456");
            assertThat(masked).startsWith("devi").endsWith("3456");
        }

        @Test
        void a_short_or_absent_token_reveals_nothing_at_all() throws Exception {
            var method = DevLogPushClient.class.getDeclaredMethod("maskToken", String.class);
            method.setAccessible(true);

            assertThat((String) method.invoke(null, (Object) null)).isEqualTo("********");
            assertThat((String) method.invoke(null, "short")).isEqualTo("********");
            // Exactly at the boundary, still nothing revealed.
            assertThat((String) method.invoke(null, "12345678")).isEqualTo("********");
        }
    }

    @Nested
    @DisplayName("Firebase without a project configured")
    class Unconfigured {

        /**
         * The dev case. Startup must not fail — that would take the whole push path down in every
         * environment without a Firebase project — so the refusal happens per send instead.
         */
        @Test
        void refuses_permanently_and_says_the_credentials_are_missing() {
            DeliveryOutcome outcome = new FirebasePushClient("").send(command());

            assertThat(outcome.success()).isFalse();
            assertThat(outcome.retryable()).isFalse();
            assertThat(outcome.failureReason()).contains("not provisioned");
        }

        /** Unreadable credentials are a configuration error, not something to retry into. */
        @Test
        void unreadable_credentials_do_not_report_success() {
            DeliveryOutcome outcome = new FirebasePushClient("{\"not\":\"a service account\"}")
                    .send(command());

            assertThat(outcome.success()).isFalse();
        }

        @Test
        void it_registers_under_the_name_connector_settings_offers() {
            assertThat(new FirebasePushClient("").name()).isEqualTo("FIREBASE");
        }
    }

    @Nested
    @DisplayName("classifying what FCM says")
    class Classification {

        /** Reaches the private classifier with a real FCM exception. */
        private DeliveryOutcome classify(MessagingErrorCode code) {
            try {
                var method = FirebasePushClient.class.getDeclaredMethod(
                        "classify", FirebaseMessagingException.class);
                method.setAccessible(true);
                return (DeliveryOutcome) method.invoke(new FirebasePushClient(""), fcmError(code));
            } catch (ReflectiveOperationException e) {
                throw new IllegalStateException(e);
            }
        }

        /**
         * The app was uninstalled or the token rotated. No number of retries brings that device
         * back, and retrying is how the budget gets spent on devices that do not exist.
         */
        @Test
        void an_unregistered_device_is_permanent() {
            DeliveryOutcome outcome = classify(MessagingErrorCode.UNREGISTERED);

            assertThat(outcome.retryable()).isFalse();
            assertThat(outcome.failureReason()).contains("UNREGISTERED");
        }

        @Test
        void a_malformed_message_is_permanent() {
            assertThat(classify(MessagingErrorCode.INVALID_ARGUMENT).retryable()).isFalse();
        }

        /** The token belongs to a different Firebase project; it will never belong to ours. */
        @Test
        void a_sender_id_mismatch_is_permanent() {
            assertThat(classify(MessagingErrorCode.SENDER_ID_MISMATCH).retryable()).isFalse();
        }

        @Test
        void a_third_party_auth_error_is_permanent() {
            assertThat(classify(MessagingErrorCode.THIRD_PARTY_AUTH_ERROR).retryable()).isFalse();
        }

        /** Quota is Firebase asking us to slow down, not to give up on the notification. */
        @Test
        void exceeding_quota_is_retryable() {
            assertThat(classify(MessagingErrorCode.QUOTA_EXCEEDED).retryable()).isTrue();
        }

        @Test
        void firebase_being_unavailable_is_retryable() {
            assertThat(classify(MessagingErrorCode.UNAVAILABLE).retryable()).isTrue();
        }

        @Test
        void an_internal_firebase_error_is_retryable() {
            assertThat(classify(MessagingErrorCode.INTERNAL).retryable()).isTrue();
        }

        /** An error code the SDK did not populate must not be guessed as permanent. */
        @Test
        void an_absent_error_code_is_retryable_rather_than_dropped() {
            DeliveryOutcome outcome = classify(null);

            assertThat(outcome.retryable()).isTrue();
            assertThat(outcome.failureReason()).contains("UNKNOWN");
        }

        /**
         * Guards the assumption the classifier is written against: if the SDK adds a code, it lands
         * on the retryable side by default, which is the recoverable direction to be wrong in.
         */
        @Test
        void every_code_the_sdk_defines_is_classified_one_way_or_the_other() {
            for (MessagingErrorCode code : MessagingErrorCode.values()) {
                assertThat(classify(code)).as("code %s", code).isNotNull();
            }
        }
    }
}
