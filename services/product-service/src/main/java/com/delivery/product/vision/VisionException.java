package com.delivery.product.vision;

/**
 * A vision provider could not produce an answer.
 *
 * <p>Distinct from an empty result, which is an answer. The reason is carried as a value so the scan
 * can record a code the client words in the merchant's language, rather than whatever English a
 * vendor put in an error body.
 */
public class VisionException extends RuntimeException {

    public enum Reason {
        /** The provider looked and declined — on every model its fallback chain tried. */
        REFUSED,
        /** Unreachable, timed out, rate-limited, or answered with something unusable. */
        PROVIDER_ERROR,
        /** No provider by the configured name, or the configured one has no credential. */
        NOT_CONFIGURED
    }

    private final Reason reason;

    public VisionException(Reason reason, String message) {
        super(message);
        this.reason = reason;
    }

    public VisionException(Reason reason, String message, Throwable cause) {
        super(message, cause);
        this.reason = reason;
    }

    public Reason reason() {
        return reason;
    }
}
