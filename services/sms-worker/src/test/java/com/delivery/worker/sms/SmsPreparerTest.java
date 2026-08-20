package com.delivery.worker.sms;

import java.time.Instant;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import com.delivery.platform.notifications.ChannelPreparer.Prepared;
import com.delivery.platform.notifications.NotificationCommand;

/**
 * Segmentation has money attached — vendors bill per segment — and recipient validation is what
 * stops the platform paying to send to numbers that can never receive. Both are worth pinning down.
 */
class SmsPreparerTest {

    private final SmsPreparer preparer = new SmsPreparer(3);

    private static NotificationCommand command(String recipient, String body) {
        return new NotificationCommand("11111111-1111-4111-8111-111111111111", "SMS",
                recipient, "ignored subject", body, Map.of("orderId", "abc"), "corr", Instant.now());
    }

    private static String repeat(String unit, int times) {
        return unit.repeat(times);
    }

    @Nested
    @DisplayName("recipient validation")
    class Recipients {

        @Test
        void accepts_an_e164_number() {
            assertThat(preparer.prepare(command("+15550100001", "hi")).rejected()).isFalse();
        }

        @Test
        void trims_surrounding_whitespace_rather_than_rejecting() {
            // A trailing space in a Keycloak attribute is a data-entry slip, not an unsendable
            // number. Rejecting it would cost a real notification.
            Prepared prepared = preparer.prepare(command("  +15550100001  ", "hi"));

            assertThat(prepared.rejected()).isFalse();
            assertThat(prepared.command().recipient()).isEqualTo("+15550100001");
        }

        @Test
        void rejects_a_number_without_a_country_code() {
            assertThat(preparer.prepare(command("5550100001", "hi")).rejected()).isTrue();
        }

        @Test
        void rejects_letters() {
            assertThat(preparer.prepare(command("not-a-phone-number", "hi")).rejection())
                    .contains("E.164");
        }

        @Test
        void rejects_a_leading_zero_country_code() {
            // +0 is not a valid country code, so this can never route.
            assertThat(preparer.prepare(command("+05550100001", "hi")).rejected()).isTrue();
        }

        @Test
        void rejects_null_and_empty() {
            assertThat(preparer.prepare(command(null, "hi")).rejected()).isTrue();
            assertThat(preparer.prepare(command("", "hi")).rejected()).isTrue();
        }

        @Test
        void rejects_an_empty_body() {
            assertThat(preparer.prepare(command("+15550100001", "   ")).rejection())
                    .contains("empty");
        }
    }

    @Nested
    @DisplayName("segmentation")
    class Segmentation {

        @Test
        void a_short_gsm_message_is_one_segment() {
            Prepared prepared = preparer.prepare(command("+15550100001", "Order is on the way"));

            assertThat(prepared.command().metadata()).containsEntry("segments", "1");
            assertThat(prepared.command().metadata()).containsEntry("encoding", "GSM-7");
        }

        @Test
        void exactly_160_gsm_characters_still_fits_one_segment() {
            Prepared prepared = preparer.prepare(command("+15550100001", repeat("a", 160)));

            assertThat(prepared.command().metadata()).containsEntry("segments", "1");
        }

        @Test
        void one_character_more_costs_two_segments() {
            // The cliff edge: past 160 every segment loses room to the concatenation header, so
            // capacity drops to 153 and a 161-character message is billed twice.
            Prepared prepared = preparer.prepare(command("+15550100001", repeat("a", 161)));

            assertThat(prepared.command().metadata()).containsEntry("segments", "2");
        }

        @Test
        void a_euro_sign_costs_two_units_not_one() {
            // GSM extension characters are sent as an escape plus the character. 159 plain
            // characters plus one euro is 161 units, so it crosses into a second segment even
            // though it is only 160 characters long.
            Prepared prepared = preparer.prepare(command("+15550100001", repeat("a", 159) + "€"));

            assertThat(prepared.command().metadata()).containsEntry("encoding", "GSM-7");
            assertThat(prepared.command().metadata()).containsEntry("segments", "2");
        }

        @Test
        void one_non_gsm_character_drops_the_whole_message_to_ucs2() {
            // A curly quote pasted into a template, or an emoji in a product name, quarters the
            // capacity of every segment in the message - the most expensive single character a
            // template author can introduce.
            Prepared prepared = preparer.prepare(command("+15550100001", repeat("a", 70) + "😀"));

            assertThat(prepared.command().metadata()).containsEntry("encoding", "UCS-2");
            assertThat(prepared.command().metadata().get("segments")).isNotEqualTo("1");
        }

        @Test
        void a_short_unicode_message_is_still_one_segment() {
            Prepared prepared = preparer.prepare(command("+15550100001", "Bestellung unterwegs 🚴"));

            assertThat(prepared.command().metadata()).containsEntry("encoding", "UCS-2");
            assertThat(prepared.command().metadata()).containsEntry("segments", "1");
        }

        @Test
        void rejects_rather_than_truncates_past_the_segment_limit() {
            // Truncation would produce a message cut off mid-sentence, which is worse than none.
            // The real fix is the template, so this fails loudly.
            Prepared prepared = preparer.prepare(command("+15550100001", repeat("a", 1000)));

            assertThat(prepared.rejected()).isTrue();
            assertThat(prepared.rejection()).contains("limit is 3");
        }
    }

    @Nested
    @DisplayName("the command handed to the connector")
    class Output {

        @Test
        void drops_the_subject_because_no_sms_provider_has_one() {
            assertThat(preparer.prepare(command("+15550100001", "hi")).command().subject()).isNull();
        }

        @Test
        void preserves_the_idempotency_key_and_correlation_id() {
            Prepared prepared = preparer.prepare(command("+15550100001", "hi"));

            assertThat(prepared.command().notificationId())
                    .isEqualTo("11111111-1111-4111-8111-111111111111");
            assertThat(prepared.command().correlationId()).isEqualTo("corr");
        }

        @Test
        void keeps_metadata_the_manager_sent() {
            assertThat(preparer.prepare(command("+15550100001", "hi")).command().metadata())
                    .containsEntry("orderId", "abc");
        }
    }
}
