package com.delivery.connector.email.provider;

import java.io.UnsupportedEncodingException;
import java.nio.charset.StandardCharsets;

import jakarta.mail.internet.AddressException;
import jakarta.mail.internet.InternetAddress;
import jakarta.mail.internet.MimeMessage;

import org.eclipse.angus.mail.smtp.SMTPAddressFailedException;
import org.eclipse.angus.mail.smtp.SMTPSendFailedException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.mail.MailAuthenticationException;
import org.springframework.mail.MailParseException;
import org.springframework.mail.MailSendException;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.mail.javamail.MimeMessageHelper;
import org.springframework.stereotype.Component;

import com.delivery.connector.email.EmailHtmlLayout;
import com.delivery.platform.notifications.DeliveryOutcome;
import com.delivery.platform.notifications.NotificationCommand;
import com.delivery.platform.notifications.ProviderClient;

/**
 * Sends through the configured SMTP relay.
 *
 * <p>The failure classification is the substance of this class. SMTP distinguishes 4xx (try again)
 * from 5xx (never), and collapsing the two would either strand recoverable messages or make the
 * platform retry a mailbox that does not exist until the budget runs out.
 */
@Component
public class SmtpEmailClient implements ProviderClient {

    public static final String NAME = "SMTP";

    private static final Logger log = LoggerFactory.getLogger(SmtpEmailClient.class);

    private final JavaMailSender mailSender;
    private final EmailHtmlLayout layout;
    private final InternetAddress from;

    public SmtpEmailClient(JavaMailSender mailSender,
                           EmailHtmlLayout layout,
                           @Value("${delivery.email.from:no-reply@delivery.local}") String from,
                           @Value("${delivery.email.from-name:YouDrop}") String fromName) {
        this.mailSender = mailSender;
        this.layout = layout;
        this.from = resolveFrom(from, fromName);
    }

    /**
     * The From header, settled once at startup rather than rebuilt per message.
     *
     * <p>{@code delivery.email.from} may be given either way round — a bare address, or a full
     * mailbox that already carries a display name. Wrapping the second form in a display name again
     * yields {@code YouDrop <YouDrop <a@b.com>>}, which is not an address, and nothing notices until
     * send time: <em>every</em> notification then fails on a JavaMail parse error that says nothing
     * about which setting caused it. That is not hypothetical — configuring the friendly form took
     * all outbound email down, and the only signal was verification codes silently not arriving.
     *
     * <p>So a bad value stops the service here, with a message naming the setting and both accepted
     * forms. A connector that cannot address a message has nothing useful to do, and a container
     * that will not start is far easier to diagnose than one that runs while discarding mail.
     */
    private static InternetAddress resolveFrom(String from, String fromName) {
        String configured = from == null ? "" : from.trim();
        try {
            // Lenient parse, then validate: strict mode rejects a bare address, which is the form
            // most deployments use and the one every default here is written in.
            InternetAddress address = new InternetAddress(configured, false);
            address.validate();
            if (address.getPersonal() == null && fromName != null && !fromName.isBlank()) {
                address.setPersonal(fromName, StandardCharsets.UTF_8.name());
            }
            return address;
        } catch (AddressException | UnsupportedEncodingException e) {
            throw new IllegalStateException(
                    "delivery.email.from is not a usable sender address: \"" + configured + "\". "
                            + "Give either a bare address (you@example.com) or a full mailbox "
                            + "(YouDrop <you@example.com>) — not a display name around one that "
                            + "already has one.", e);
        }
    }

    @Override
    public String name() {
        return NAME;
    }

    @Override
    public DeliveryOutcome send(NotificationCommand command) {
        try {
            MimeMessage message = mailSender.createMimeMessage();
            // Multipart: plain text first, branded HTML second. A client that will not render HTML
            // still shows the message rather than nothing, and the plain part is what the log row
            // holds, so the two can never say different things.
            MimeMessageHelper helper =
                    new MimeMessageHelper(message, true, StandardCharsets.UTF_8.name());

            // Carries the display name, so the message arrives from YouDrop rather than from a
            // bare no-reply address. Already parsed and validated at startup — see resolveFrom.
            helper.setFrom(from);
            helper.setTo(command.recipient());
            helper.setSubject(command.subject() == null ? "" : command.subject());
            // The HTML alternative interpolates NOTHING unescaped — see EmailHtmlLayout. That is
            // what makes this safe: bodies carry customer-controlled values such as product names
            // and delivery notes, and rendering one of those as markup would put an injection
            // point in every customer's inbox.
            helper.setText(command.body(), layout.render(command.subject(), command.body()));

            // Survives the relay and appears in the delivered headers, so a message in someone's
            // inbox can be traced back to its notification_log row (Section 10).
            message.setHeader("X-Notification-Id", command.notificationId());
            if (command.correlationId() != null) {
                message.setHeader("X-Correlation-Id", command.correlationId());
            }

            mailSender.send(message);
            return DeliveryOutcome.sent(NAME, "smtp-" + command.notificationId());

        } catch (MailParseException e) {
            // Malformed address or headers. Retrying re-parses the same bytes to the same result.
            return DeliveryOutcome.permanentFailure(NAME, "malformed message: " + e.getMessage());

        } catch (MailAuthenticationException e) {
            // The relay rejected our credentials. Transient in the sense that a fix is possible
            // without changing the message - and worth a loud log, since it stops all email.
            log.error("SMTP relay rejected our credentials; no email will be delivered", e);
            return DeliveryOutcome.transientFailure(NAME, "relay authentication failed");

        } catch (MailSendException e) {
            return classify(e);

        } catch (Exception e) {
            log.warn("SMTP send failed for {}: {}", command.notificationId(), e.getMessage());
            return DeliveryOutcome.transientFailure(NAME, e.getMessage());
        }
    }

    /**
     * A 5xx reply is a permanent refusal — no such mailbox, message rejected as spam. A 4xx is the
     * relay asking us to come back later, and a connection problem is the same in practice.
     *
     * <p>The reply code is read off the exception rather than matched out of its text. Text matching
     * is what this used to do, and it read the relay's <em>port number</em> as a reply code: JavaMail
     * renders an unreachable relay as {@code "Could not connect to SMTP host: ..., port: 587"}, and
     * 587 is both the standard submission port and a plausible-looking 5xx. Every email sent during
     * a relay outage was therefore classified permanent and dead-lettered instead of retried — order
     * confirmations, verification codes, application decisions — and only in production, because the
     * dev relay listens on 1025 and never matched.
     */
    private DeliveryOutcome classify(MailSendException e) {
        Integer replyCode = smtpReplyCode(e);
        String message = String.valueOf(e.getMessage());

        if (replyCode == null) {
            // No reply code means the relay never answered — connection refused, DNS, timeout.
            // Nothing about the message itself was rejected, so it is worth sending again.
            return DeliveryOutcome.transientFailure(NAME, message);
        }
        return replyCode >= 500
                ? DeliveryOutcome.permanentFailure(NAME, message)
                : DeliveryOutcome.transientFailure(NAME, message);
    }

    /**
     * The SMTP reply code the relay actually sent, or null if it never got that far.
     *
     * <p>Walks the per-recipient failures and their cause chains, because {@code MailSendException}
     * carries the interesting exception underneath rather than being it.
     */
    private static Integer smtpReplyCode(MailSendException e) {
        for (Exception failure : e.getFailedMessages().values()) {
            Integer code = replyCodeIn(failure);
            if (code != null) {
                return code;
            }
        }
        return replyCodeIn(e);
    }

    private static Integer replyCodeIn(Throwable throwable) {
        for (Throwable current = throwable; current != null; current = current.getCause()) {
            if (current instanceof SMTPSendFailedException failed) {
                return failed.getReturnCode();
            }
            if (current instanceof SMTPAddressFailedException failed) {
                return failed.getReturnCode();
            }
            if (current == current.getCause()) {
                break;
            }
        }
        return null;
    }
}
