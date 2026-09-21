package com.delivery.product.shoppage;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalTime;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

import com.delivery.product.domain.Store;

/**
 * The same page, said again for a machine: schema.org, as JSON-LD.
 *
 * <p>This is how a shop appears when somebody types its name into Google rather than following a
 * link somebody sent them — a panel with the hours, whether it is open now, and what it sells,
 * instead of a blue link. The Open Graph tags in the head already do the equivalent job for chat
 * apps; nothing on this page did it for a search engine.
 *
 * <p><strong>Nothing here is new information.</strong> Every value is one the reader can already
 * see on the page above it: the name in the {@code <h1>}, the neighbourhood beside it, the hours
 * out of the table, the prices off the shelf, the rating out of the badge. That rule is not a
 * style preference — structured data that claims more than the page shows is what search engines
 * call spam, it is what gets a site's rich results turned off, and on this page it would also be
 * the one place a shop's private details could leak into a public document. There is no telephone
 * number here, no address beyond the district, and no {@code geo}: the shop's pin is the
 * merchant's premises, and a delivery-only shop never asked for walk-ins.
 *
 * <p>Written by hand, next to the markup that draws the same values, for the same reason
 * {@link ShopPageHtml} is: one file where a value and its escaping are visible together. It goes
 * through {@link ShopPageHtml#json}, which is a different function from the one the markup uses
 * and has to be — {@code &amp;quot;} is not a quote mark to a JSON parser.
 *
 * <p>It sits at the end of the body rather than in the head. A crawler finds it either way; a
 * reader on 3G would have waited for up to twenty kilobytes of it before the shop's name arrived.
 */
final class ShopPageJsonLd {

    private ShopPageJsonLd() {
    }

    /** The vocabulary's own day names. Terms, not text, so they stay English in both renderings. */
    private static final List<String> DAYS = List.of(
            "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday");

    /**
     * @param description the same sentence the {@code <meta name="description">} carries, so the
     *                    two cannot describe the shop differently
     */
    static void append(StringBuilder b, PublicShopPage page, ShopPageText t, String url,
                       String description) {
        b.append("<script type=\"application/ld+json\">")
                .append("{\"@context\":\"https://schema.org\",\"@type\":\"").append(type(page))
                .append("\",\"@id\":\"").append(json(url)).append("#shop\"")
                .append(",\"name\":\"").append(json(page.name())).append('"')
                .append(",\"url\":\"").append(json(url)).append('"')
                .append(",\"inLanguage\":\"").append(t.tag()).append('"')
                .append(",\"description\":\"").append(json(description)).append('"');

        if (page.coverUrl() != null) {
            b.append(",\"image\":\"").append(json(page.coverUrl())).append('"');
        }
        if (page.logoUrl() != null) {
            b.append(",\"logo\":\"").append(json(page.logoUrl())).append('"');
        }
        if (!page.tags().isEmpty()) {
            b.append(",\"keywords\":\"").append(json(String.join(", ", page.tags()))).append('"');
        }
        // The district, and only the district. addressCountry is not on the page in so many
        // words, and this block is held to what the page shows rather than to what would help.
        if (page.neighbourhood() != null && !page.neighbourhood().isBlank()) {
            b.append(",\"address\":{\"@type\":\"PostalAddress\",\"addressLocality\":\"")
                    .append(json(page.neighbourhood())).append("\"}");
        }
        areasServed(b, page);
        openingHours(b, page.opening());
        rating(b, page);
        catalogue(b, page, t);
        b.append("}</script>");
    }

    /**
     * What kind of business this is, from the vertical the page already names in its first line.
     *
     * <p>A specific type is worth having where schema.org has one — a {@code Pharmacy} and a
     * {@code Restaurant} are understood very differently from a generic business. Where it does
     * not, {@code LocalBusiness} is the honest answer: schema.org has no printer, no tailor and no
     * tutor, and picking the nearest-looking type would be telling a search engine something
     * about the shop that is not true.
     */
    private static String type(PublicShopPage page) {
        if (page.vertical() == Store.Vertical.SERVICES) {
            return page.serviceCategory() == Store.ServiceCategory.BEAUTY
                    ? "BeautySalon"
                    : "LocalBusiness";
        }
        return switch (page.vertical()) {
            case RESTAURANT -> "Restaurant";
            case COFFEE -> "CafeOrCoffeeShop";
            case GROCERY -> "GroceryStore";
            case CONVENIENCE -> "ConvenienceStore";
            case PHARMACY -> "Pharmacy";
            case ELECTRONICS -> "ElectronicsStore";
            case FLOWERS_GIFTS -> "Florist";
            case SERVICES -> "LocalBusiness";
        };
    }

    /** The areas the delivery block already lists, by name. No polygons and no coordinates. */
    private static void areasServed(StringBuilder b, PublicShopPage page) {
        List<String> areas = page.delivery().areas();
        if (areas.isEmpty()) {
            return;
        }
        b.append(",\"areaServed\":[");
        for (int i = 0; i < areas.size(); i++) {
            b.append(i == 0 ? "" : ",").append("{\"@type\":\"Place\",\"name\":\"")
                    .append(json(areas.get(i))).append("\"}");
        }
        b.append(']');
    }

    /**
     * The week, out of the same table the page draws.
     *
     * <p>Days that share a set of windows are named together in one specification — six days of
     * 08:00–23:00 is one entry rather than six, which is most of this block's size on a shop that
     * keeps the same hours all week. A day the shop never opens is simply absent, which is what
     * the vocabulary means by absent.
     *
     * <p>In Latin digits and 24-hour {@code HH:MM}, whichever language the page is being read in:
     * this is the format the vocabulary defines, not text a person reads. The Arabic rendering
     * shows the reader ٠٨:٠٠ two sections further up, and it is the same hour.
     */
    private static void openingHours(StringBuilder b, PublicShopPage.Opening opening) {
        Map<String, List<Integer>> byWindows = new LinkedHashMap<>();
        for (PublicShopPage.Day day : opening.week()) {
            if (day.windows().isEmpty()) {
                continue;
            }
            StringBuilder signature = new StringBuilder();
            for (PublicShopPage.Window window : day.windows()) {
                signature.append(clock(window.opensAt())).append('-')
                        .append(clock(window.closesAt())).append(' ');
            }
            byWindows.computeIfAbsent(signature.toString(), ignored -> new ArrayList<>())
                    .add(day.isoDay());
        }
        if (byWindows.isEmpty()) {
            return;
        }

        b.append(",\"openingHoursSpecification\":[");
        boolean first = true;
        for (Map.Entry<String, List<Integer>> entry : byWindows.entrySet()) {
            for (String window : entry.getKey().strip().split(" ")) {
                String[] hours = window.split("-");
                b.append(first ? "" : ",")
                        .append("{\"@type\":\"OpeningHoursSpecification\",\"dayOfWeek\":[");
                List<Integer> days = entry.getValue();
                for (int i = 0; i < days.size(); i++) {
                    b.append(i == 0 ? "" : ",").append('"').append(DAYS.get(days.get(i) - 1))
                            .append('"');
                }
                b.append("],\"opens\":\"").append(hours[0])
                        .append("\",\"closes\":\"").append(hours[1]).append("\"}");
                first = false;
            }
        }
        b.append(']');
    }

    private static void rating(StringBuilder b, PublicShopPage page) {
        if (page.rating() == null || page.ratingCount() <= 0) {
            return;
        }
        b.append(",\"aggregateRating\":{\"@type\":\"AggregateRating\",\"ratingValue\":\"")
                .append(page.rating().setScale(1, RoundingMode.HALF_UP).toPlainString())
                .append("\",\"reviewCount\":").append(page.ratingCount())
                .append(",\"bestRating\":\"5\"}");
    }

    /**
     * The shelf, as an offer catalogue: the aisles the page draws, and in each the rows it drew.
     *
     * <p>Name, price and whether it is in stock. Not the picture — a hundred and twenty object-store
     * URLs would be the largest thing on this page for an image a search engine does not use from
     * an offer catalogue — and not the description, which is on the page for a person to open and
     * would double this block for a machine that would not read it.
     *
     * <p>{@code priceRange} is derived from the rows above, so it cannot claim a price the page
     * does not show; and the currency is named as the page names it, dollars with lira beside them
     * when there is a rate to convert at.
     */
    private static void catalogue(StringBuilder b, PublicShopPage page, ShopPageText t) {
        List<PublicShopPage.Section> sections = page.catalogue().sections();
        if (sections.isEmpty()) {
            return;
        }

        BigDecimal cheapest = null;
        BigDecimal dearest = null;
        boolean lira = false;
        for (PublicShopPage.Section section : sections) {
            for (PublicShopPage.Item item : section.items()) {
                cheapest = cheapest == null || item.priceUsd().compareTo(cheapest) < 0
                        ? item.priceUsd() : cheapest;
                dearest = dearest == null || item.priceUsd().compareTo(dearest) > 0
                        ? item.priceUsd() : dearest;
                lira |= item.priceLbp() != null;
            }
        }
        if (cheapest != null) {
            b.append(",\"priceRange\":\"").append(money(cheapest));
            if (dearest.compareTo(cheapest) != 0) {
                b.append('-').append(money(dearest));
            }
            b.append("\",\"currenciesAccepted\":\"").append(lira ? "USD, LBP" : "USD").append('"');
        }

        b.append(",\"hasOfferCatalog\":{\"@type\":\"OfferCatalog\",\"name\":\"")
                .append(json(t.catalogue())).append("\",\"itemListElement\":[");
        for (int s = 0; s < sections.size(); s++) {
            PublicShopPage.Section section = sections.get(s);
            b.append(s == 0 ? "" : ",")
                    .append("{\"@type\":\"OfferCatalog\",\"name\":\"")
                    .append(json(section.name().isEmpty() ? t.otherItems() : section.name()))
                    .append("\",\"itemListElement\":[");
            List<PublicShopPage.Item> items = section.items();
            for (int i = 0; i < items.size(); i++) {
                PublicShopPage.Item item = items.get(i);
                b.append(i == 0 ? "" : ",")
                        .append("{\"@type\":\"Offer\",\"itemOffered\":{\"@type\":\"Product\",")
                        .append("\"name\":\"").append(json(item.name())).append("\"}")
                        .append(",\"price\":\"").append(plain(item.priceUsd()))
                        .append("\",\"priceCurrency\":\"USD\",\"availability\":\"https://")
                        .append(item.inStock() ? "schema.org/InStock" : "schema.org/OutOfStock")
                        .append("\"}");
            }
            b.append("]}");
        }
        b.append("]}");
    }

    /** {@code HH:MM}, the vocabulary's own clock. */
    private static String clock(LocalTime at) {
        return String.format(Locale.ROOT, "%02d:%02d", at.getHour(), at.getMinute());
    }

    /** A price as a machine reads one: Latin digits, two places, no grouping and no symbol. */
    private static String plain(BigDecimal amount) {
        return amount.setScale(2, RoundingMode.HALF_UP).toPlainString();
    }

    /** The two ends of {@code priceRange}, which is free text and conventionally carries a sign. */
    private static String money(BigDecimal amount) {
        return "$" + plain(amount);
    }

    private static String json(String raw) {
        return ShopPageHtml.json(raw);
    }
}
