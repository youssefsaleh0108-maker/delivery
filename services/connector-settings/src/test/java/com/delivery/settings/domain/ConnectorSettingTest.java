package com.delivery.settings.domain;

import java.lang.reflect.Field;
import java.util.LinkedHashMap;
import java.util.Map;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * The rules on a settings row, which is the one screen that can redirect real traffic.
 *
 * <p>Changing a value here sends live SMS to a different vendor, or points the banking connector at
 * a simulator. Three rules keep that from going wrong quietly: the provider must be one the
 * connector actually has an implementation for, no secret may be stored in a jsonb column that ends
 * up in backups and on a Backoffice screen, and a canary must be as validated as the primary — a
 * ramp that routes nothing looks exactly like a ramp that is finding no problems.
 */
class ConnectorSettingTest {

    /** The entity is built by Flyway and JPA, so a test needs to construct one by hand. */
    private static ConnectorSetting settingFor(ConnectorType type, String provider) {
        try {
            ConnectorSetting setting = ConnectorSetting.class.getDeclaredConstructor().newInstance();
            set(setting, "connectorType", type);
            set(setting, "provider", provider);
            set(setting, "config", new LinkedHashMap<String, Object>());
            set(setting, "updatedBy", "seed");
            return setting;
        } catch (ReflectiveOperationException e) {
            throw new IllegalStateException(e);
        }
    }

    private static void set(Object target, String name, Object value)
            throws ReflectiveOperationException {
        Field field = ConnectorSetting.class.getDeclaredField(name);
        field.setAccessible(true);
        field.set(target, value);
    }

    private static Map<String, Object> config(Object... pairs) {
        Map<String, Object> map = new LinkedHashMap<>();
        for (int i = 0; i < pairs.length; i += 2) {
            map.put(String.valueOf(pairs[i]), pairs[i + 1]);
        }
        return map;
    }

    @Nested
    @DisplayName("the provider list is closed")
    class Providers {

        @Test
        void every_declared_provider_is_accepted_for_its_connector() {
            for (ConnectorType type : ConnectorType.values()) {
                for (String provider : type.providers()) {
                    ConnectorSetting setting = settingFor(type, type.providers().get(0));
                    setting.update(provider, Map.of(), "admin");
                    assertThat(setting.getProvider()).isEqualTo(provider);
                }
            }
        }

        /** A dropdown is a UI convention, not a control. The service has to re-check it. */
        @Test
        void an_invented_provider_is_refused() {
            ConnectorSetting sms = settingFor(ConnectorType.SMS, "DEV_PASSTHROUGH");

            assertThatThrownBy(() -> sms.update("CHEAPEST_VENDOR", Map.of(), "admin"))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessageContaining("not a valid provider");
        }

        /** Another connector's provider is still not this connector's provider. */
        @Test
        void a_provider_belonging_to_a_different_connector_is_refused() {
            ConnectorSetting email = settingFor(ConnectorType.EMAIL, "SMTP");

            assertThatThrownBy(() -> email.update("TWILIO", Map.of(), "admin"))
                    .isInstanceOf(IllegalArgumentException.class);
        }

        @Test
        void provider_names_are_case_sensitive() {
            ConnectorSetting sms = settingFor(ConnectorType.SMS, "DEV_PASSTHROUGH");

            assertThatThrownBy(() -> sms.update("twilio", Map.of(), "admin"))
                    .isInstanceOf(IllegalArgumentException.class);
        }

        /** The refusal names the alternatives, so an admin can fix it without reading the source. */
        @Test
        void the_refusal_says_what_would_have_been_valid() {
            ConnectorSetting sms = settingFor(ConnectorType.SMS, "DEV_PASSTHROUGH");

            assertThatThrownBy(() -> sms.update("NOPE", Map.of(), "admin"))
                    .hasMessageContaining("TWILIO")
                    .hasMessageContaining("MONTYMOBILE");
        }
    }

    @Nested
    @DisplayName("secrets never land in this table")
    class Secrets {

        /**
         * A settings form is exactly where somebody eventually pastes an API key "just to test",
         * and a jsonb column puts it into backups, audit rows and a Backoffice screen at once.
         */
        @Test
        void anything_that_looks_like_a_credential_is_refused() {
            ConnectorSetting sms = settingFor(ConnectorType.SMS, "DEV_PASSTHROUGH");

            for (String key : new String[]{"apiKey", "api_key", "authToken", "password",
                    "clientSecret", "credentials", "passphrase", "privateKey", "signing_key"}) {
                assertThatThrownBy(() -> sms.update("TWILIO", config(key, "value"), "admin"))
                        .as("config key %s", key)
                        .isInstanceOf(IllegalArgumentException.class)
                        .hasMessageContaining("Vault");
            }
        }

        @Test
        void the_check_is_case_insensitive() {
            ConnectorSetting sms = settingFor(ConnectorType.SMS, "DEV_PASSTHROUGH");

            assertThatThrownBy(() -> sms.update("TWILIO", config("API_KEY", "x"), "admin"))
                    .isInstanceOf(IllegalArgumentException.class);
            assertThatThrownBy(() -> sms.update("TWILIO", config("MySecretThing", "x"), "admin"))
                    .isInstanceOf(IllegalArgumentException.class);
        }

        /** Over-rejecting would push someone towards a worse workaround, so ordinary keys pass. */
        @Test
        void ordinary_configuration_is_not_mistaken_for_a_secret() {
            ConnectorSetting sms = settingFor(ConnectorType.SMS, "DEV_PASSTHROUGH");

            sms.update("TWILIO", config("senderId", "DELIVERY", "routingKey", "sms.outbound",
                    "idempotencyKeyPrefix", "ord-", "region", "eu-west-1"), "admin");

            assertThat(sms.getConfig()).containsKeys("senderId", "routingKey");
        }

        /** The pointer to where the secret lives is fine — it is the value that must not be here. */
        @Test
        void a_vault_path_is_allowed_since_it_is_not_the_secret() {
            ConnectorSetting sms = settingFor(ConnectorType.SMS, "DEV_PASSTHROUGH");

            sms.update("TWILIO", config("vaultPath", "secret/delivery/sms/twilio"), "admin");

            assertThat(sms.getConfig()).containsEntry("vaultPath", "secret/delivery/sms/twilio");
        }

        /** A refused change must leave the row exactly as it was, not half-applied. */
        @Test
        void a_refused_change_does_not_alter_the_row() {
            ConnectorSetting sms = settingFor(ConnectorType.SMS, "DEV_PASSTHROUGH");

            assertThatThrownBy(() -> sms.update("TWILIO", config("apiKey", "leaked"), "admin"))
                    .isInstanceOf(IllegalArgumentException.class);

            assertThat(sms.getProvider()).isEqualTo("DEV_PASSTHROUGH");
            assertThat(sms.getConfig()).isEmpty();
        }
    }

    @Nested
    @DisplayName("the canary is validated like the primary")
    class Canary {

        private ConnectorSetting sms() {
            return settingFor(ConnectorType.SMS, "DEV_PASSTHROUGH");
        }

        @Test
        void a_valid_ramp_is_accepted() {
            ConnectorSetting sms = sms();

            sms.update("MONTYMOBILE", config("canaryProvider", "TWILIO", "canaryPercentage", "10"),
                    "admin");

            assertThat(sms.getConfig()).containsEntry("canaryProvider", "TWILIO");
        }

        /**
         * Without this the canary is an unvalidated free-text field deciding where real messages
         * go — the hole the closed provider list exists to close, reopened through the back door.
         */
        @Test
        void an_invented_canary_provider_is_refused() {
            assertThatThrownBy(() -> sms().update("MONTYMOBILE",
                    config("canaryProvider", "MYSTERY_VENDOR", "canaryPercentage", "10"), "admin"))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessageContaining("not a valid canary provider");
        }

        /** A canary with no percentage routes nothing while looking like a working ramp. */
        @Test
        void a_canary_without_a_percentage_is_refused() {
            assertThatThrownBy(() -> sms().update("MONTYMOBILE",
                    config("canaryProvider", "TWILIO"), "admin"))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessageContaining("nothing would be routed");
        }

        @Test
        void a_percentage_that_will_not_parse_is_refused() {
            assertThatThrownBy(() -> sms().update("MONTYMOBILE",
                    config("canaryProvider", "TWILIO", "canaryPercentage", "ten"), "admin"))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessageContaining("whole number");
        }

        @Test
        void a_percentage_outside_zero_to_one_hundred_is_refused() {
            assertThatThrownBy(() -> sms().update("MONTYMOBILE",
                    config("canaryProvider", "TWILIO", "canaryPercentage", "101"), "admin"))
                    .isInstanceOf(IllegalArgumentException.class);
            assertThatThrownBy(() -> sms().update("MONTYMOBILE",
                    config("canaryProvider", "TWILIO", "canaryPercentage", "-1"), "admin"))
                    .isInstanceOf(IllegalArgumentException.class);
        }

        /** The ends of the ramp — off, and fully cut over — are both legitimate settings. */
        @Test
        void zero_and_one_hundred_percent_are_both_valid() {
            sms().update("MONTYMOBILE",
                    config("canaryProvider", "TWILIO", "canaryPercentage", "0"), "admin");
            sms().update("MONTYMOBILE",
                    config("canaryProvider", "TWILIO", "canaryPercentage", "100"), "admin");
        }

        @Test
        void a_blank_canary_is_treated_as_no_canary_at_all() {
            ConnectorSetting sms = sms();

            sms.update("MONTYMOBILE", config("canaryProvider", "  "), "admin");

            assertThat(sms.getProvider()).isEqualTo("MONTYMOBILE");
        }

        @Test
        void whitespace_around_the_percentage_is_tolerated() {
            sms().update("MONTYMOBILE",
                    config("canaryProvider", "TWILIO", "canaryPercentage", " 25 "), "admin");
        }
    }

    @Nested
    @DisplayName("the audit snapshot")
    class Snapshot {

        /** The audit row is only worth having if it captures what actually changed. */
        @Test
        void carries_the_provider_and_config_at_that_moment() {
            ConnectorSetting sms = settingFor(ConnectorType.SMS, "DEV_PASSTHROUGH");
            sms.update("TWILIO", config("senderId", "DELIVERY"), "admin");

            Map<String, Object> snapshot = sms.snapshot();

            assertThat(snapshot).containsEntry("connectorType", "SMS")
                    .containsEntry("provider", "TWILIO");
            assertThat(snapshot.get("config")).isEqualTo(Map.of("senderId", "DELIVERY"));
        }

        /**
         * A snapshot taken before a change must not move when the change is applied — otherwise the
         * audit row's "before" and "after" are the same object and the trail records nothing.
         */
        @Test
        void a_snapshot_taken_before_a_change_is_not_altered_by_it() {
            ConnectorSetting sms = settingFor(ConnectorType.SMS, "DEV_PASSTHROUGH");
            sms.update("MONTYMOBILE", config("senderId", "OLD"), "admin");

            Map<String, Object> before = sms.snapshot();
            sms.update("TWILIO", config("senderId", "NEW"), "admin");

            assertThat(before).containsEntry("provider", "MONTYMOBILE");
            assertThat(before.get("config")).isEqualTo(Map.of("senderId", "OLD"));
        }

        @Test
        void the_config_getter_cannot_be_used_to_mutate_the_row() {
            ConnectorSetting sms = settingFor(ConnectorType.SMS, "DEV_PASSTHROUGH");
            sms.update("TWILIO", config("senderId", "DELIVERY"), "admin");

            assertThatThrownBy(() -> sms.getConfig().put("apiKey", "smuggled"))
                    .isInstanceOf(UnsupportedOperationException.class);
        }
    }

    @Nested
    @DisplayName("bookkeeping")
    class Bookkeeping {

        /** This page can redirect real SMS and money, so who changed it is not optional. */
        @Test
        void records_who_made_the_change_and_when() {
            ConnectorSetting sms = settingFor(ConnectorType.SMS, "DEV_PASSTHROUGH");

            sms.update("TWILIO", Map.of(), "alice@backoffice");

            assertThat(sms.getUpdatedBy()).isEqualTo("alice@backoffice");
            assertThat(sms.getUpdatedAt()).isNotNull();
        }

        /** Replace, not merge: a key removed from the form has to actually go away. */
        @Test
        void a_new_config_replaces_the_old_one_rather_than_merging_into_it() {
            ConnectorSetting sms = settingFor(ConnectorType.SMS, "DEV_PASSTHROUGH");
            sms.update("TWILIO", config("senderId", "OLD", "region", "eu"), "admin");

            sms.update("TWILIO", config("senderId", "NEW"), "admin");

            assertThat(sms.getConfig()).containsEntry("senderId", "NEW").doesNotContainKey("region");
        }
    }
}
