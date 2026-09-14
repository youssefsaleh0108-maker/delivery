package com.delivery.appnotification.service;

import java.time.Duration;
import java.time.Instant;
import java.util.UUID;

/**
 * The refusals neighbourhood rooms and shop threads can give, each mapped to its own status by
 * {@code ChatExceptionHandler}.
 *
 * <p>Gathered in one holder because each is a few lines and they only make sense together: the
 * status a client receives is an instruction (stop asking, pick an area, wait, fix the text), and
 * reading them side by side is how that stays consistent.
 */
public final class RoomExceptions {

    private RoomExceptions() {
    }

    /**
     * 404. Also what a caller gets for a room that exists but is not theirs, so the answer leaks
     * nothing about which rooms or threads exist.
     */
    public static class RoomNotFoundException extends RuntimeException {
        public RoomNotFoundException(UUID id) {
            super("No such room or thread: " + id);
        }
    }

    /** Why the caller has no room to be placed in. */
    public enum NoRoomReason {
        /** Their delivery address names no area: addresses saved before areas existed have none. */
        NO_ZONE,
        /** The area they named is not one Product Service lists, or it has been retired. */
        UNKNOWN_ZONE
    }

    /** 404 with a reason, so the app can say "choose your area" instead of "something went wrong". */
    public static class NoNeighbourhoodException extends RuntimeException {
        private final NoRoomReason reason;

        public NoNeighbourhoodException(NoRoomReason reason) {
            super(reason == NoRoomReason.NO_ZONE
                    ? "Choose a delivery area to join its neighbourhood chat"
                    : "That delivery area has no neighbourhood chat");
            this.reason = reason;
        }

        public NoRoomReason getReason() {
            return reason;
        }
    }

    /** 403, with when it ends, so the composer can say so instead of failing each send. */
    public static class MemberMutedException extends RuntimeException {
        private final Instant mutedUntil;

        public MemberMutedException(Instant mutedUntil) {
            super("You can't post in this room right now");
            this.mutedUntil = mutedUntil;
        }

        public Instant getMutedUntil() {
            return mutedUntil;
        }
    }

    /**
     * 403 with a reason. The caller may read this room but not speak in it: no order of theirs has
     * been delivered in its area recently enough. The app draws the composer read-only and says what
     * would open it, instead of failing each send.
     */
    public static class PostingLockedException extends RuntimeException {
        public PostingLockedException() {
            super("You can post in this room after an order of yours is delivered in its area");
        }
    }

    /**
     * 503. Order Manager could not say where the caller's orders were delivered. Posting waits rather
     * than guessing: "yes" would let any account speak in any room, and "no" would tell a neighbour of
     * years that they have never had a delivery.
     */
    public static class ProofUnavailableException extends RuntimeException {
        public ProofUnavailableException(String message, Throwable cause) {
            super(message, cause);
        }
    }

    /** 429 with Retry-After. */
    public static class SendRateLimitedException extends RuntimeException {
        private final Duration retryAfter;

        public SendRateLimitedException(Duration retryAfter) {
            super("Too many messages; wait a moment before sending another");
            this.retryAfter = retryAfter;
        }

        public Duration getRetryAfter() {
            return retryAfter;
        }
    }

    /**
     * 503. Product Service could not be asked a question the answer depends on — whether an area is
     * real, whether a shop exists, which shops a merchant owns. Refusing is the only safe answer:
     * guessing "yes" would let anybody in, guessing "no" would tell a real customer their area does
     * not exist.
     */
    public static class DirectoryUnavailableException extends RuntimeException {
        public DirectoryUnavailableException(String message, Throwable cause) {
            super(message, cause);
        }
    }

    /**
     * 503. Order Manager could not say whether an order is the caller's. Opening a thread from that
     * order waits rather than guessing: "yes" would put somebody else's order in front of a shop, and
     * "no" would tell a customer their own order does not exist. An open without an order never asks
     * Order Manager, so it is unaffected.
     */
    public static class OrderUnavailableException extends RuntimeException {
        public OrderUnavailableException(String message, Throwable cause) {
            super(message, cause);
        }
    }

    /**
     * 409, with when it closed. The order is one of the caller's shop's and is on their screen, but it
     * was delivered or cancelled longer ago than a shop may open a conversation about it. Null
     * {@code closedAt} only for an ended order Order Manager recorded no end time for, which is refused
     * rather than treated as open.
     */
    public static class OrderChatClosedException extends RuntimeException {
        private final Instant closedAt;

        public OrderChatClosedException(UUID orderId, Instant closedAt) {
            super("The shop's chat about order " + orderId + " closed at " + closedAt);
            this.closedAt = closedAt;
        }

        public Instant getClosedAt() {
            return closedAt;
        }
    }
}
