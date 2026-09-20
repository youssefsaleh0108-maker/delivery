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

    /**
     * One photo of one product in, what the product is out: photo search.
     *
     * <p>A different question from {@link #detect}. A shelf reading lists everything on a shelf and
     * nothing on a photo that is not of shelves, so a product held in someone's hand comes back empty
     * from it. This asks about the one product a shopper — or a shopkeeper finding it in their own
     * catalogue — pointed the camera at, and for the words to search for it by, in English and Arabic.
     *
     * <p>A photo of no product at all is an answer ({@code isProduct} false), not a failure. A provider
     * that could not be reached, or that declined, throws {@link VisionException}, as {@link #detect}
     * does. Whatever comes back is untrusted: {@link Descriptions#sanitize} cleans it before anything
     * reads it.
     *
     * @param photo the photo, already upright, shrunk and re-encoded as JPEG
     */
    ProductDescription describe(ProductPhoto photo);

    /** One shelf photo, as JPEG bytes. */
    record ShelfPhoto(byte[] jpeg) {
    }

    /**
     * One photo of one product, as JPEG bytes. Held only for the length of one {@link #describe}
     * call: nothing keeps it afterwards.
     */
    record ProductPhoto(byte[] jpeg) {
    }

    /**
     * What a provider says a product photo shows, exactly as reported — before sanitising.
     *
     * @param isProduct  whether the photo shows a product a shop sells at all
     * @param name       the product as a shopper would search for it, spelled as on the pack
     * @param nameAr     its Arabic name, as printed or as a Lebanese shop would list it
     * @param brand      as printed
     * @param size       the pack size as printed, e.g. "1 L"
     * @param keywords   generic words for what it is, in English and Arabic, most specific first
     * @param barcode    the digits under the barcode, only when every one was legible
     * @param confidence 0 to 1, the provider's own certainty about the name
     */
    record ProductDescription(boolean isProduct, String name, String nameAr, String brand, String size,
                              List<String> keywords, String barcode, double confidence) {
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
