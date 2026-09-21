package com.delivery.product.shoppage;

import java.math.BigDecimal;
import java.util.List;

/**
 * The page itself, as bytes.
 *
 * <p><strong>Server-rendered, and that is the whole design.</strong> WhatsApp, Instagram and
 * Facebook build a link preview by fetching the URL and reading the markup; none of them runs
 * JavaScript. A shop page that assembled itself in the browser would be a blank card in every chat
 * it was ever pasted into — which is the one place this link is going to live. So the title, the
 * description and the Open Graph tags are in the first response, and the page needs no script at
 * all to be complete.
 *
 * <p>No template engine, for the same reason there is no properties bundle: a {@code StringBuilder}
 * and one escaping function are less machinery than a dependency, and every value that reaches the
 * markup goes through {@link #esc} on the way — a shop names itself, and a shop is allowed to call
 * itself {@code <script>}.
 *
 * <p>No inline {@code <style>} and no inline {@code <script>}: the site's policy is
 * {@code script-src 'self'} with no {@code 'unsafe-inline'} anywhere, so the one stylesheet is
 * fetched from this service ({@code /s/assets/shop.css}) and there is nothing else to fetch. No
 * CDN, no web font — a phone on 3G reading a shop's opening hours should not wait on a typeface.
 */
final class ShopPageHtml {

    private ShopPageHtml() {
    }

    /** Where the stylesheet lives. Content-addressed, so it can be cached for a year. */
    static final String STYLESHEET = "/s/assets/shop.css";

    /**
     * The one script, and the one thing it is allowed to do.
     *
     * <p>Same origin, so {@code script-src 'self'} allows it and nothing else. It filters the rows
     * this document already carries and never builds one: the catalogue is in the HTML, so a phone
     * with scripting off, a phone that gave up on this file, a chat app's preview and a crawler all
     * see the whole shelf. The search box it drives starts {@code hidden} in the markup and is
     * revealed by the script, because a box that did nothing when tapped is worse than no box.
     */
    static final String SCRIPT = "/s/assets/shop.js";

    /**
     * Renders one shop.
     *
     * @param base    the public origin the page believes it is on, for the canonical URL, the Open
     *                Graph URL and every link off the page. Configuration, not the request's own
     *                Host header: a page reached on an internal address must still tell a crawler
     *                and a chat app the one address the shop printed on its sign.
     */
    static String render(PublicShopPage page, ShopPageText t, String base, BigDecimal lbpPerUsd) {
        String url = base + "/s/" + page.slug();
        String what = t.vertical(page.vertical(), page.serviceCategory());
        String title = page.neighbourhood() == null || page.neighbourhood().isBlank()
                ? page.name() + " · YouDrop"
                : page.name() + " — " + page.neighbourhood() + " · YouDrop";
        String description = page.tagline() != null && !page.tagline().isBlank()
                ? page.tagline()
                : t.metaDescription(page.name(), what, page.neighbourhood());
        // The derivative, not the original: a chat app has a size budget for the picture it
        // re-encodes, and over it the card comes back blank. See PublicShopPage.coverThumbUrl.
        String picture = page.coverThumbUrl() != null ? page.coverThumbUrl() : page.logoUrl();

        StringBuilder b = new StringBuilder(8192);
        head(b, t, title, description, url, picture, page.name());

        b.append("<body><main class=\"shop\">");
        hero(b, page, t, what);
        delivery(b, page, t);
        hours(b, page, t);
        catalogue(b, page, t);
        order(b, t, base, url);
        footer(b, page, t, url, lbpPerUsd);
        b.append("</main></body></html>");
        return b.toString();
    }

    /**
     * The page a stranger gets for a draft shop, a suspended shop, a shop with no pin and a slug
     * nobody has ever had.
     *
     * <p>One rendering, taking nothing but the language, so the four cannot be told apart by the
     * length of the body, a stray word or an ETag. Marked {@code noindex} as well as answered 404:
     * a crawler that already has the address should drop it rather than keep asking.
     */
    static String renderNotFound(ShopPageText t, String base) {
        StringBuilder b = new StringBuilder(1024);
        b.append("<!doctype html><html lang=\"").append(t.tag())
                .append("\" dir=\"").append(t.dir()).append("\"><head>")
                .append("<meta charset=\"utf-8\">")
                .append("<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">")
                .append("<meta name=\"robots\" content=\"noindex\">")
                .append("<title>").append(esc(t.notFoundTitle())).append(" · YouDrop</title>")
                .append("<link rel=\"stylesheet\" href=\"").append(STYLESHEET).append("\">")
                .append("</head><body><main class=\"shop missing\">")
                .append("<h1>").append(esc(t.notFoundTitle())).append("</h1>")
                .append("<p>").append(esc(t.notFoundBody())).append("</p>")
                .append("<p><a class=\"cta\" href=\"").append(esc(base)).append("/\">")
                .append(esc(t.backToSite())).append("</a></p>")
                .append("</main></body></html>");
        return b.toString();
    }

    // ---------------------------------------------------------------- head

    private static void head(StringBuilder b, ShopPageText t, String title, String description,
                             String url, String picture, String name) {
        b.append("<!doctype html><html lang=\"").append(t.tag())
                .append("\" dir=\"").append(t.dir()).append("\"><head>")
                .append("<meta charset=\"utf-8\">")
                .append("<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">")
                .append("<title>").append(esc(title)).append("</title>")
                .append("<meta name=\"description\" content=\"").append(esc(description))
                .append("\">")
                // The canonical is the un-suffixed URL in both languages: one page, two renderings,
                // and hreflang below is what tells a search engine which is which. Letting ?lang=ar
                // be its own canonical would split the shop into two competing results.
                .append("<link rel=\"canonical\" href=\"").append(esc(url)).append("\">")
                .append("<link rel=\"alternate\" hreflang=\"en\" href=\"").append(esc(url))
                .append("?lang=en\">")
                .append("<link rel=\"alternate\" hreflang=\"ar\" href=\"").append(esc(url))
                .append("?lang=ar\">")
                .append("<link rel=\"alternate\" hreflang=\"x-default\" href=\"").append(esc(url))
                .append("\">")
                .append("<meta property=\"og:type\" content=\"website\">")
                .append("<meta property=\"og:site_name\" content=\"YouDrop\">")
                .append("<meta property=\"og:locale\" content=\"")
                .append(t.arabic() ? "ar_LB" : "en_US").append("\">")
                .append("<meta property=\"og:title\" content=\"").append(esc(title)).append("\">")
                .append("<meta property=\"og:description\" content=\"").append(esc(description))
                .append("\">")
                .append("<meta property=\"og:url\" content=\"").append(esc(url)).append("\">");
        if (picture != null) {
            b.append("<meta property=\"og:image\" content=\"").append(esc(picture)).append("\">")
                    .append("<meta property=\"og:image:alt\" content=\"").append(esc(name))
                    .append("\">")
                    .append("<meta name=\"twitter:card\" content=\"summary_large_image\">")
                    .append("<meta name=\"twitter:image\" content=\"").append(esc(picture))
                    .append("\">");
        } else {
            // A large-image card with no image is an empty grey box in every client that draws it.
            b.append("<meta name=\"twitter:card\" content=\"summary\">");
        }
        b.append("<meta name=\"twitter:title\" content=\"").append(esc(title)).append("\">")
                .append("<meta name=\"twitter:description\" content=\"").append(esc(description))
                .append("\">")
                .append("<link rel=\"stylesheet\" href=\"").append(STYLESHEET).append("\">")
                // Deferred, so it is fetched alongside the markup and runs after it: the shelf is
                // already on the screen before this file arrives, and nothing waits on it.
                .append("<script src=\"").append(SCRIPT).append("\" defer></script>")
                .append("</head>");
    }

    // ---------------------------------------------------------------- sections

    private static void hero(StringBuilder b, PublicShopPage page, ShopPageText t, String what) {
        b.append("<header class=\"hero\">");
        if (page.coverUrl() != null) {
            // Empty alt: the name is the <h1> right beneath it, and a screen reader reading the
            // shop's name twice is worse than a picture it skips.
            b.append("<img class=\"cover\" src=\"").append(esc(page.coverUrl()))
                    .append("\" alt=\"\" fetchpriority=\"high\" decoding=\"async\">");
        }
        b.append("<div class=\"head\">");
        if (page.logoUrl() != null) {
            b.append("<img class=\"logo\" src=\"").append(esc(page.logoUrl()))
                    .append("\" alt=\"\" decoding=\"async\">");
        }
        b.append("<h1>").append(esc(page.name())).append("</h1>");

        b.append("<p class=\"what\">").append(esc(what));
        if (page.neighbourhood() != null && !page.neighbourhood().isBlank()) {
            b.append(" · ").append(esc(page.neighbourhood()));
        }
        b.append("</p>");

        b.append("<ul class=\"badges\">");
        PublicShopPage.Opening opening = page.opening();
        if (opening.openNow()) {
            b.append("<li class=\"open\">").append(esc(opening.closesAt() == null
                    ? t.openNow() : t.openUntil(opening.closesAt()))).append("</li>");
        } else {
            b.append("<li class=\"shut\">").append(esc(t.closedNow())).append("</li>");
            if (opening.next() != null) {
                b.append("<li class=\"next\">").append(esc(nextLine(opening.next(), t)))
                        .append("</li>");
            }
        }
        if (page.power() != null) {
            b.append("<li class=\"power ").append(page.power().status().name().toLowerCase())
                    .append("\">").append(esc(t.power(page.power().status())));
            if (page.power().note() != null && !page.power().note().isBlank()) {
                b.append(" · ").append(esc(page.power().note()));
            }
            b.append(" · ").append(esc(t.ago(page.power().minutesAgo()))).append("</li>");
        }
        if (page.verifiedLocal()) {
            b.append("<li class=\"badge\">").append(esc(t.verifiedLocal())).append("</li>");
        }
        if (page.rating() != null && page.ratingCount() > 0) {
            b.append("<li class=\"rating\">")
                    .append(esc(t.rated(page.rating(), page.ratingCount()))).append("</li>");
        }
        b.append("</ul>");

        if (page.tagline() != null && !page.tagline().isBlank()) {
            b.append("<p class=\"tagline\">").append(esc(page.tagline())).append("</p>");
        }
        if (page.description() != null && !page.description().isBlank()) {
            b.append("<p class=\"about\">").append(esc(page.description())).append("</p>");
        }
        if (!page.tags().isEmpty()) {
            b.append("<ul class=\"tags\">");
            for (String tag : page.tags()) {
                b.append("<li>").append(esc(tag)).append("</li>");
            }
            b.append("</ul>");
        }
        b.append("</div></header>");
    }

    private static String nextLine(PublicShopPage.Next next, ShopPageText t) {
        return switch (next.daysAhead()) {
            case 0 -> t.opensToday(next.opensAt());
            case 1 -> t.opensTomorrow(next.opensAt());
            default -> t.opensOn(next.isoDay(), next.opensAt());
        };
    }

    private static void delivery(StringBuilder b, PublicShopPage page, ShopPageText t) {
        PublicShopPage.Delivery d = page.delivery();
        b.append("<section class=\"block delivery\"><h2>").append(esc(t.delivery()))
                .append("</h2><ul class=\"facts\">");
        if (d.radiusMetres() != null) {
            b.append("<li>").append(esc(t.deliversWithin(d.radiusMetres()))).append("</li>");
        }
        b.append("<li>").append(esc(t.minutesRange(d.etaMinMinutes(), d.etaMaxMinutes())))
                .append("</li>");
        b.append("<li>").append(esc(d.fee().signum() == 0
                ? t.freeDelivery()
                : t.deliveryFee(d.fee(), d.feeLbp()))).append("</li>");
        b.append("<li>").append(esc(d.minOrder().signum() == 0
                ? t.noMinimum()
                : t.minimumOrder(d.minOrder(), d.minOrderLbp()))).append("</li>");
        b.append("</ul>");
        if (!d.areas().isEmpty()) {
            b.append("<h3>").append(esc(t.areasServed())).append("</h3><ul class=\"areas\">");
            for (String area : d.areas()) {
                b.append("<li>").append(esc(area)).append("</li>");
            }
            b.append("</ul>");
        }
        b.append("</section>");
    }

    private static void hours(StringBuilder b, PublicShopPage page, ShopPageText t) {
        PublicShopPage.Opening opening = page.opening();
        b.append("<section class=\"block hours\"><h2>").append(esc(t.openingHours()))
                .append("</h2><table><tbody>");
        for (PublicShopPage.Day day : opening.week()) {
            boolean isToday = day.isoDay() == opening.todayIso();
            b.append("<tr").append(isToday ? " class=\"today\"" : "").append("><th scope=\"row\">")
                    .append(esc(t.day(day.isoDay())));
            if (isToday) {
                b.append(" <span class=\"now\">").append(esc(t.today())).append("</span>");
            }
            b.append("</th><td>");
            if (day.windows().isEmpty()) {
                b.append(esc(t.closedAllDay()));
            } else {
                List<PublicShopPage.Window> windows = day.windows();
                for (int i = 0; i < windows.size(); i++) {
                    if (i > 0) {
                        b.append(", ");
                    }
                    // Both times are wrapped so the digits stay in reading order beside Arabic
                    // text: a bare "08:00-13:00" in an RTL paragraph is reordered by the browser
                    // into "13:00-08:00" on the screen, which is a different pair of hours.
                    b.append("<span dir=\"ltr\">").append(esc(t.time(windows.get(i).opensAt())))
                            .append("–").append(esc(t.time(windows.get(i).closesAt())))
                            .append("</span>");
                }
            }
            b.append("</td></tr>");
        }
        b.append("</tbody></table><p class=\"note\">")
                .append(esc(t.timesIn(opening.timezone()))).append("</p></section>");
    }

    private static void catalogue(StringBuilder b, PublicShopPage page, ShopPageText t) {
        PublicShopPage.Catalogue catalogue = page.catalogue();
        if (catalogue.sections().isEmpty()) {
            return;
        }
        b.append("<section class=\"block menu\"><h2>").append(esc(t.catalogue())).append("</h2>");
        finder(b, catalogue, t);
        int index = 0;
        for (PublicShopPage.Section section : catalogue.sections()) {
            String name = section.name().isEmpty() ? t.otherItems() : section.name();
            // A wrapper with a positional id, so a jump link has something to land on and the
            // filter has one element to hide when a search empties the whole aisle. Positional
            // rather than the section's own row id, which has no business being on this page.
            b.append("<div class=\"sec\" id=\"s").append(++index).append("\">")
                    .append("<h3>").append(esc(name)).append("</h3><ul class=\"items\">");
            for (PublicShopPage.Item item : section.items()) {
                b.append("<li").append(item.inStock() ? "" : " class=\"gone\"").append(">");
                if (item.imageUrl() != null) {
                    // Lazy below the fold: a hundred thumbnails fetched eagerly is the difference
                    // between a page that opens on a bus and one that does not.
                    b.append("<img src=\"").append(esc(item.imageUrl()))
                            .append("\" alt=\"\" loading=\"lazy\" decoding=\"async\">");
                }
                b.append("<span class=\"n\">").append(esc(item.name())).append("</span>")
                        .append("<span class=\"p\">")
                        .append(esc(t.price(item.priceUsd(), item.priceLbp())))
                        .append("</span>");
                if (!item.inStock()) {
                    b.append("<span class=\"x\">").append(esc(t.outOfStock())).append("</span>");
                }
                b.append("</li>");
            }
            b.append("</ul></div>");
        }
        if (catalogue.total() > catalogue.shown()) {
            b.append("<p class=\"note\">")
                    .append(esc(t.andMoreInTheApp(catalogue.total() - catalogue.shown())))
                    .append("</p>");
        }
        b.append("</section>");
    }

    /**
     * How a reader finds one thing in a shop that sells a hundred and twenty.
     *
     * <p>Two halves, and only one of them needs a script.
     *
     * <p>The <strong>jump links</strong> are plain anchors at the sections the document already
     * contains. They work with scripting off, with the script still in flight, and in a reader
     * mode that stripped it — which is the case this page is built for.
     *
     * <p>The <strong>search field</strong> ships {@code hidden} and is revealed by
     * {@code shop.js}. It is the honest way round: filtering happens entirely in the browser
     * ({@code form-action 'none'}, and there is no search endpoint to submit to), so a box left
     * visible for a reader with no script would be a control that swallows what they type. The
     * "nothing matches" line ships with it, in the markup, in the reader's own language, rather
     * than being a string the script would have to carry in two languages.
     */
    private static void finder(StringBuilder b, PublicShopPage.Catalogue catalogue,
                               ShopPageText t) {
        b.append("<div class=\"find\">");
        if (catalogue.sections().size() > 1) {
            b.append("<p class=\"jump\"><span>").append(esc(t.jumpTo())).append("</span>");
            int index = 0;
            for (PublicShopPage.Section section : catalogue.sections()) {
                b.append("<a href=\"#s").append(++index).append("\">")
                        .append(esc(section.name().isEmpty() ? t.otherItems() : section.name()))
                        .append("</a>");
            }
            b.append("</p>");
        }
        b.append("<p class=\"q\" hidden><label for=\"q\">").append(esc(t.searchThisShop()))
                .append("</label>")
                .append("<input id=\"q\" type=\"search\" autocomplete=\"off\" ")
                .append("enterkeyhint=\"search\"></p>")
                .append("<p class=\"qn\" role=\"status\" hidden>").append(esc(t.nothingMatches()))
                .append("</p></div>");
    }

    /**
     * How to order: the app, and nothing that looks like a basket.
     *
     * <p>Deliberately not a checkout and not a form. This page is anonymous, cached and crawled;
     * anything on it that took an address or a phone number would be collecting a stranger's
     * details on a page that cannot authenticate anybody.
     */
    private static void order(StringBuilder b, ShopPageText t, String base, String url) {
        b.append("<section class=\"block order\"><h2>").append(esc(t.howToOrder()))
                .append("</h2><p>").append(esc(t.orderInTheApp())).append("</p>")
                .append("<p><a class=\"cta\" href=\"").append(esc(base)).append("/app\">")
                .append(esc(t.getTheApp())).append("</a></p>")
                .append("<p><a class=\"qr\" href=\"").append(esc(url)).append("/qr.png\">")
                .append(esc(t.printThisPage())).append("</a></p></section>");
    }

    private static void footer(StringBuilder b, PublicShopPage page, ShopPageText t, String url,
                               BigDecimal lbpPerUsd) {
        b.append("<footer class=\"foot\">");
        if (lbpPerUsd != null && lbpPerUsd.signum() > 0) {
            b.append("<p class=\"note\">").append(esc(t.rateNote(lbpPerUsd))).append("</p>");
        }
        b.append("<p><a rel=\"alternate\" hreflang=\"").append(t.other().tag())
                .append("\" href=\"").append(esc(url)).append("?lang=").append(t.other().tag())
                .append("\">").append(esc(t.switchLanguage())).append("</a></p>")
                .append("<p class=\"note\">").append(esc(page.name())).append(" ")
                .append(esc(t.onYouDrop())).append("</p></footer>");
    }

    // ---------------------------------------------------------------- escaping

    /**
     * Everything a shop, a product or an area is allowed to be called.
     *
     * <p>Five characters, including both quote marks, because these values go into attributes as
     * well as into text — {@code og:title} is an attribute, and a shop called {@code " onerror="}
     * would otherwise write its own markup into the head of a page the platform advertises.
     *
     * <p><strong>And the invisible characters are dropped, not escaped.</strong> Escaping keeps
     * them: {@code &#x202E;} is still a right-to-left override when the browser draws it, and the
     * attack it makes possible is not markup at all — a shop that puts one in its name reverses the
     * text after it, so a price, an opening time or the name of another shop can be made to read
     * backwards on a page the platform publishes under its own domain, and in the preview card of
     * every chat it is pasted into. The same goes for a stray {@code \u0000} or
     * {@code \u001B},
     * which nothing on a page means and which only confuse whatever reads it next. So the explicit
     * bidi formatting characters go, the C0 controls and DEL go, and the three that are ordinary
     * whitespace become a space — HTML would have collapsed them anyway.
     *
     * <p>Arabic is untouched by this: an Arabic name renders right-to-left from its own letters and
     * the {@code dir} this page sets, never from a control character in the middle of a value.
     * {@code U+200C} and {@code U+200D}, which Arabic and Persian spelling genuinely use, stay.
     */
    static String esc(String raw) {
        if (raw == null) {
            return "";
        }
        StringBuilder out = new StringBuilder(raw.length() + 16);
        for (int i = 0; i < raw.length(); i++) {
            char c = raw.charAt(i);
            switch (c) {
                case '&' -> out.append("&amp;");
                case '<' -> out.append("&lt;");
                case '>' -> out.append("&gt;");
                case '"' -> out.append("&quot;");
                case '\'' -> out.append("&#39;");
                case '\t', '\n', '\r' -> out.append(' ');
                default -> {
                    if (!invisible(c)) {
                        out.append(c);
                    }
                }
            }
        }
        return out.toString();
    }

    /**
     * Characters a merchant's text is not allowed to carry onto the page.
     *
     * <ul>
     *   <li>The C0 controls and DEL. Tab, newline and carriage return are handled above as the
     *       whitespace they are; the rest are not text.
     *   <li>{@code U+061C}, {@code U+200E}, {@code U+200F} — the bidi marks.
     *   <li>{@code U+202A}–{@code U+202E} — embeddings and overrides, the Trojan Source ones.
     *   <li>{@code U+2066}–{@code U+2069} — the isolates, which do the same thing with a scope.
     *   <li>{@code U+FEFF} — a byte-order mark that wandered into a value, invisible and useless
     *       in the middle of a name.
     * </ul>
     */
    private static boolean invisible(char c) {
        return c < 0x20 || c == 0x7F
                || c == '\u061C' || c == '\u200E' || c == '\u200F'
                || (c >= '\u202A' && c <= '\u202E')
                || (c >= '\u2066' && c <= '\u2069')
                || c == '\uFEFF';
    }
}
