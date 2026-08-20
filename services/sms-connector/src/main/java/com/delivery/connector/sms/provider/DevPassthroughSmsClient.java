package com.delivery.connector.sms.provider;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.mail.MailSendException;
import org.springframework.mail.SimpleMailMessage;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.stereotype.Component;

import com.delivery.platform.notifications.DeliveryOutcome;
import com.delivery.platform.notifications.NotificationCommand;
import com.delivery.platform.notifications.ProviderClient;

/**
 * The dev provider: delivers "what the SMS would have said" to a test inbox over SMTP.
 *
 * <p>Section 7's dev mode. It exists so the whole notification chain — outbox, manager, worker,
 * connector, resilience, receipt — can be exercised end to end without a paid SMS account or a real
 * handset, and so the platform can launch before the MontyMobile/Twilio commercial decision is made
 * (Section 12, open decision #6).
 *
 * <p>Deliberately a real send, not a log line. A no-op would leave the SMTP hop, the failure
 * classification and the receipt path untested until the day a real vendor is switched on, which is
 * the worst possible day to find out they were wrong.
 */
@Component
public class DevPassthroughSmsClient implements ProviderClient {

    public static final String NAME = "DEV_PASSTHROUGH";

    private static final Logger log = LoggerFactory.getLogger(DevPassthroughSmsClient.class);

    private final JavaMailSender mailSender;
    private final String testInbox;
    private final String from;

    public DevPassthroughSmsClient(
            JavaMailSender mailSender,
            @Value("${delivery.sms.dev-passthrough.test-inbox:sms-test-inbox@dev.local}") String testInbox,
            @Value("${delivery.sms.dev-passthrough.from:sms-connector@dev.local}") String from) {
        this.mailSender = mailSender;
        this.testInbox = testInbox;
        this.from = from;
    }

    @Override
    public String name() {
        return NAME;
    }

    @Override
    public DeliveryOutcome send(NotificationCommand command) {
        try {
            SimpleMailMessage message = new SimpleMailMessage();
            message.setFrom(from);
            message.setTo(testInbox);
            // The intended recipient goes in the subject, not just the body: a QA engineer reading
            // the inbox needs to tell at a glance which number a message was meant for.
            message.setSubject("[SMS -> " + command.recipient() + "] " + command.notificationId());
            message.setText(command.body()
                    + "\n\n--\nintended recipient: " + command.recipient()
                    + "\nnotification id: " + command.notificationId()
                    + "\ncorrelation id: " + command.correlationId());

            mailSender.send(message);

            log.info("SMS for {} redirected to the dev test inbox ({})",
                    command.recipient(), testInbox);
            return DeliveryOutcome.sent(NAME, "devinbox-" + command.notificationId());

        } catch (MailSendException e) {
            // The relay is down or refusing. Same shape as a real vendor being unavailable, and
            // treated the same way, which is the point of not stubbing this out.
            return DeliveryOutcome.transientFailure(NAME, "test inbox unreachable: " + e.getMessage());

        } catch (Exception e) {
            return DeliveryOutcome.permanentFailure(NAME, e.getMessage());
        }
    }
}
