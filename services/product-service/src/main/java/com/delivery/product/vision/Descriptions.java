package com.delivery.product.vision;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;

import com.delivery.product.vision.VisionProvider.ProductDescription;

/**
 * The one gate every provider's product description passes through before anything reads it.
 *
 * <p>{@link Detections}' rules, for photo search: provider-agnostic, and erring towards dropping a
 * field rather than keeping a wrong one. Text is stripped of control characters and capped with
 * {@link Detections#text}, since it becomes search terms, a chip on a customer's screen and a name
 * prefilled into a merchant's product form. The barcode is kept only when it is a real GTIN — 8, 12, 13
 * or 14 digits whose last digit is the GS1 check digit of the others — because a barcode is matched
 * exactly, and a misread digit would find somebody else's product, or file a wrong code in a merchant's
 * catalogue.
 */
public final class Descriptions {

    /** Keywords kept: enough for a fallback search in both languages. */
    public static final int MAX_KEYWORDS = 5;

    /** A keyword is a word or a short phrase ("soft drink", "مشروب غازي"), never a sentence. */
    public static final int MAX_KEYWORD = 60;

    private Descriptions() {
    }

    /**
     * A description that survived, every field safe to use.
     *
     * @param isProduct false when the photo showed no product, or nothing searchable was read off it;
     *                  every other field is then empty
     * @param keywords  at most {@value #MAX_KEYWORDS}, distinct ignoring case, in the provider's order
     * @param barcode   a GTIN with a valid check digit, or null
     */
    public record Clean(boolean isProduct, String name, String nameAr, String brand, String size,
                        List<String> keywords, String barcode, BigDecimal confidence) {

        public Clean {
            keywords = keywords == null ? List.of() : List.copyOf(keywords);
        }

        /** No product: what a photo of a person, a street or an empty table is answered with. */
        public static Clean notAProduct() {
            return new Clean(false, null, null, null, null, List.of(), null,
                    BigDecimal.ZERO.setScale(3));
        }
    }

    public static Clean sanitize(ProductDescription raw) {
        if (raw == null || !raw.isProduct()) {
            return Clean.notAProduct();
        }
        String name = Detections.text(raw.name(), Detections.MAX_NAME);
        String nameAr = Detections.text(raw.nameAr(), Detections.MAX_NAME);
        String barcode = gtin(raw.barcode());
        if (name == null && nameAr == null && barcode == null) {
            // A product the provider could not name in either language and whose code it could not
            // read is nothing anybody can search for.
            return Clean.notAProduct();
        }
        return new Clean(true, name, nameAr,
                Detections.text(raw.brand(), Detections.MAX_BRAND),
                Detections.text(raw.size(), Detections.MAX_SIZE),
                keywords(raw.keywords()),
                barcode,
                Detections.confidence(raw.confidence()));
    }

    static List<String> keywords(List<String> raw) {
        List<String> kept = new ArrayList<>();
        if (raw == null) {
            return kept;
        }
        Set<String> seen = new LinkedHashSet<>();
        for (String keyword : raw) {
            if (kept.size() >= MAX_KEYWORDS) {
                break;
            }
            String clean = Detections.text(keyword, MAX_KEYWORD);
            if (clean != null && seen.add(clean.toLowerCase(Locale.ROOT))) {
                kept.add(clean);
            }
        }
        return kept;
    }

    /**
     * The digits, when they are a GTIN-8, GTIN-12 (UPC-A), GTIN-13 (EAN) or GTIN-14 whose check digit
     * is right; otherwise null. Spaces and hyphens a reader copied from the print are dropped first;
     * anything else that is not a digit makes it no barcode.
     */
    public static String gtin(String raw) {
        if (raw == null) {
            return null;
        }
        String digits = raw.replace(" ", "").replace("-", "");
        int length = digits.length();
        if (length != 8 && length != 12 && length != 13 && length != 14) {
            return null;
        }
        for (int i = 0; i < length; i++) {
            char c = digits.charAt(i);
            if (c < '0' || c > '9') {
                return null;
            }
        }
        return checkDigit(digits.substring(0, length - 1)) == digits.charAt(length - 1) - '0'
                ? digits : null;
    }

    /**
     * GS1's check digit for the digits before it: from the right, weights 3, 1, 3, 1…, and the digit
     * that brings the sum up to a multiple of ten. The same rule for every GTIN length.
     */
    static int checkDigit(String body) {
        int sum = 0;
        boolean three = true;
        for (int i = body.length() - 1; i >= 0; i--) {
            sum += (body.charAt(i) - '0') * (three ? 3 : 1);
            three = !three;
        }
        return (10 - sum % 10) % 10;
    }
}
