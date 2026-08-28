package com.delivery.connector.email.provider;

import java.time.Instant;
import java.util.Map;
import java.util.Properties;

import jakarta.mail.Session;
import jakarta.mail.internet.MimeMessage;
import java.util.ArrayList;
import java.util.List;

import jakarta.mail.internet.MimeMultipart;

import org.eclipse.angus.mail.smtp.SMTPSendFailedException;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.mail.MailAuthenticationException;
import org.springframework.mail.MailParseException;
import org.springframework.mail.MailSendException;
import org.springframework.mail.javamail.JavaMailSender;

import com.delivery.connector.email.EmailHtmlLayout;
import com.delivery.platform.notifications.DeliveryOutcome;
import com.delivery.platform.notifications.NotificationCommand;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Sending mail, and the classification that decides whether a failed message is ever retried.
 *
 * <p>The classification is the substance. A 5xx is the relay refusing the message and no number of
 * retries changes it; a 4xx or an unreachable relay is "not now". Getting it backwards either burns
 * the retry budget on a mailbox that does not exist, or throws away recoverable mail — and the mail
 * in question is order confirmations and one-time verification codes.
 *
 * <p>Two of these tests are regression guards for a bug that only fired in production: the reply
 * code used to be matched out of the exception text, which read the relay's port number as a reply
 * code. Port 587 is the standard SMTP submission port, so an unreachable relay looked like a
 * permanent refusal. Dev never saw it, because the dev relay listens on 1025.
 */
class SmtpEmailClientTest {

    private JavaMailSender mailSender;
    private SmtpEmailClient client;

    @BeforeEach
    void setUp() {
        mailSender = mock(JavaMailSender.class);
        client = new SmtpEmailClient(mailSender,
                new EmailHtmlLayout("YouDrop", "#C41D4E"),
                "no-reply@delivery.test", "YouDrop");

        when(mailSender.createMimeMessage()).thenAnswer(call ->
                new MimeMessage(Session.getInstance(new Properties())));
    }

    private static NotificationCommand command() {
        return new NotificationCommand("notif-1", "EMAIL", "sam@example.test",
                "Your order is on its way", "It left the shop a moment ago",
                Map.of("eventType", "order.status_changed"), "corr-1", Instant.now());
    }

    private MimeMessage captureSent() {
        ArgumentCaptor<MimeMessage> captor = ArgumentCaptor.forClass(MimeMessage.class);
        verify(mailSender).send(captor.capture());
        return captor.getValue();
    }

    /** A relay that answered with a reply code, the way Angus reports it. */
    private void relayAnswers(int replyCode, String text) {
        MailSendException failure = new MailSendException(
                Map.of("sam@example.test", new SMTPSendFailedException(
                        "DATA", replyCode, text, null, new jakarta.mail.Address[0],
                        new jakarta.mail.Address[0], new jakarta.mail.Address[0])));
        doThrow(failure).when(mailSender).send(any(MimeMessage.class));
    }

    @Nested
    @DisplayName("a message that goes out")
    class Sending {

        @Test
        void reports_success_naming_the_provider() {
            DeliveryOutcome outcome = client.send(command());

            assertThat(outcome.success()).isTrue();
            assertThat(outcome.provider()).isEqualTo("SMTP");
        }

        @Test
        void is_addressed_from_the_configured_sender_to_the_recipient() throws Exception {
            client.send(command());

            MimeMessage sent = captureSent();
            assertThat(sent.getAllRecipients()[0].toString()).isEqualTo("sam@example.test");
            // With the display name, so it arrives from YouDrop rather than a bare address.
            assertThat(sent.getFrom()[0].toString())
                    .isEqualTo("YouDrop <no-reply@delivery.test>");
            assertThat(sent.getSubject()).isEqualTo("Your order is on its way");
        }

        /**
         * Multipart, with plain text first and branded HTML second.
         *
         * <p>The HTML alternative interpolates nothing unescaped — see {@link EmailHtmlLayout} and
         * its tests. That is what makes it safe: bodies carry customer-controlled values, product
         * names and delivery notes, and rendering one as markup would put an injection point in
         * every inbox. The plain part is what the notification log holds, so it stays first and the
         * two can never say different things.
         */
        @Test
        void is_sent_as_plain_text_with_a_branded_html_alternative() throws Exception {
            client.send(command());

            MimeMessage sent = captureSent();
            // What a real JavaMailSenderImpl does before handing the message to the transport.
            // The mock does not, so without it the content-type header is still the placeholder
            // one and reads as text/plain no matter what parts were attached.
            sent.saveChanges();
            assertThat(sent.getContentType()).startsWith("multipart/");

            // Walked rather than indexed. Spring nests mixed inside related inside alternative, and
            // the exact nesting is its business, not this test's — what matters is that both
            // renderings reach the inbox.
            List<String> types = new ArrayList<>();
            List<String> bodies = new ArrayList<>();
            collect(sent.getContent(), types, bodies);

            assertThat(types).anyMatch(t -> t.startsWith("text/plain"));
            assertThat(types).anyMatch(t -> t.startsWith("text/html"));
            assertThat(bodies).anySatisfy(b -> assertThat(b).contains("YouDrop"));
        }

        /** Flattens the part tree into content types and their text. */
        private void collect(Object content, List<String> types, List<String> bodies)
                throws Exception {
            if (content instanceof MimeMultipart multipart) {
                for (int i = 0; i < multipart.getCount(); i++) {
                    types.add(multipart.getBodyPart(i).getContentType());
                    collect(multipart.getBodyPart(i).getContent(), types, bodies);
                }
            } else if (content != null) {
                bodies.add(content.toString());
            }
        }

        /** Lets a message sitting in somebody's inbox be traced back to its notification_log row. */
        @Test
        void carries_the_notification_and_correlation_ids_as_headers() throws Exception {
            client.send(command());

            MimeMessage sent = captureSent();
            assertThat(sent.getHeader("X-Notification-Id")[0]).isEqualTo("notif-1");
            assertThat(sent.getHeader("X-Correlation-Id")[0]).isEqualTo("corr-1");
        }

        /** A message raised outside any request has no correlation id, and must still send. */
        @Test
        void tolerates_a_command_with_no_correlation_id() {
            NotificationCommand uncorrelated = new NotificationCommand("notif-1", "EMAIL",
                    "sam@example.test", "s", "b", Map.of(), null, Instant.now());

            assertThat(client.send(uncorrelated).success()).isTrue();
        }

        /** SMS-shaped templates have no subject; an email still has to go out. */
        @Test
        void tolerates_a_command_with_no_subject() throws Exception {
            NotificationCommand subjectless = new NotificationCommand("notif-1", "EMAIL",
                    "sam@example.test", null, "b", Map.of(), "corr-1", Instant.now());

            assertThat(client.send(subjectless).success()).isTrue();
            assertThat(captureSent().getSubject()).isEmpty();
        }
    }

    @Nested
    @DisplayName("failures that will never succeed")
    class Permanent {

        /** No such mailbox. Retrying delivers it to the same nowhere. */
        @Test
        void a_550_reply_is_permanent() {
            relayAnswers(550, "5.1.1 <sam@example.test>: Recipient address rejected");

            DeliveryOutcome outcome = client.send(command());

            assertThat(outcome.success()).isFalse();
            assertThat(outcome.retryable()).isFalse();
        }

        @Test
        void a_552_over_quota_reply_is_permanent() {
            relayAnswers(552, "5.2.2 Mailbox full");

            assertThat(client.send(command()).retryable()).isFalse();
        }

        /** A malformed address re-parses to the same failure every time. */
        @Test
        void a_malformed_message_is_permanent() {
            doThrow(new MailParseException("Invalid address"))
                    .when(mailSender).send(any(MimeMessage.class));

            DeliveryOutcome outcome = client.send(command());

            assertThat(outcome.retryable()).isFalse();
            assertThat(outcome.failureReason()).contains("malformed");
        }
    }

    @Nested
    @DisplayName("failures worth another attempt")
    class Transient {

        @Test
        void a_451_reply_is_retryable() {
            relayAnswers(451, "4.7.1 Try again later");

            DeliveryOutcome outcome = client.send(command());

            assertThat(outcome.success()).isFalse();
            assertThat(outcome.retryable()).isTrue();
        }

        @Test
        void a_421_service_unavailable_reply_is_retryable() {
            relayAnswers(421, "4.3.2 Service not available");

            assertThat(client.send(command()).retryable()).isTrue();
        }

        /**
         * The regression guard. JavaMail renders an unreachable relay as
         * {@code "Could not connect to SMTP host: ..., port: 587"}, and 587 — the standard
         * submission port — used to be read as a 5xx reply code. Every email during a relay outage
         * was permanently failed and dead-lettered instead of retried.
         */
        @Test
        void an_unreachable_relay_on_port_587_is_retryable_not_permanent() {
            doThrow(new MailSendException(
                    "Mail server connection failed; nested exception is "
                            + "jakarta.mail.MessagingException: Could not connect to SMTP host: "
                            + "smtp.example.test, port: 587; nested exception is "
                            + "java.net.ConnectException: Connection refused",
                    new java.net.ConnectException("Connection refused")))
                    .when(mailSender).send(any(MimeMessage.class));

            DeliveryOutcome outcome = client.send(command());

            assertThat(outcome.success()).isFalse();
            assertThat(outcome.retryable())
                    .as("an unreachable relay must be retried, not dead-lettered")
                    .isTrue();
        }

        /** The same holds for any port that happens to look like a reply code. */
        @Test
        void an_unreachable_relay_is_retryable_whatever_port_it_listens_on() {
            for (int port : new int[]{25, 465, 587, 1025, 2525}) {
                JavaMailSender sender = mock(JavaMailSender.class);
                when(sender.createMimeMessage()).thenAnswer(call ->
                        new MimeMessage(Session.getInstance(new Properties())));
                doThrow(new MailSendException("Could not connect to SMTP host: relay, port: " + port))
                        .when(sender).send(any(MimeMessage.class));

                assertThat(new SmtpEmailClient(sender,
                        new EmailHtmlLayout("YouDrop", "#C41D4E"),
                        "no-reply@delivery.test", "YouDrop")
                        .send(command()).retryable())
                        .as("port %d", port)
                        .isTrue();
            }
        }

        /**
         * A rejected credential stops all email, so it is loud — but it is fixable without changing
         * the message, which makes it worth keeping rather than dead-lettering.
         */
        @Test
        void rejected_relay_credentials_are_retryable() {
            doThrow(new MailAuthenticationException("535 authentication failed"))
                    .when(mailSender).send(any(MimeMessage.class));

            DeliveryOutcome outcome = client.send(command());

            assertThat(outcome.retryable()).isTrue();
            assertThat(outcome.failureReason()).contains("authentication");
        }

        /** An unexpected failure is treated as transient — the safe direction for a lost message. */
        @Test
        void an_unexpected_failure_is_retryable() {
            doThrow(new IllegalStateException("something odd"))
                    .when(mailSender).send(any(MimeMessage.class));

            assertThat(client.send(command()).retryable()).isTrue();
        }
    }

    /**
     * Which sender address the configuration produces.
     *
     * <p>A regression guard for an outage. {@code delivery.email.from} was set to the friendly form
     * — a display name around the address — and the display name was then applied a second time,
     * producing {@code YouDrop <YouDrop <a@b>>}. Every outbound message failed on a parse error, and
     * because nothing about the error names a setting, the visible symptom was verification codes
     * not arriving. Both forms have to work, and anything that works in neither has to stop the
     * service rather than be discovered one undelivered code at a time.
     */
    @Nested
    @DisplayName("the sender address")
    class SenderAddress {

        private SmtpEmailClient clientFrom(String from, String fromName) {
            return new SmtpEmailClient(mailSender, new EmailHtmlLayout("YouDrop", "#C41D4E"),
                    from, fromName);
        }

        private String fromHeaderOf(SmtpEmailClient subject) throws Exception {
            subject.send(command());
            return captureSent().getFrom()[0].toString();
        }

        @Test
        void a_bare_address_gains_the_configured_display_name() throws Exception {
            assertThat(fromHeaderOf(clientFrom("hello@youdrop.shop", "YouDrop")))
                    .isEqualTo("YouDrop <hello@youdrop.shop>");
        }

        /** The form that caused the outage: already named, so it is used as it stands. */
        @Test
        void an_address_that_already_carries_a_name_is_not_wrapped_again() throws Exception {
            assertThat(fromHeaderOf(clientFrom("YouDrop <hello@youdrop.shop>", "YouDrop")))
                    .isEqualTo("YouDrop <hello@youdrop.shop>");
        }

        /** The address decides; a differing from-name does not override a name already given. */
        @Test
        void the_name_on_the_address_wins_over_the_separate_setting() throws Exception {
            assertThat(fromHeaderOf(clientFrom("Support <hello@youdrop.shop>", "YouDrop")))
                    .isEqualTo("Support <hello@youdrop.shop>");
        }

        @Test
        void surrounding_whitespace_does_not_change_the_address() throws Exception {
            assertThat(fromHeaderOf(clientFrom("  hello@youdrop.shop  ", "YouDrop")))
                    .isEqualTo("YouDrop <hello@youdrop.shop>");
        }

        /** No display name configured is legitimate — the address goes out on its own. */
        @Test
        void a_blank_display_name_leaves_the_address_bare() throws Exception {
            assertThat(fromHeaderOf(clientFrom("hello@youdrop.shop", "  ")))
                    .isEqualTo("hello@youdrop.shop");
        }

        /**
         * Refused at construction, not at send. The message has to name the setting, because the
         * whole point is that the previous failure did not.
         */
        @Test
        void an_unusable_address_stops_the_service_rather_than_the_mail() {
            for (String unusable : List.of("YouDrop <YouDrop <a@b.com>>", "not an address", "")) {
                assertThatThrownBy(() -> clientFrom(unusable, "YouDrop"))
                        .as("from = \"%s\"", unusable)
                        .isInstanceOf(IllegalStateException.class)
                        .hasMessageContaining("delivery.email.from");
            }
        }
    }
}
