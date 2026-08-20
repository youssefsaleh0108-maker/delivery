package com.delivery.platform.notifications;

import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

/**
 * The canary split decides which vendor real, billable messages go to. Two properties matter more
 * than the percentages being pretty: a retry must never change vendor, and a malformed
 * configuration must never send everything somewhere unproven.
 */
class CanaryRouterTest {

    private static Map<String, String> canary(String provider, String percentage) {
        Map<String, String> config = new HashMap<>();
        if (provider != null) {
            config.put(CanaryRouter.CANARY_PROVIDER, provider);
        }
        if (percentage != null) {
            config.put(CanaryRouter.CANARY_PERCENTAGE, percentage);
        }
        return config;
    }

    @Nested
    @DisplayName("determinism")
    class Determinism {

        /**
         * The property the whole design rests on. A retried send carries the same idempotency key;
         * if it routed elsewhere, the other vendor has never seen that key, would accept it as new,
         * and the customer gets two texts — both billed.
         */
        @Test
        void the_same_key_always_routes_to_the_same_provider() {
            Map<String, String> config = canary("TWILIO", "50");

            for (int i = 0; i < 500; i++) {
                String key = UUID.randomUUID().toString();
                String first = CanaryRouter.route("MONTYMOBILE", config, key);

                for (int retry = 0; retry < 5; retry++) {
                    assertThat(CanaryRouter.route("MONTYMOBILE", config, key)).isEqualTo(first);
                }
            }
        }

        @Test
        void the_bucket_is_stable_across_calls() {
            String key = "11111111-1111-4111-8111-111111111111";
            int bucket = CanaryRouter.bucketOf(key);

            assertThat(CanaryRouter.bucketOf(key)).isEqualTo(bucket);
            // Nothing process-seeded: two connector instances must agree, or a retry landing on a
            // different pod would switch vendor.
            assertThat(bucket).isBetween(0, 99);
        }
    }

    @Nested
    @DisplayName("the split")
    class Split {

        @Test
        void roughly_honours_the_percentage() {
            Map<String, String> config = canary("TWILIO", "20");
            int canaryCount = 0;
            int total = 10_000;

            for (int i = 0; i < total; i++) {
                if (CanaryRouter.route("MONTYMOBILE", config, UUID.randomUUID().toString())
                        .equals("TWILIO")) {
                    canaryCount++;
                }
            }

            // Wide tolerance on purpose. This asserts the split is in the right ballpark, not that
            // CRC32 distributes perfectly - a tight bound here would be a flaky test about a
            // property nobody depends on.
            assertThat(canaryCount).isBetween(1500, 2500);
        }

        @Test
        void zero_percent_sends_nothing_to_the_canary() {
            Map<String, String> config = canary("TWILIO", "0");

            for (int i = 0; i < 200; i++) {
                assertThat(CanaryRouter.route("MONTYMOBILE", config, UUID.randomUUID().toString()))
                        .isEqualTo("MONTYMOBILE");
            }
        }

        @Test
        void a_hundred_percent_completes_the_cutover() {
            Map<String, String> config = canary("TWILIO", "100");

            for (int i = 0; i < 200; i++) {
                assertThat(CanaryRouter.route("MONTYMOBILE", config, UUID.randomUUID().toString()))
                        .isEqualTo("TWILIO");
            }
        }
    }

    @Nested
    @DisplayName("failing closed")
    class FailingClosed {

        /**
         * Every one of these must fall back to the primary. A misconfigured ramp that quietly sends
         * everything through an unproven vendor is the failure this class exists to prevent.
         */
        @Test
        void no_canary_configured() {
            assertThat(CanaryRouter.route("MONTYMOBILE", Map.of(), "key")).isEqualTo("MONTYMOBILE");
        }

        @Test
        void a_blank_canary_provider() {
            assertThat(CanaryRouter.route("MONTYMOBILE", canary("", "50"), "key"))
                    .isEqualTo("MONTYMOBILE");
        }

        @Test
        void a_percentage_that_will_not_parse() {
            assertThat(CanaryRouter.route("MONTYMOBILE", canary("TWILIO", "fifty"), "key"))
                    .isEqualTo("MONTYMOBILE");
        }

        @Test
        void a_missing_percentage() {
            assertThat(CanaryRouter.route("MONTYMOBILE", canary("TWILIO", null), "key"))
                    .isEqualTo("MONTYMOBILE");
        }

        @Test
        void a_negative_percentage() {
            assertThat(CanaryRouter.route("MONTYMOBILE", canary("TWILIO", "-10"), "key"))
                    .isEqualTo("MONTYMOBILE");
        }

        @Test
        void a_canary_naming_the_primary_is_a_no_op() {
            assertThat(CanaryRouter.route("TWILIO", canary("TWILIO", "50"), "key"))
                    .isEqualTo("TWILIO");
        }

        @Test
        void a_null_key_cannot_be_bucketed_so_stays_on_the_primary() {
            assertThat(CanaryRouter.route("MONTYMOBILE", canary("TWILIO", "50"), null))
                    .isEqualTo("MONTYMOBILE");
        }

        @Test
        void a_null_config() {
            assertThat(CanaryRouter.route("MONTYMOBILE", null, "key")).isEqualTo("MONTYMOBILE");
        }
    }
}
