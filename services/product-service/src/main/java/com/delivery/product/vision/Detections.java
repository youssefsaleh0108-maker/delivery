package com.delivery.product.vision;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.ArrayList;
import java.util.List;

import com.delivery.product.vision.VisionProvider.Box;
import com.delivery.product.vision.VisionProvider.Detection;

/**
 * The one gate every provider's output passes through before it is stored.
 *
 * <p>Provider-agnostic on purpose. The fake is trustworthy and the model is not, but a rule applied
 * to only one of them is a rule that is missing the day a third provider lands. Everything here
 * errs towards dropping a field rather than storing a wrong one:
 * <ul>
 *   <li>text is stripped of control characters and capped at its column's width — a label read off
 *       a box reaches a shopkeeper's screen and, once accepted, a customer's;</li>
 *   <li>a line with no name, or pointing at a photo that was not sent, is dropped whole;</li>
 *   <li>a price guess outside a plausible shelf range is dropped, not clamped — a clamped guess is
 *       still a number the platform does not actually have;</li>
 *   <li>a box that does not fit inside its photo is dropped, and the tag simply is not drawn.</li>
 * </ul>
 */
public final class Detections {

    public static final int MAX_NAME = 200;
    public static final int MAX_BRAND = 120;
    public static final int MAX_SIZE = 60;
    public static final int MAX_CATEGORY = 128;

    /** No shelf item in a corner shop is a thousand dollars; a guess that says so is noise. */
    private static final BigDecimal MAX_GUESS = new BigDecimal("999.99");
    private static final BigDecimal MIN_GUESS = new BigDecimal("0.01");

    /** Rounding slack for a box that ends exactly on the photo's edge. */
    private static final double EDGE_TOLERANCE = 0.0001;

    private Detections() {
    }

    /** A detection that survived, with every field already safe to store. */
    public record Clean(int photoIndex, String name, String brand, String size, String category,
                        BigDecimal confidence, BigDecimal priceGuess, Box box) {
    }

    public static List<Clean> sanitize(List<Detection> raw, int photoCount, int maxItems) {
        List<Clean> kept = new ArrayList<>();
        if (raw == null) {
            return kept;
        }
        for (Detection d : raw) {
            if (kept.size() >= maxItems) {
                break;
            }
            if (d == null || d.photoIndex() < 0 || d.photoIndex() >= photoCount) {
                continue;
            }
            String name = text(d.name(), MAX_NAME);
            if (name == null) {
                continue;
            }
            kept.add(new Clean(
                    d.photoIndex(),
                    name,
                    text(d.brand(), MAX_BRAND),
                    text(d.size(), MAX_SIZE),
                    text(d.category(), MAX_CATEGORY),
                    confidence(d.confidence()),
                    guess(d.priceGuess()),
                    box(d.box())));
        }
        return kept;
    }

    /**
     * Control characters out, whitespace collapsed, capped at {@code max} code points.
     *
     * <p>Capped by code point rather than by {@code char}: Arabic and emoji both arrive, and cutting
     * a surrogate pair in half stores a string that is not valid UTF-16.
     */
    static String text(String value, int max) {
        if (value == null) {
            return null;
        }
        StringBuilder out = new StringBuilder();
        boolean space = false;
        int count = 0;
        for (int i = 0; i < value.length() && count < max; ) {
            int cp = value.codePointAt(i);
            i += Character.charCount(cp);
            if (Character.isISOControl(cp) || Character.isWhitespace(cp)
                    || Character.getType(cp) == Character.FORMAT && cp != 0x200C && cp != 0x200D) {
                // Zero-width joiners stay: Arabic and Persian shaping legitimately needs them.
                space = out.length() > 0;
                continue;
            }
            if (space) {
                out.append(' ');
                count++;
                space = false;
                if (count >= max) {
                    break;
                }
            }
            out.appendCodePoint(cp);
            count++;
        }
        String cleaned = out.toString().trim();
        return cleaned.isEmpty() ? null : cleaned;
    }

    static BigDecimal confidence(double value) {
        if (Double.isNaN(value)) {
            return BigDecimal.ZERO.setScale(3);
        }
        double clamped = Math.max(0d, Math.min(1d, value));
        return BigDecimal.valueOf(clamped).setScale(3, RoundingMode.HALF_UP);
    }

    static BigDecimal guess(BigDecimal value) {
        if (value == null) {
            return null;
        }
        BigDecimal cents = value.setScale(2, RoundingMode.HALF_UP);
        if (cents.compareTo(MIN_GUESS) < 0 || cents.compareTo(MAX_GUESS) > 0) {
            return null;
        }
        return cents;
    }

    static Box box(Box value) {
        if (value == null) {
            return null;
        }
        double l = value.left();
        double t = value.top();
        double w = value.width();
        double h = value.height();
        if (!(Double.isFinite(l) && Double.isFinite(t) && Double.isFinite(w) && Double.isFinite(h))) {
            return null;
        }
        if (l < 0 || t < 0 || w <= 0 || h <= 0
                || l + w > 1 + EDGE_TOLERANCE || t + h > 1 + EDGE_TOLERANCE) {
            return null;
        }
        return value;
    }

    /**
     * Parses a price the provider sent as text, which is how the structured output carries it — a
     * decimal string, so no binary float ever stands between the model and a money column.
     */
    public static BigDecimal parseGuess(String text) {
        if (text == null) {
            return null;
        }
        String trimmed = text.trim().replace("$", "").replace("USD", "").trim();
        if (trimmed.isEmpty()) {
            return null;
        }
        try {
            return guess(new BigDecimal(trimmed));
        } catch (NumberFormatException e) {
            return null;
        }
    }
}
