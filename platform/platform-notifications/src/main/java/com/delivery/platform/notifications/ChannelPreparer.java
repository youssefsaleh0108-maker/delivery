package com.delivery.platform.notifications;

/**
 * The one thing a channel worker does that the other two do not.
 *
 * <p>A worker is not a pass-through. Between the manager's rendered message and the connector's
 * provider call sits work that is genuinely channel-specific — SMS segmentation and GSM-alphabet
 * limits, email MIME assembly and address validation, push payload shaping and token checks. That
 * belongs in the worker rather than the connector, because it is a property of the channel, not of
 * the vendor: swapping Twilio for MontyMobile does not change how an SMS segments.
 *
 * <p>Rejecting here is worth more than rejecting at the provider. A malformed phone number caught
 * in the worker costs nothing; the same number sent to a paid vendor costs a request, a retry
 * budget and, on some plans, money.
 */
public interface ChannelPreparer {

    Prepared prepare(NotificationCommand command);

    /**
     * Either a command ready for the connector, or a permanent rejection.
     *
     * @param command   what to hand the connector; null when rejected
     * @param rejection why this can never be sent; null when accepted
     */
    record Prepared(NotificationCommand command, String rejection) {

        public static Prepared ready(NotificationCommand command) {
            return new Prepared(command, null);
        }

        /** Permanent by definition — nothing about a retry would make the message valid. */
        public static Prepared reject(String reason) {
            return new Prepared(null, reason);
        }

        public boolean rejected() {
            return rejection != null;
        }
    }
}
