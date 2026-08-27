package com.delivery.product.geocoding;

/**
 * The geocoder could not answer.
 *
 * <p>Deliberately distinct from an empty result. "There is no such street" is an answer the address
 * picker should show; "the provider is unreachable, or refused us, or is not configured" is a
 * failure the caller must not present as an empty list, because the customer would conclude their
 * address does not exist and give up. {@code ApiExceptionHandler} maps this to 503.
 *
 * <p>The message is safe to return to a caller: it names the provider and the condition, never a
 * credential and never the query — a search term here is somebody's home address.
 */
public class GeocodingException extends RuntimeException {

    public GeocodingException(String message) {
        super(message);
    }

    public GeocodingException(String message, Throwable cause) {
        super(message, cause);
    }
}
