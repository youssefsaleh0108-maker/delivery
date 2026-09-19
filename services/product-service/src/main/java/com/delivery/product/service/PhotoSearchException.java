package com.delivery.product.service;

/**
 * Why a photo was not read, or not searched: one exception for every refusal of photo search and of a
 * merchant's find by photo, each with the HTTP status and the {@code code} a client branches on
 * ({@code ApiExceptionHandler#onPhotoSearchRefused}).
 *
 * <p>The detail is written here, in English, and names the rule — never the photo, what it was read
 * as, or the account. The apps word each code in the user's own language.
 */
public class PhotoSearchException extends RuntimeException {

    /** The refusals, with their status and code. */
    public enum Refusal {
        /** No real reader is configured, or customer photo search is switched off. */
        UNAVAILABLE(503, "PHOTO_SEARCH_UNAVAILABLE"),
        /** A customer's photo search limit: per day, per minute, or the platform's day. */
        SEARCH_LIMIT(429, "PHOTO_SEARCH_LIMIT"),
        /** A merchant's find-by-photo limit: per day or per minute. */
        FIND_LIMIT(429, "PHOTO_FIND_LIMIT"),
        /** Every reader slot is taken; nothing was counted. */
        BUSY(503, "PHOTO_READER_BUSY"),
        /** Over the largest photo accepted. */
        TOO_LARGE(413, "PHOTO_TOO_LARGE"),
        /** Not a JPEG or a PNG. */
        TYPE(415, "PHOTO_TYPE"),
        /** A JPEG or PNG that could not be decoded, or one larger than the reader decodes. */
        UNREADABLE(422, "PHOTO_UNREADABLE"),
        /** The reader looked and declined, on every model its fallback chain tried. */
        REFUSED(422, "PHOTO_REFUSED"),
        /** The reader could not be reached, timed out, or answered with something unusable. */
        FAILED(502, "PHOTO_READER_FAILED"),
        /** No photo in the request. The apps always send one; this is a caller's mistake. */
        MISSING(400, "PHOTO_MISSING");

        private final int status;
        private final String code;

        Refusal(int status, String code) {
            this.status = status;
            this.code = code;
        }

        public int status() {
            return status;
        }

        public String code() {
            return code;
        }
    }

    /**
     * Which limit a 429 is about, so an app can say "10 a day" or "wait a minute" or "photo search is
     * busy today" rather than one sentence for three different situations.
     */
    public enum Scope {
        /** The account's rolling day. */
        DAY,
        /** The account's last minute. */
        MINUTE,
        /** Every customer's photo searches over the platform's rolling day. */
        PLATFORM
    }

    private final Refusal refusal;
    private final Integer limit;
    private final Scope scope;
    private final Long retryAfterSeconds;

    private PhotoSearchException(Refusal refusal, String message, Integer limit, Scope scope,
                                 Long retryAfterSeconds) {
        super(message);
        this.refusal = refusal;
        this.limit = limit;
        this.scope = scope;
        this.retryAfterSeconds = retryAfterSeconds;
    }

    public static PhotoSearchException unavailable() {
        return new PhotoSearchException(Refusal.UNAVAILABLE,
                "Search by photo is not available right now. Search by name instead.", null, null, null);
    }

    /**
     * A limit reached.
     *
     * @param merchant whether it is a merchant's find ({@code PHOTO_FIND_LIMIT}) rather than a
     *                 customer's search ({@code PHOTO_SEARCH_LIMIT})
     */
    public static PhotoSearchException limit(boolean merchant, int limit, Scope scope,
                                             long retryAfterSeconds) {
        String message = switch (scope) {
            case DAY -> "You can use " + limit + " photos a day. Try again later.";
            case MINUTE -> "You can use " + limit + " photos a minute. Wait a moment and try again.";
            case PLATFORM -> "Search by photo is very busy today. Try again later, or search by name.";
        };
        return new PhotoSearchException(merchant ? Refusal.FIND_LIMIT : Refusal.SEARCH_LIMIT, message,
                limit, scope, Math.max(1L, retryAfterSeconds));
    }

    public static PhotoSearchException busy(long retryAfterSeconds) {
        return new PhotoSearchException(Refusal.BUSY,
                "Too many photos are being read right now. Try again in a moment.", null, null,
                Math.max(1L, retryAfterSeconds));
    }

    public static PhotoSearchException tooLarge(long maxBytes) {
        return new PhotoSearchException(Refusal.TOO_LARGE,
                "A photo can be at most " + maxBytes + " bytes.", null, null, null);
    }

    public static PhotoSearchException type() {
        return new PhotoSearchException(Refusal.TYPE, "Send the photo as a JPEG or a PNG.", null, null,
                null);
    }

    public static PhotoSearchException unreadable() {
        return new PhotoSearchException(Refusal.UNREADABLE,
                "The photo could not be read. Try another photo.", null, null, null);
    }

    public static PhotoSearchException refused() {
        return new PhotoSearchException(Refusal.REFUSED,
                "This photo cannot be searched. Try another photo.", null, null, null);
    }

    public static PhotoSearchException failed() {
        return new PhotoSearchException(Refusal.FAILED,
                "The photo could not be read just now. Try again.", null, null, null);
    }

    public static PhotoSearchException missing() {
        return new PhotoSearchException(Refusal.MISSING,
                "Send the photo as the multipart part named 'photo'.", null, null, null);
    }

    public Refusal refusal() {
        return refusal;
    }

    public String getCode() {
        return refusal.code();
    }

    /** The limit reached, for a 429; null otherwise. */
    public Integer getLimit() {
        return limit;
    }

    /** Which limit, for a 429; null otherwise. */
    public Scope getScope() {
        return scope;
    }

    /** How long to wait, for a 429 or a busy reader; null otherwise. */
    public Long getRetryAfterSeconds() {
        return retryAfterSeconds;
    }
}
