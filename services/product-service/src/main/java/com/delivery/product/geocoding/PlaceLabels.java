package com.delivery.product.geocoding;

/**
 * Cleans text that came back from a geocoder.
 *
 * <p>Every label a geocoder returns is text a stranger typed into somebody else's database.
 * OpenStreetMap is world-writable; a Mapbox label carries whatever a business owner put on their
 * listing. It arrives here and goes straight onto a customer's screen, so it is data from an
 * untrusted source in the ordinary sense, and the platform's rule for that is the same everywhere:
 * do not hand it on unexamined.
 *
 * <p>What this does <em>not</em> do is HTML-escape. Escaping here would be the wrong layer and
 * actively harmful: this service returns JSON, an apostrophe in "L'Épicerie" is not a threat to a
 * JSON parser, and pre-escaping would render {@code &amp;#39;} in every client that correctly treats
 * the value as text. The rule the platform states — never echo user text into a response something
 * might render as HTML — is satisfied by never producing HTML here and by clients binding text
 * rather than setting innerHTML. What is removed below is the part that is hostile in <em>any</em>
 * rendering: control characters, which can hide content or break log lines, and unbounded length.
 */
final class PlaceLabels {

    /**
     * Longer than any real address and short enough that no single label can dominate a response.
     * Nominatim's own {@code display_name} tops out well under this for a street; anything past it
     * is a very long administrative chain, and truncating it costs nothing a customer reads.
     */
    private static final int MAX_LENGTH = 300;

    private PlaceLabels() {
    }

    /**
     * @return the cleaned label, or null when there was nothing usable. Null rather than an empty
     *         string, so a caller can tell "the provider gave no label" from "the provider gave a
     *         blank one" — the first is normal, the second is a provider bug worth seeing.
     */
    static String clean(String raw) {
        if (raw == null) {
            return null;
        }

        // Strips C0 and C1 controls, including the newlines and tabs that would otherwise let a
        // label forge extra lines in a log or a plain-text render. \p{Cntrl} alone misses C1.
        String cleaned = raw.replaceAll("[\\p{Cntrl}\\u0080-\\u009F]", " ")
                .replaceAll("\\s+", " ")
                .trim();

        if (cleaned.isEmpty()) {
            return null;
        }
        return cleaned.length() > MAX_LENGTH ? cleaned.substring(0, MAX_LENGTH).trim() : cleaned;
    }
}
