package com.delivery.appnotification.service;

/**
 * The sender's text was not acceptable — too long, empty, or carrying characters that cannot be
 * stored.
 *
 * <p>Its own type rather than {@link IllegalArgumentException} so the controller can answer 422
 * ("I understood you and I am refusing") instead of the 400 that a malformed request body gets. The
 * client's handling differs: a 400 is a bug to report, a 422 is something to show the sender so
 * they can shorten what they typed.
 *
 * <p>The message on this exception is returned to the caller, so it must never contain the
 * offending text.
 */
public class MessageRejectedException extends RuntimeException {

    public MessageRejectedException(String message) {
        super(message);
    }
}
