package com.delivery.appnotification.service;

import java.util.UUID;

/**
 * There is no such conversation, <em>or</em> the caller is not in it.
 *
 * <p>One exception for both on purpose, and the merged case is the security property rather than a
 * shortcut. Answering 403 for "exists but not yours" and 404 for "no such thing" turns the endpoint
 * into an oracle: a rider could walk order ids and learn which ones have a live chat, and which
 * customer ids are real. Since the caller cannot tell the two apart, there is nothing to learn.
 *
 * <p>The message names only the id the caller already supplied. It never names the other
 * participant or the order behind a conversation id, because it is rendered into a ProblemDetail
 * that goes back to whoever asked.
 */
public class ConversationNotFoundException extends RuntimeException {

    public ConversationNotFoundException(UUID id) {
        super("No conversation " + id + " is visible to this user");
    }
}
