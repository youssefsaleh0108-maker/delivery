package com.delivery.connector.push;

import java.time.Instant;
import java.util.HashMap;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import com.delivery.platform.notifications.ChannelPreparer.Prepared;
import com.delivery.platform.notifications.NotificationCommand;

class PushPreparerTest {

    private static final String VALID_TOKEN = "dev-fcm-token-customer-0000000000000000000000000000";

    private final PushPreparer preparer = new PushPreparer("delivery://orders/");

    private static NotificationCommand command(String token, String subject, String body,
                                               Map<String, String> metadata) {
        return new NotificationCommand("33333333-3333-4333-8333-333333333333", "PUSH",
                token, subject, body, metadata, "corr", Instant.now());
    }

    @Nested
    @DisplayName("tokens")
    class Tokens {

        @Test
        void accepts_a_realistic_token() {
            assertThat(preparer.prepare(command(VALID_TOKEN, "t", "b", Map.of())).rejected()).isFalse();
        }

        @Test
        void rejects_an_obvious_placeholder() {
            assertThat(preparer.prepare(command("token", "t", "b", Map.of())).rejection())
                    .contains("too short");
        }

        @Test
        void rejects_null() {
            assertThat(preparer.prepare(command(null, "t", "b", Map.of())).rejected()).isTrue();
        }
    }

    @Nested
    @DisplayName("payload shaping")
    class Shaping {

        /**
         * Truncation is right for push and wrong for SMS. A shortened title still does its job on a
         * lock screen, whereas an oversized payload is refused outright by FCM and the customer
         * sees nothing at all.
         */
        @Test
        void an_over_long_title_is_truncated_rather_than_rejected() {
            Prepared prepared = preparer.prepare(command(VALID_TOKEN, "T".repeat(200), "b", Map.of()));

            assertThat(prepared.rejected()).isFalse();
            assertThat(prepared.command().subject()).hasSize(64).endsWith("…");
        }

        @Test
        void an_over_long_body_is_truncated_too() {
            Prepared prepared = preparer.prepare(command(VALID_TOKEN, "t", "B".repeat(1000), Map.of()));

            assertThat(prepared.command().body()).hasSize(240).endsWith("…");
        }

        @Test
        void a_missing_title_gets_a_default() {
            assertThat(preparer.prepare(command(VALID_TOKEN, null, "b", Map.of())).command().subject())
                    .isEqualTo("Delivery");
        }

        @Test
        void an_empty_body_is_rejected() {
            assertThat(preparer.prepare(command(VALID_TOKEN, "t", "  ", Map.of())).rejection())
                    .contains("empty");
        }

        @Test
        void metadata_large_enough_to_burst_the_limit_is_rejected() {
            // Not reachable from the platform's own templates, since the visible fields are capped
            // first - but a caller could still get here, and FCM would refuse the whole message.
            Map<String, String> huge = new HashMap<>();
            huge.put("blob", "x".repeat(5000));

            assertThat(preparer.prepare(command(VALID_TOKEN, "t", "b", huge)).rejection())
                    .contains("4KB");
        }
    }

    @Nested
    @DisplayName("deep links")
    class DeepLinks {

        @Test
        void an_order_id_becomes_a_deep_link() {
            // Tapping the notification should land on the order it is about, not the home screen.
            Prepared prepared = preparer.prepare(
                    command(VALID_TOKEN, "t", "b", Map.of("orderId", "order-42")));

            assertThat(prepared.command().metadata())
                    .containsEntry("deepLink", "delivery://orders/order-42");
        }

        @Test
        void an_explicit_deep_link_is_left_alone() {
            Prepared prepared = preparer.prepare(command(VALID_TOKEN, "t", "b",
                    Map.of("orderId", "order-42", "deepLink", "delivery://promotions/spring")));

            assertThat(prepared.command().metadata())
                    .containsEntry("deepLink", "delivery://promotions/spring");
        }

        @Test
        void no_order_id_means_no_deep_link() {
            assertThat(preparer.prepare(command(VALID_TOKEN, "t", "b", Map.of())).command().metadata())
                    .doesNotContainKey("deepLink");
        }
    }
}
