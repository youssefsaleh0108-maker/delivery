package com.delivery.connector.sms.provider;

import java.util.Map;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.slf4j.LoggerFactory;
import org.springframework.mail.javamail.JavaMailSender;

import ch.qos.logback.classic.Logger;
import ch.qos.logback.classic.spi.ILoggingEvent;
import ch.qos.logback.core.read.ListAppender;

import com.delivery.platform.notifications.NotificationCommand;
import com.delivery.platform.notifications.OneTimeCodes;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;

/**
 * With no dev test inbox configured, the passthrough logs what it would have sent — and a one-time
 * code must not be part of that. The log outlives the code's ten minutes and is read by more people
 * than the phone it was meant for.
 */
class DevPassthroughSmsClientTest {

    private static final String CODE = "482913";

    private final DevPassthroughSmsClient client =
            new DevPassthroughSmsClient(mock(JavaMailSender.class), "", "sms-connector@dev.local");

    private final Logger logger = (Logger) LoggerFactory.getLogger(DevPassthroughSmsClient.class);
    private final ListAppender<ILoggingEvent> logged = new ListAppender<>();

    @BeforeEach
    void listen() {
        logged.start();
        logger.addAppender(logged);
    }

    @AfterEach
    void stopListening() {
        logger.detachAppender(logged);
    }

    private static NotificationCommand sms(Map<String, String> metadata) {
        return new NotificationCommand("n-1", "SMS", "+9613123456", null,
                CODE + " is your YouDrop verification code. It expires in 10 minutes.",
                metadata, "corr-1", null);
    }

    @Test
    void a_one_time_code_is_masked_in_the_line_it_logs_instead_of_sending() {
        assertThat(client.send(sms(Map.of("eventType", "onboarding.verification",
                OneTimeCodes.FLAG, "true"))).success()).isTrue();

        assertThat(logged.list).singleElement().satisfies(event -> assertThat(
                event.getFormattedMessage())
                .doesNotContain(CODE)
                .contains("is your YouDrop verification code"));
    }

    @Test
    void any_other_message_is_logged_as_it_would_have_been_sent() {
        client.send(sms(Map.of("eventType", "order.status_changed")));

        assertThat(logged.list).singleElement().satisfies(event ->
                assertThat(event.getFormattedMessage()).contains(CODE));
    }
}
