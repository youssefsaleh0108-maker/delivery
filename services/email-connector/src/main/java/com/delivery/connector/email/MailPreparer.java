package com.delivery.connector.email;

import java.util.regex.Pattern;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import com.delivery.platform.notifications.ChannelPreparer;
import com.delivery.platform.notifications.NotificationCommand;

/**
 * Email-specific work: address validation, subject assembly, header-injection defence.
 *
 * <p>The last of those is the one that matters. Subjects are rendered from templates that
 * interpolate customer-controlled values — a product name, a delivery note — and a value containing
 * a newline would end the Subject header early and let the rest be read as headers of its own. That
 * is how a Bcc gets added to every order confirmation. Stripping CR and LF here closes it once, in
 * the one place all email passes through, rather than trusting every template author.
 */
@Component
public class MailPreparer implements ChannelPreparer {

    /**
     * Deliberately permissive. Full RFC 5322 validation rejects addresses that are legal and
     * deliverable, and the relay is the real authority on whether an address exists — this only
     * catches the shapes that are obviously not addresses at all.
     */
    private static final Pattern ADDRESS = Pattern.compile("^[^@\\s]+@[^@\\s.]+(\\.[^@\\s.]+)+$");

    /** RFC 5321's limit on a single header line before folding is required. */
    private static final int MAX_SUBJECT_LENGTH = 200;

    private final String defaultSubject;

    public MailPreparer(@Value("${delivery.email.default-subject:YouDrop}") String defaultSubject) {
        this.defaultSubject = defaultSubject;
    }

    @Override
    public Prepared prepare(NotificationCommand command) {
        String recipient = command.recipient() == null ? "" : command.recipient().trim();

        if (!ADDRESS.matcher(recipient).matches()) {
            return Prepared.reject("recipient is not a valid email address: " + recipient);
        }

        String body = command.body() == null ? "" : command.body().strip();
        if (body.isEmpty()) {
            return Prepared.reject("empty email body");
        }

        String subject = sanitiseSubject(command.subject());

        return Prepared.ready(new NotificationCommand(
                command.notificationId(),
                command.channel(),
                recipient,
                subject,
                body,
                command.metadata(),
                command.correlationId(),
                command.createdAt()));
    }

    /**
     * Removes anything that could break out of the Subject header, and supplies a default.
     *
     * <p>An empty subject is not an error worth failing a notification over — a message with a
     * generic subject reaches the customer, a rejected one does not.
     */
    private String sanitiseSubject(String subject) {
        if (subject == null || subject.isBlank()) {
            return defaultSubject;
        }

        String cleaned = subject.replaceAll("[\\r\\n]", " ").strip();
        if (cleaned.length() > MAX_SUBJECT_LENGTH) {
            cleaned = cleaned.substring(0, MAX_SUBJECT_LENGTH - 1) + "…";
        }
        return cleaned.isEmpty() ? defaultSubject : cleaned;
    }
}
