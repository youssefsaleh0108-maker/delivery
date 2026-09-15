package com.delivery.product.vision;

import java.math.BigDecimal;
import java.util.List;

/**
 * Something that can look at shelf photos and say what products are on them.
 *
 * <p>An interface for the same reason the geocoder is one ({@code GeocodingProvider}): the feature
 * has to run somewhere free before anybody has a key, and moving to a paid provider afterwards
 * should be configuration, not a project. The implementations are {@link FakeVisionProvider} —
 * deterministic sample data, never leaves the pod, what runs by default — and
 * {@link ClaudeVisionProvider}, which sends the photos to the Claude API.
 *
 * <p>Everything a provider returns is untrusted. The text on a shelf is text a stranger printed on
 * a box, and a model reading it is one step removed from that; {@link Detections#sanitize} caps and
 * cleans every field before any of it is stored, whichever provider answered.
 */
public interface VisionProvider {

    /** The name this provider is selected by — the value of the config property. */
    String name();

    /**
     * Whether this provider can answer right now.
     *
     * <p>False for a provider whose credential is absent. {@link VisionProviders} then answers with
     * the fake instead, and the scan records that it did — so the merchant sees sample results
     * labelled as samples rather than a failure they can do nothing about.
     */
    default boolean isReady() {
        return true;
    }

    /**
     * Photos in, detected products out.
     *
     * <p>An empty list is an answer — a photo of an empty shelf — and not a failure. A provider that
     * could not be reached, or that declined, throws {@link VisionException} instead, so the caller
     * can tell "nothing there" from "we do not know".
     *
     * @param photos        the shelf photos, already shrunk and re-encoded as JPEG, in order
     * @param categoryNames the sections a product may be filed under — the store's own first, then
     *                      the platform taxonomy. A provider may suggest one of these by name or
     *                      none; it may not invent one.
     */
    List<Detection> detect(List<ShelfPhoto> photos, List<String> categoryNames);

    /** One shelf photo, as JPEG bytes. */
    record ShelfPhoto(byte[] jpeg) {
    }

    /**
     * One product on one photo, exactly as the provider reported it — before sanitising.
     *
     * @param photoIndex which photo, 0-based, in the order they were passed in
     * @param category   one of the offered category names, or blank for "no suggestion"
     * @param confidence 0 to 1, the provider's own certainty; carried so the review screen can put
     *                   doubtful lines first rather than presenting every line as equally sure
     * @param priceGuess a typical shelf price in USD, as a GUESS; null when the provider offered none
     * @param box        where the product sits on its photo, or null when the provider could not say
     */
    record Detection(int photoIndex, String name, String brand, String size, String category,
                     double confidence, BigDecimal priceGuess, Box box) {
    }

    /** Fractions of the photo's width and height, top-left origin. */
    record Box(double left, double top, double width, double height) {
    }
}
