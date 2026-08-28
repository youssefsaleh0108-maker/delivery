package com.delivery.connector.push.provider;

import java.lang.reflect.Method;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Which Android channel a category lands on.
 *
 * <p>This is pinned because its failure mode is invisible. Android DROPS a notification addressed to
 * a channel the app has not created, without an error on the device or a failure at the sender —
 * Firebase reports the send as successful either way. A typo here would show up as "push stopped
 * working for some people", months later, with nothing in any log to explain it.
 *
 * <p>The ids are duplicated as literals below on purpose. Asserting against the production
 * constants would pass just as happily if somebody renamed one, which is exactly the change that
 * breaks every installed app. These strings must match
 * clients/apps/mobile_app/android/app/src/main/kotlin/com/delivery/mobile_app/NotificationChannels.kt
 * and the default_notification_channel_id in that app's manifest.
 */
class FirebaseChannelRoutingTest {

    /** The private static mapper, reached by reflection so the test can stay outside the class. */
    private static String channelFor(String category) throws Exception {
        Method m = FirebasePushClient.class.getDeclaredMethod("channelFor", String.class);
        m.setAccessible(true);
        return (String) m.invoke(null, category);
    }

    @Nested
    @DisplayName("each category reaches its own channel")
    class Mapping {

        @Test
        @DisplayName("order updates")
        void orders() throws Exception {
            assertThat(channelFor("ORDER_UPDATES")).isEqualTo("youdrop_order_updates");
        }

        @Test
        @DisplayName("chat")
        void chat() throws Exception {
            assertThat(channelFor("CHAT")).isEqualTo("youdrop_chat");
        }

        @Test
        @DisplayName("promotions — the one a user must be able to silence alone")
        void promotions() throws Exception {
            assertThat(channelFor("PROMOTIONS")).isEqualTo("youdrop_promotions");
        }

        @Test
        @DisplayName("account and security")
        void account() throws Exception {
            assertThat(channelFor("ACCOUNT")).isEqualTo("youdrop_account");
        }
    }

    @Nested
    @DisplayName("anything unrecognised")
    class Fallback {

        @Test
        @DisplayName("a missing category still gets a channel that exists")
        void nullCategory() throws Exception {
            assertThat(channelFor(null)).isEqualTo("youdrop_order_updates");
        }

        @Test
        @DisplayName("a category this connector has not been taught about is not dropped")
        void unknownCategory() throws Exception {
            // The wrong bucket beats silence: a channel id the app never created is discarded by
            // Android outright, so an unknown category must never produce a new id.
            assertThat(channelFor("SOMETHING_ADDED_LATER")).isEqualTo("youdrop_order_updates");
        }

        @Test
        @DisplayName("every mapping answers one of the four channels the app creates")
        void neverInventsAChannel() throws Exception {
            for (String category : new String[] {
                    "ORDER_UPDATES", "CHAT", "PROMOTIONS", "ACCOUNT", "", "unknown", null}) {
                assertThat(channelFor(category)).isIn(
                        "youdrop_order_updates", "youdrop_chat",
                        "youdrop_promotions", "youdrop_account");
            }
        }
    }
}
