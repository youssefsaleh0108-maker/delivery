package com.delivery.platform.notifications;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;

import java.nio.charset.StandardCharsets;
import java.util.Map;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.slf4j.LoggerFactory;
import org.springframework.amqp.AmqpException;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.rabbit.core.RabbitTemplate;

import ch.qos.logback.classic.Logger;
import ch.qos.logback.classic.spi.ILoggingEvent;
import ch.qos.logback.core.read.ListAppender;

import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * A one-time code leaves in its message and nowhere else.
 *
 * <p>The code is a credential while it lives, so every copy the platform keeps is a way to take an
 * account: a dead-lettered command sits on a queue until somebody empties it, and a log line sits in
 * a file for as long as the logs are kept. These pin the places a worker keeps something, and the
 * rule they share.
 */
class OneTimeCodesTest {

    private static final String CODE = "482913";

    /** No timestamp: these serialise with a plain mapper, which has no java.time support. */
    private static NotificationCommand command(Map<String, String> metadata) {
        return new NotificationCommand("notification-1", "EMAIL", "sam@example.test",
                CODE + " is your YouDrop verification code",
                CODE + "\n\nUse this code to confirm your email address. It expires in 10 minutes.",
                metadata, "corr-1", null);
    }

    private static NotificationCommand codeBearing() {
        return command(Map.of("eventType", "onboarding.verification", OneTimeCodes.FLAG, "true"));
    }

    @Nested
    @DisplayName("the rule")
    class Rule {

        @Test
        void every_long_run_of_digits_is_masked_and_the_prose_around_it_kept() {
            assertThat(OneTimeCodes.mask(CODE + " is your YouDrop verification code. It expires in 10 "
                    + "minutes."))
                    .isEqualTo(OneTimeCodes.MASK + " is your YouDrop verification code. It expires in "
                            + "10 minutes.");
        }

        @Test
        void a_code_with_leading_zeros_is_still_a_code() {
            assertThat(OneTimeCodes.mask("004213")).isEqualTo(OneTimeCodes.MASK);
            assertThat(OneTimeCodes.find("Your code: 004213")).contains("004213");
        }

        @Test
        void nothing_to_mask_is_nothing_changed_and_null_stays_null() {
            assertThat(OneTimeCodes.mask("Approved")).isEqualTo("Approved");
            assertThat(OneTimeCodes.mask(null)).isNull();
            assertThat(OneTimeCodes.find(null)).isEmpty();
            assertThat(OneTimeCodes.find("It expires in 10 minutes")).isEmpty();
        }

        /** The mark is the sender's word; a command without it is left exactly as it came. */
        @Test
        void only_a_command_marked_as_carrying_a_code_is_masked() {
            NotificationCommand unmarked = command(Map.of("eventType", "order.placed"));

            assertThat(OneTimeCodes.carriedBy(unmarked)).isFalse();
            assertThat(OneTimeCodes.masked(unmarked)).isSameAs(unmarked);
            assertThat(OneTimeCodes.carriedBy(command(null))).isFalse();

            NotificationCommand masked = OneTimeCodes.masked(codeBearing());
            assertThat(masked.subject()).doesNotContain(CODE);
            assertThat(masked.body()).doesNotContain(CODE).contains("It expires in 10 minutes");
            assertThat(masked.recipient()).isEqualTo("sam@example.test");
            assertThat(masked.notificationId()).isEqualTo("notification-1");
        }
    }

    @Nested
    @DisplayName("a command that will never be delivered")
    class DeadLetters {

        private RabbitTemplate rabbit;
        private DeadLetterPublisher publisher;

        @BeforeEach
        void setUp() {
            rabbit = mock(RabbitTemplate.class);
            publisher = new DeadLetterPublisher(rabbit, new ObjectMapper(), "notification.dead-letter");
        }

        private String parked() {
            ArgumentCaptor<Message> captor = ArgumentCaptor.forClass(Message.class);
            verify(rabbit).send(eq(""), eq("notification.dead-letter"), captor.capture());
            return new String(captor.getValue().getBody(), StandardCharsets.UTF_8);
        }

        /** The queue keeps what it is given; a code on it is a working credential for its readers. */
        @Test
        void a_code_is_parked_masked_with_everything_else_an_operator_needs() {
            publisher.park(codeBearing(), "550 mailbox unavailable");

            assertThat(parked())
                    .doesNotContain(CODE)
                    .contains("sam@example.test", "notification-1", "550 mailbox unavailable",
                            "is your YouDrop verification code");
        }

        /** Anything else is parked unchanged, so it can still be replayed as it was. */
        @Test
        void an_ordinary_message_is_parked_as_it_was() {
            publisher.park(command(Map.of("eventType", "order.placed")), "550 mailbox unavailable");

            assertThat(parked()).contains(CODE + " is your YouDrop verification code");
        }

        /** The last resort writes the command into the log, and so must not write the code. */
        @Test
        void when_the_queue_is_unreachable_the_log_line_holds_no_code() {
            doThrow(new AmqpException("broker down"))
                    .when(rabbit).send(any(String.class), any(String.class), any(Message.class));

            ListAppender<ILoggingEvent> logged = listen(DeadLetterPublisher.class);
            try {
                publisher.park(codeBearing(), "550 mailbox unavailable");
            } finally {
                stopListening(DeadLetterPublisher.class, logged);
            }

            assertThat(logged.list).extracting(ILoggingEvent::getFormattedMessage)
                    .anySatisfy(line -> assertThat(line).startsWith("Could not dead-letter"))
                    .allSatisfy(line -> assertThat(line).doesNotContain(CODE));
        }
    }

    @Nested
    @DisplayName("a command the worker cannot read")
    class Unreadable {

        /** It cannot say whether it carries a code, so no code in it reaches the log. */
        @Test
        void the_logged_payload_holds_no_code() {
            WorkerDispatchService worker = new WorkerDispatchService("email", null, null, null, null,
                    null, new ObjectMapper(), "delivery.events");

            ListAppender<ILoggingEvent> logged = listen(WorkerDispatchService.class);
            try {
                worker.handle("{\"notificationId\": \"n-1\", \"body\": \"" + CODE
                        + " is your YouDrop verification code\", ");
            } finally {
                stopListening(WorkerDispatchService.class, logged);
            }

            assertThat(logged.list)
                    .anySatisfy(event -> assertThat(event.getFormattedMessage())
                            .startsWith("Unreadable email command"))
                    .allSatisfy(event -> {
                        assertThat(event.getFormattedMessage()).doesNotContain(CODE);
                        // The parser's own message rides along with the line; it must not quote the
                        // payload back either.
                        if (event.getThrowableProxy() != null) {
                            assertThat(event.getThrowableProxy().getMessage()).doesNotContain(CODE);
                        }
                    });
        }
    }

    private static ListAppender<ILoggingEvent> listen(Class<?> type) {
        Logger logger = (Logger) LoggerFactory.getLogger(type);
        ListAppender<ILoggingEvent> appender = new ListAppender<>();
        appender.start();
        logger.addAppender(appender);
        return appender;
    }

    private static void stopListening(Class<?> type, ListAppender<ILoggingEvent> appender) {
        ((Logger) LoggerFactory.getLogger(type)).detachAppender(appender);
    }
}
