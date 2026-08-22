package com.delivery.connector.email;

import java.time.Instant;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import com.delivery.platform.notifications.ChannelPreparer.Prepared;
import com.delivery.platform.notifications.NotificationCommand;

class MailPreparerTest {

    private final MailPreparer preparer = new MailPreparer("Delivery");

    private static NotificationCommand command(String recipient, String subject, String body) {
        return new NotificationCommand("22222222-2222-4222-8222-222222222222", "EMAIL",
                recipient, subject, body, Map.of(), "corr", Instant.now());
    }

    @Nested
    @DisplayName("header injection")
    class HeaderInjection {

        /**
         * The reason this class exists. Subjects are rendered from templates that interpolate
         * customer-controlled values, and a newline in one would end the Subject header early and
         * let everything after it be parsed as headers — which is how a Bcc ends up on every order
         * confirmation.
         */
        @Test
        void a_newline_in_the_subject_cannot_start_a_new_header() {
            Prepared prepared = preparer.prepare(command("a@b.com",
                    "Order #ABC\nBcc: attacker@evil.example.com", "body"));

            assertThat(prepared.command().subject()).doesNotContain("\n");
            assertThat(prepared.command().subject())
                    .isEqualTo("Order #ABC Bcc: attacker@evil.example.com");
        }

        @Test
        void carriage_returns_are_stripped_too() {
            Prepared prepared = preparer.prepare(command("a@b.com", "One\r\nTwo", "body"));

            assertThat(prepared.command().subject()).doesNotContain("\r").doesNotContain("\n");
        }

        @Test
        void an_over_long_subject_is_truncated_not_folded() {
            Prepared prepared = preparer.prepare(command("a@b.com", "x".repeat(500), "body"));

            assertThat(prepared.command().subject()).hasSize(200);
            assertThat(prepared.command().subject()).endsWith("…");
        }
    }

    @Nested
    @DisplayName("addresses")
    class Addresses {

        @Test
        void accepts_an_ordinary_address() {
            assertThat(preparer.prepare(command("customer@dev.local", "s", "b")).rejected()).isFalse();
        }

        @Test
        void accepts_subdomains_and_plus_addressing() {
            assertThat(preparer.prepare(command("a+tag@mail.example.co.uk", "s", "b")).rejected())
                    .isFalse();
        }

        @Test
        void rejects_an_address_with_no_domain() {
            assertThat(preparer.prepare(command("customer", "s", "b")).rejected()).isTrue();
        }

        @Test
        void rejects_an_address_with_no_dot_in_the_domain() {
            assertThat(preparer.prepare(command("a@localhost", "s", "b")).rejected()).isTrue();
        }

        @Test
        void rejects_whitespace_inside_the_address() {
            assertThat(preparer.prepare(command("a b@c.com", "s", "b")).rejected()).isTrue();
        }
    }

    @Nested
    @DisplayName("defaults")
    class Defaults {

        @Test
        void a_missing_subject_gets_the_default_rather_than_failing() {
            // A generic subject still reaches the customer; a rejected notification does not.
            assertThat(preparer.prepare(command("a@b.com", null, "body")).command().subject())
                    .isEqualTo("Delivery");
            assertThat(preparer.prepare(command("a@b.com", "   ", "body")).command().subject())
                    .isEqualTo("Delivery");
        }

        @Test
        void a_subject_of_only_newlines_falls_back_to_the_default() {
            assertThat(preparer.prepare(command("a@b.com", "\n\r\n", "body")).command().subject())
                    .isEqualTo("Delivery");
        }

        @Test
        void an_empty_body_is_rejected() {
            assertThat(preparer.prepare(command("a@b.com", "s", "  ")).rejection()).contains("empty");
        }
    }
}
