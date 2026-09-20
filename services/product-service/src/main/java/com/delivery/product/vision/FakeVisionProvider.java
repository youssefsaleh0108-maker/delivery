package com.delivery.product.vision;

import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

import org.springframework.stereotype.Component;

/**
 * Sample detections that never leave the pod — the default, and what every environment runs until
 * somebody provisions a key.
 *
 * <p><strong>Deterministic</strong>: the same photo bytes give the same lines, every time, on every
 * machine. That is what makes the whole scan flow testable end to end — the API scenario can upload
 * a fixture and assert on exactly what comes back — and what stops a demo from looking different
 * each time somebody retries it.
 *
 * <p>It looks at the bytes only to seed that choice, never at the picture. Its lines are not about
 * the merchant's shelf, which is why a scan it answers carries {@code provider = FAKE} and the
 * client says "sample results" over them. Presenting these as a reading of the photo would be
 * showing a merchant numbers the platform does not have.
 */
@Component
public class FakeVisionProvider implements VisionProvider {

    public static final String NAME = "FAKE";

    /**
     * A shelf a Beirut minimarket might plausibly carry, with a group to match sections against, and
     * what photo search would say about each: its Arabic name and a few generic words in both languages.
     */
    private record Sample(String name, String nameAr, String brand, String size, String priceGuess,
                          Group group, List<String> keywords) {
    }

    /** How a sample finds a section, by a few words its name is likely to contain in either language. */
    private enum Group {
        DRINKS("drink", "beverage", "soda", "water", "مشروب", "مياه"),
        SNACKS("snack", "chips", "crisps", "sweets", "candy", "سناك", "حلويات", "تسالي"),
        DAIRY("dairy", "cheese", "milk", "ألبان", "أجبان", "حليب"),
        PANTRY("pantry", "grocery", "groceries", "food", "مؤن", "بقالة", "مواد غذائية"),
        HOUSEHOLD("household", "cleaning", "detergent", "منزل", "تنظيف");

        private final String[] words;

        Group(String... words) {
            this.words = words;
        }

        boolean matches(String section) {
            String lower = section.toLowerCase(Locale.ROOT);
            for (String word : words) {
                if (lower.contains(word)) {
                    return true;
                }
            }
            return false;
        }
    }

    private static final List<Sample> SHELF = List.of(
            new Sample("Pepsi 1L", "بيبسي 1 لتر", "Pepsi", "1 L", "1.20", Group.DRINKS,
                    List.of("cola", "soft drink", "كولا", "مشروب غازي")),
            new Sample("Lay's Classic", "ليز كلاسيك", "Lay's", "170 g", "0.80", Group.SNACKS,
                    List.of("potato chips", "crisps", "شيبس", "رقائق البطاطا")),
            new Sample("Tannourine Water 1.5L", "مياه تنورين 1.5 لتر", "Tannourine", "1.5 L", "0.60",
                    Group.DRINKS, List.of("water", "mineral water", "مياه", "مياه معدنية")),
            new Sample("Kinder Bueno", "كيندر بوينو", "Kinder", "43 g", "1.00", Group.SNACKS,
                    List.of("chocolate", "wafer", "شوكولا", "ويفر")),
            new Sample("Picon Cheese Portions", "جبنة بيكون", "Picon", "140 g", "2.50", Group.DAIRY,
                    List.of("cheese", "cheese portions", "جبنة", "أجبان")),
            new Sample("Nido Milk Powder", "حليب نيدو", "Nido", "900 g", "9.50", Group.DAIRY,
                    List.of("milk powder", "milk", "حليب بودرة", "حليب")),
            new Sample("Mymouné Apricot Jam", "مربى المشمش ميموني", "Mymouné", "450 g", "4.00",
                    Group.PANTRY, List.of("apricot jam", "jam", "مربى المشمش", "مربى")),
            new Sample("Al Wadi Tahini", "طحينة الوادي الأخضر", "Al Wadi Al Akhdar", "400 g", "2.20",
                    Group.PANTRY, List.of("tahini", "sesame paste", "طحينة", "طحينة سمسم")),
            new Sample("Maggi Chicken Stock", "مرقة دجاج ماجي", "Maggi", "20 cubes", "1.75",
                    Group.PANTRY, List.of("chicken stock", "stock cubes", "مرقة دجاج", "مكعبات مرقة")),
            new Sample("Persil Liquid Detergent", "برسيل سائل غسيل", "Persil", "3 L", "7.00",
                    Group.HOUSEHOLD, List.of("laundry detergent", "detergent", "سائل غسيل", "منظف")),
            new Sample("Pringles Original", "برينجلز أوريجينال", "Pringles", "165 g", "2.10",
                    Group.SNACKS, List.of("potato chips", "crisps", "شيبس", "رقائق البطاطا")),
            new Sample("Nescafé Classic", "نسكافيه كلاسيك", "Nescafé", "200 g", "6.50", Group.DRINKS,
                    List.of("instant coffee", "coffee", "قهوة سريعة التحضير", "قهوة")));

    @Override
    public String name() {
        return NAME;
    }

    /**
     * One sample product the photo's bytes choose, the same one every time for the same bytes.
     *
     * <p>Never about the photo, like every line this class gives, and never with a barcode: a sample's
     * name is visibly a sample under its label, but a made-up code prefilled into a merchant's product
     * form would pass for a real one. Photo search for customers never asks the fake at all
     * ({@link VisionProviders#real}); a merchant finding a product by photo does, and is told the answer
     * is a sample.
     */
    @Override
    public ProductDescription describe(ProductPhoto photo) {
        byte[] seed = digest(photo == null ? null : photo.jpeg());
        Sample sample = SHELF.get(Math.floorMod(seed[1], SHELF.size()));
        double confidence = 0.70 + (Math.floorMod(seed[2], 256) / 255d) * 0.29;
        return new ProductDescription(true, sample.name(), sample.nameAr(), sample.brand(), sample.size(),
                sample.keywords(), null, confidence);
    }

    @Override
    public List<Detection> detect(List<ShelfPhoto> photos, List<String> categoryNames) {
        List<Detection> found = new ArrayList<>();
        for (int index = 0; index < photos.size(); index++) {
            byte[] seed = digest(photos.get(index).jpeg());

            // Three to six lines per photo, starting somewhere on the shelf the bytes choose.
            int count = 3 + Math.floorMod(seed[0], 4);
            int start = Math.floorMod(seed[1], SHELF.size());

            for (int k = 0; k < count; k++) {
                Sample sample = SHELF.get((start + k) % SHELF.size());
                // A grid of three per row, so the tags land somewhere sensible over the photo.
                Box box = new Box(0.05 + (k % 3) * 0.31, 0.08 + (k / 3) * 0.45, 0.25, 0.35);
                double confidence = 0.70 + (Math.floorMod(seed[2 + k], 256) / 255d) * 0.29;
                found.add(new Detection(index, sample.name(), sample.brand(), sample.size(),
                        sectionFor(sample.group(), categoryNames), confidence,
                        new BigDecimal(sample.priceGuess()), box));
            }
        }
        return found;
    }

    private static String sectionFor(Group group, List<String> categoryNames) {
        for (String section : categoryNames) {
            if (section != null && group.matches(section)) {
                return section;
            }
        }
        return "";
    }

    private static byte[] digest(byte[] bytes) {
        try {
            return MessageDigest.getInstance("SHA-256").digest(bytes == null
                    ? "".getBytes(StandardCharsets.UTF_8) : bytes);
        } catch (NoSuchAlgorithmException e) {
            // Every JVM is required to provide SHA-256.
            throw new IllegalStateException(e);
        }
    }
}
