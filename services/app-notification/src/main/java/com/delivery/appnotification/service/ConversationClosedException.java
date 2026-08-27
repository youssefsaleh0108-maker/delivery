package com.delivery.appnotification.service;

import java.time.Instant;
import java.util.UUID;

/**
 * The conversation still exists and the caller is still in it, but it has stopped taking messages.
 *
 * <p>409 rather than 404: the thread is right there on the caller's screen and they can still read
 * it, so pretending it does not exist would be a lie the UI can immediately disprove. The client's
 * job here is to grey out the composer and point at support, which it can only do if it is told the
 * difference.
 */
public class ConversationClosedException extends RuntimeException {

    private final Instant closedAt;

    public ConversationClosedException(UUID conversationId, Instant closedAt) {
        super("Conversation " + conversationId + " closed at " + closedAt);
        this.closedAt = closedAt;
    }

    public Instant getClosedAt() {
        return closedAt;
    }
}
