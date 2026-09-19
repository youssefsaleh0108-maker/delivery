package com.delivery.platform.notifications;

import java.util.Optional;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Keeping one-time codes out of everything except the message that delivers them.
 *
 * <p>A verification or passcode-reset code is a credential for as long as it lives: whoever reads it
 * can prove an address, or set the passcode of the account behind it. The message has to carry it,
 * because that is what the message is for. Nothing that stays behind may: not Notifications
 * Manager's delivery log, which back office reads through an API; not the dead-letter queue, which
 * keeps a failed command until somebody empties it; not an application log line. Each of those held
 * every code the platform sent, and the first of them let anybody with back-office access ask for a
 * code to any address, read it back, and take the account.
 *
 * <p>Two halves, split by who knows what. Notifications Manager knows which messages carry a code,
 * because it owns their purposes, and marks their commands with {@link #FLAG}. Everything downstream
 * (a worker parking a failure, a dev connector logging what it would have sent) knows only the mark,
 * and masks with {@link #mask} before it keeps anything.
 *
 * <p><strong>A code is found as a run of four or more digits.</strong> Every code on the platform is
 * one, six digits today, and taking every such run out of a code-bearing message costs nothing: the
 * rest of those messages is fixed prose with no long numbers in it. A code that stopped being all
 * digits would slip past this, so a change to its shape has to change this rule with it.
 */
public final class OneTimeCodes {

    /** The metadata key a command carries, set to {@code "true"}, when its text holds a code. */
    public static final String FLAG = "carriesOneTimeCode";

    /** What a code is replaced with wherever it would otherwise be kept. */
    public static final String MASK = "******";

    private static final Pattern CODE = Pattern.compile("\\d{4,}");

    private OneTimeCodes() {
    }

    /** Whether this command's subject or body holds a code, going by the mark its sender put on it. */
    public static boolean carriedBy(NotificationCommand command) {
        return command != null && command.metadata() != null
                && "true".equals(command.metadata().get(FLAG));
    }

    /** The text with every code in it masked. Null stays null. */
    public static String mask(String text) {
        return text == null ? null : CODE.matcher(text).replaceAll(Matcher.quoteReplacement(MASK));
    }

    /**
     * The first code in the text.
     *
     * <p>For the one place allowed to keep a code at all: Notifications Manager's sink for the reserved
     * test domain, which exists so smoke tests can sign up without an inbox.
     */
    public static Optional<String> find(String text) {
        if (text == null) {
            return Optional.empty();
        }
        Matcher matcher = CODE.matcher(text);
        return matcher.find() ? Optional.of(matcher.group()) : Optional.empty();
    }

    /**
     * The command as anything that keeps a copy may keep it: subject and body masked when it is
     * marked as carrying a code, and unchanged when it is not. Recipient, channel, ids and metadata
     * stay, since those are what somebody investigating a failed send needs.
     */
    public static NotificationCommand masked(NotificationCommand command) {
        if (!carriedBy(command)) {
            return command;
        }
        return new NotificationCommand(
                command.notificationId(),
                command.channel(),
                command.recipient(),
                mask(command.subject()),
                mask(command.body()),
                command.metadata(),
                command.correlationId(),
                command.createdAt());
    }
}
