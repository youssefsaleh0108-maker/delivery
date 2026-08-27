package com.delivery.notifications.link;

import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * What a notification link promises: it names a route, never a server, and it survives the trip to
 * the device unchanged.
 *
 * <p>Both halves have already cost this project something. A hostname baked into a link kept every
 * notification already sitting in a device tray pointing at an environment that had moved. And an id
 * that changes which route resolves is a link that claims to open an order and opens something else
 * — the ids come from event payloads, which carry data a customer can influence.
 */
class NotificationLinkTest {

    private static final UUID ORDER = UUID.fromString("6f1c7c9e-0000-4000-8000-000000000001");

    @Nested
    @DisplayName("naming a route rather than a server")
    class Canonical {

        /**
         * Push Connector has been synthesising this exact string as its fallback for order pushes.
         * Matching it byte for byte is what lets this service take the link over without an app
         * release and without two spellings of one link being in flight at the same time.
         */
        @Test
        void the_order_route_matches_the_one_the_push_connector_already_synthesises() {
            assertThat(NotificationLink.toOrder(ORDER).canonical())
                    .isEqualTo("delivery://orders/" + ORDER);
        }

        @Test
        void no_link_of_any_target_carries_a_hostname() {
            for (NotificationLinkTarget target : NotificationLinkTarget.values()) {
                String canonical = NotificationLink
                        .of(target, target.takesId() ? "id-1" : null)
                        .orElseThrow()
                        .canonical();

                assertThat(canonical).startsWith("delivery://")
                        .doesNotContain("http")
                        .doesNotContain(".com")
                        .doesNotContain(".io")
                        .doesNotContain("localhost");
            }
        }

        /** "Your password was changed" points at a screen, not at a record. */
        @Test
        void a_target_with_no_id_renders_without_a_trailing_segment() {
            assertThat(new NotificationLink(NotificationLinkTarget.ACCOUNT, null).canonical())
                    .isEqualTo("delivery://account");
        }
    }

    @Nested
    @DisplayName("surviving the trip to the device")
    class RoundTrip {

        @Test
        void every_target_survives_being_written_to_metadata_and_read_back() {
            for (NotificationLinkTarget target : NotificationLinkTarget.values()) {
                NotificationLink link = NotificationLink
                        .of(target, target.takesId() ? UUID.randomUUID().toString() : null)
                        .orElseThrow();

                Map<String, String> metadata = new HashMap<>();
                link.writeTo(metadata);

                assertThat(NotificationLink.fromMetadata(metadata)).contains(link);
            }
        }

        @Test
        void the_canonical_string_alone_is_enough_to_recover_the_typed_link() {
            NotificationLink link = NotificationLink.toOrder(ORDER);

            assertThat(NotificationLink.parse(link.canonical())).contains(link);
        }

        /**
         * A command written before the typed pair existed carries only {@code deepLink}. It must
         * still yield a typed link, or the first deploy of this change would silently drop the
         * destination of everything already sitting in a queue.
         */
        @Test
        void a_command_carrying_only_the_old_deep_link_key_still_yields_a_typed_link() {
            Map<String, String> legacy = Map.of("deepLink", "delivery://orders/" + ORDER);

            assertThat(NotificationLink.fromMetadata(legacy))
                    .contains(NotificationLink.toOrder(ORDER));
        }

        @Test
        void metadata_with_no_link_at_all_yields_nothing_rather_than_a_guess() {
            assertThat(NotificationLink.fromMetadata(Map.of("eventType", "order.placed"))).isEmpty();
            assertThat(NotificationLink.fromMetadata(null)).isEmpty();
        }

        @Test
        void a_string_under_another_scheme_is_not_a_link_of_ours() {
            assertThat(NotificationLink.parse("https://app.example.test/orders/" + ORDER)).isEmpty();
            assertThat(NotificationLink.parse("delivery://nowhere/" + ORDER)).isEmpty();
        }
    }

    @Nested
    @DisplayName("refusing an id that would change the route")
    class UntrustedIds {

        @Test
        void an_id_containing_a_path_separator_is_refused() {
            assertThatThrownBy(() ->
                    new NotificationLink(NotificationLinkTarget.ORDER, "../account"))
                    .isInstanceOf(IllegalArgumentException.class);
        }

        @Test
        void an_id_containing_whitespace_is_refused() {
            assertThat(NotificationLink.of(NotificationLinkTarget.ORDER, "abc def")).isEmpty();
        }

        /**
         * The rejection message must not repeat the value: it is untrusted text, and this message
         * reaches log lines and API error bodies.
         */
        @Test
        void the_rejection_does_not_echo_the_offending_value() {
            assertThatThrownBy(() ->
                    new NotificationLink(NotificationLinkTarget.ORDER, "<script>alert(1)</script>"))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessageNotContaining("script");
        }

        @Test
        void a_target_that_takes_an_id_will_not_be_built_without_one() {
            assertThat(NotificationLink.of(NotificationLinkTarget.ORDER, "  ")).isEmpty();
        }

        @Test
        void a_target_that_takes_no_id_will_not_be_given_one() {
            assertThat(NotificationLink.of(NotificationLinkTarget.ACCOUNT, "anything")).isEmpty();
        }
    }

    @Nested
    @DisplayName("keeping the set of destinations closed")
    class Targets {

        /**
         * An unrecognised target is not a routing error the app can report — the tap simply does
         * nothing. Skipping past it beats throwing, which would take a whole notification down over
         * a mistyped template row.
         */
        @Test
        void an_unrecognised_target_name_is_skipped_rather_than_thrown() {
            assertThat(NotificationLinkTarget.of("SOMETHING_ELSE")).isEmpty();
            assertThat(NotificationLinkTarget.of(null)).isEmpty();
        }

        @Test
        void a_target_name_is_read_however_it_was_cased() {
            assertThat(NotificationLinkTarget.of(" order "))
                    .contains(NotificationLinkTarget.ORDER);
        }

        /** Every target the app can be sent to needs a slug the app actually routes on. */
        @Test
        void every_target_has_a_distinct_slug() {
            assertThat(java.util.Arrays.stream(NotificationLinkTarget.values())
                    .map(NotificationLinkTarget::slug)
                    .distinct()
                    .count())
                    .isEqualTo(NotificationLinkTarget.values().length);
        }
    }
}
