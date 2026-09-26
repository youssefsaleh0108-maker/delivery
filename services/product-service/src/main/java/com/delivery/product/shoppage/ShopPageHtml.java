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

    /** Where the stylesheet lives. */
    static final String STYLESHEET = "/s/assets/shop.css";

    /**
     * The two asset URLs this rendering points at, each with its own content fingerprint.
     *
     * <p>Both files are served {@code immutable} for a year, which is right — they are the same
     * bytes for every shop page a reader ever opens — and which is also why the address has to
     * move when the bytes do. It did not: a reader who opened any shop page in the last year held
     * {@code /s/assets/shop.css} and would have drawn the next release's markup with the last
     * release's stylesheet, with nothing to explain it and no way to reproduce it.
     *
     * <p>A query rather than a new filename, so {@code /s/assets/shop.css} keeps resolving for
     * anything that already links to it — caches key on the whole URL either way.
     */
    record Assets(String stylesheet, String script, String basket) {

        /**
         * For a page that may not link anything: the poster refuses an unknown shop under a
         * policy of {@code default-src 'none'}, so a stylesheet link there would be blocked by
         * the browser and is simply not written.
         */
        static Assets none() {
            return new Assets("", "", "");
        }
    }

    /**
     * The one script, and the one thing it is allowed to do.
     *
     * <p>Same origin, so {@code script-src 'self'} allows it and nothing else. It filters the rows
     * this document already carries and never builds one: the catalogue is in the HTML, so a phone
     * with scripting off, a phone that gave up on this file, a chat app's preview and a crawler all
     * see the whole shelf. The search box it drives starts {@code hidden} in the markup and is
     * revealed by the script, because a box that did nothing when tapped is worse than no box.
     *
     * <p><strong>How the bar decides which aisle a reader is in</strong>, written here because this
     * file is not the one that crosses a 3G network.
     *
     * <p>The obvious rule — the last aisle whose top has passed under the bar — is the one every
     * scroll-spy uses, and it is wrong on a short menu. A page stops scrolling when its foot
     * reaches the screen, so an aisle that is still below the bar at that moment can never be
     * brought up to it: at no scroll position at all does it become the answer. Beirut Grill sells
     * six things in three aisles, which is what a dekkane looks like; scrolled to the end, Mains and
     * Sides filled the screen, Sides had never once been reachable, and the bar said Desserts — a
     * twenty-pixel sliver the reader had all but left behind. A long restaurant menu hides this
     * completely, because there every aisle eventually reaches the top.
     *
     * <p>Special-casing the foot of the document was the tempting fix and is the wrong one: it
     * moves the mark on the last pixel of the scroll and leaves the whole descent before it saying
     * the same wrong thing. So the question changed instead, from "what have I passed" to "what am
     * I looking at": the aisle covering most of the screen. That has no end to run out of — some
     * aisle always covers the most of it — and it is right by construction rather than by a
     * correction bolted on.
     *
     * <p>Two qualifications, both earned by a case that broke without them. It is the <em>top
     * half</em> of the screen, because measuring to the foot lets an aisle that has only just
     * appeared at the bottom edge take the mark from the one being read. And until the reader has
     * scrolled at all it is simply the first aisle, because nothing has been passed yet and a menu
     * that fits on one screen would otherwise be introduced by whichever aisle happens to be
     * longest. A chip that is tapped marks itself, whatever the screen then looks like: a two-row
     * aisle lands under the bar with a long one beneath it, and the reader has just said in so many
     * words which one they wanted.
     *
     * <p>{@code ShopPageScrollSpyTest} runs the real file over the rectangles this page actually
     * measured, because none of the tests that read the served bytes could see any of it.
     */
    static final String SCRIPT = "/s/assets/shop.js";

    /**
     * The second script, and the reason it is a second one.
     *
     * <p>{@link #SCRIPT} promises, in a comment at the top of the file and in a test that reads the
     * served bytes, that it never fetches and never builds a row the document did not arrive with.
     * The basket does both — it has to: a total is the server's answer, so it is fetched, and a
     * chosen line is not in the markup, so it is built. Putting the two in one file would have
     * meant deleting that promise for the catalogue as well, and the catalogue is the part a reader
     * on a bad connection depends on.
     *
     * <p>So they are two files with two rules. {@code shop.js} still only hides and marks, and
     * {@code PublicShopPageFindingTest} still holds it to that. {@code basket.js} may fetch this
     * origin and may build the basket's own rows — and nothing else: it writes every value it
     * receives with {@code textContent}, never markup, so a shop that calls a product
     * {@code <script>} cannot reach the page through it either.
     */
    static final String BASKET_SCRIPT = "/s/assets/basket.js";

    /**
     * Where a table's order goes, and where the diner reads it back.
     *
     * <p><strong>Paths, not URLs, for the same reason the quote is one</strong> — and here it
     * matters more, because this one is not even this service. The page is served on
     * {@code www.youdrop.shop} and on the API hostname, and its policy is {@code default-src 'none'}
     * with {@code connect-src 'self'}: an absolute address would be cross-origin, and therefore
     * blocked before it left the browser, for every reader who arrived by the other name. So the
     * deployment routes {@code /api/table-orders} on both hostnames — an exact mirror of the shop
     * page's own router, so a page and the endpoint it posts to are always on the same host — and
     * the page prints a path, which is same-origin by construction. See the note above the
     * {@code table-orders} IngressRoute in {@code deploy/k3s/overlays/ingress.template.yaml}.
     *
     * <p>Two of them and not one with a suffix bolted on in the browser: the status link sits under
     * its own {@code status/} segment, which is a security property of that service's permit-all
     * list rather than a spelling, and it is not this page's business to know that.
     */
    static final String SEND_PATH = "/api/table-orders";

    static final String STATUS_PATH = SEND_PATH + "/status/";

    /**
     * The ticket states nothing follows, so the page knows when to stop asking.
     *
     * <p>A copy of {@code OrderStatus.isTerminal()} in another service, and named as one. It is
     * here rather than in {@code basket.js} because a copy that lives in a comment in a JavaScript
     * file is a copy nobody finds: if that lifecycle ever grows a third ending, this line is what
     * has to change, and it is one line in a file with tests around it rather than a condition in a
     * browser.
     *
     * <p>Getting it wrong is cheap in one direction and not the other. A state missing from here
     * means a phone politely asking about a finished order every thirty seconds until the page is
     * closed; a state wrongly in here means a diner watching "being made" for food that is already
     * on the table. Neither touches money, and both are visible.
     */
    static final String TERMINAL_STATES = "DELIVERED|CANCELLED";

    /**
     * Renders one shop.
     *
     * @param base    the public origin the page believes it is on, for the canonical URL, the Open
     *                Graph URL and every link off the page. Configuration, not the request's own
     *                Host header: a page reached on an internal address must still tell a crawler
     *                and a chat app the one address the shop printed on its sign.
     */
    static String render(PublicShopPage page, ShopPageText t, String base, BigDecimal lbpPerUsd,
                         Assets assets) {
        String url = base + "/s/" + page.slug();
        String what = t.vertical(page.vertical(), page.serviceCategory());
        String title = page.neighbourhood() == null || page.neighbourhood().isBlank()
                ? page.name() + " · YouDrop"
                : page.name() + " — " + page.neighbourhood() + " · YouDrop";
        String description = describe(page, t);
        // The derivative, not the original: a chat app has a size budget for the picture it
        // re-encodes, and over it the card comes back blank. See PublicShopPage.coverThumbUrl.
        String picture = page.coverThumbUrl() != null ? page.coverThumbUrl() : page.logoUrl();

        StringBuilder b = new StringBuilder(8192);
        head(b, t, title, description, url, picture, page.name(), page.logoUrl(), assets,
                page.tableOrdering());

        b.append("<body><main class=\"shop\">");
        hero(b, page, t, what, url);
        delivery(b, page, t);
        hours(b, page, t);
        catalogue(b, page, t);
        pad(b, page, t);
        order(b, t, base, url);
        footer(b, page, t, url, lbpPerUsd);
        b.append("</main>");
        // Outside <main>, because it is furniture pinned to the screen rather than part of the
        // document being read — and last, so with no stylesheet at all it is a link at the end
        // rather than one in front of the shop's name.
        basketPeek(b, page, t);
        // After everything a person reads, not in the head. A crawler finds it either way, and up
        // to twenty kilobytes of it between <head> and the shop's name is twenty kilobytes a
        // reader on 3G waits through before anything appears.
        ShopPageJsonLd.append(b, page, t, url, description);
        b.append("</body></html>");
        return b.toString();
    }

    /**
     * The one sentence this shop is described by, wherever a description is asked for.
     *
     * <p>The {@code <meta name="description">}, the Open Graph and Twitter cards, the structured
     * data and the web manifest all take it from here, so a shop cannot be described one way to a
     * search engine and another way on a home screen.
     */
    static String describe(PublicShopPage page, ShopPageText t) {
        if (page.tagline() != null && !page.tagline().isBlank()) {
            return page.tagline();
        }
        return t.metaDescription(page.name(),
                t.vertical(page.vertical(), page.serviceCategory()), page.neighbourhood());
    }

    /**
     * The page a stranger gets for a draft shop, a suspended shop, a shop with no pin and a slug
     * nobody has ever had.
     *
     * <p>One rendering, taking nothing but the language, so the four cannot be told apart by the
     * length of the body, a stray word or an ETag. Marked {@code noindex} as well as answered 404:
     * a crawler that already has the address should drop it rather than keep asking.
     */
    static String renderNotFound(ShopPageText t, String base, Assets assets) {
        StringBuilder b = new StringBuilder(1024);
        b.append("<!doctype html><html lang=\"").append(t.tag())
                .append("\" dir=\"").append(t.dir()).append("\"><head>")
                .append("<meta charset=\"utf-8\">")
                .append("<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">")
                .append("<meta name=\"robots\" content=\"noindex\">")
                .append("<title>").append(esc(t.notFoundTitle())).append(" · YouDrop</title>")
                ;
        if (!assets.stylesheet().isBlank()) {
            b.append("<link rel=\"stylesheet\" href=\"").append(assets.stylesheet()).append("\">");
        }
        b.append("</head><body><main class=\"shop missing\">")
                .append("<h1>").append(esc(t.notFoundTitle())).append("</h1>")
                .append("<p>").append(esc(t.notFoundBody())).append("</p>")
                .append("<p><a class=\"cta\" href=\"").append(esc(base)).append("/\">")
                .append(esc(t.backToSite())).append("</a></p>")
                .append("</main></body></html>");
        return b.toString();
    }

    // ---------------------------------------------------------------- head

    private static void head(StringBuilder b, ShopPageText t, String title, String description,
                             String url, String picture, String name, String logo,
                             Assets assets, boolean pad) {
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
                // So a regular can keep the shop on a home screen under its own name and logo.
                // The language is named explicitly rather than left to Accept-Language: the
                // manifest a reader keeps should be the rendering they were looking at.
                .append("<link rel=\"manifest\" href=\"").append(esc(url))
                .append(ShopPageManifest.PATH).append("?lang=").append(t.tag()).append("\">")
                .append("<meta name=\"theme-color\" content=\"")
                .append(ShopPageManifest.THEME).append("\">");
        if (logo != null) {
            // iOS takes its home-screen icon from here rather than from the manifest.
            b.append("<link rel=\"apple-touch-icon\" href=\"").append(esc(logo)).append("\">");
        }
        b.append("<link rel=\"stylesheet\" href=\"").append(assets.stylesheet()).append("\">")
                // Deferred, so they are fetched alongside the markup and run after it: the shelf is
                // already on the screen before either file arrives, and nothing waits on them.
                .append("<script src=\"").append(assets.script()).append("\" defer></script>");
        if (pad) {
            // Only where there is a pad to run. It is 8.8 kB gzipped and the first thing it does on
            // a page without one is leave, so every shop that has not turned table ordering on was
            // paying for a file that could not do anything — and that is nearly every shop there
            // is. The sentence such a shop owes a scanned card is shop.js’s, above.
            b.append("<script src=\"").append(assets.basket()).append("\" defer></script>");
        }
        b.append("</head>");
    }

    // ---------------------------------------------------------------- sections

    private static void hero(StringBuilder b, PublicShopPage page, ShopPageText t, String what,
                             String url) {
        b.append("<header class=\"hero\">");
        if (page.coverUrl() != null) {
            // Empty alt: the name is the <h1> right beneath it, and a screen reader reading the
            // shop's name twice is worse than a picture it skips.
            b.append("<img class=\"cover\" src=\"").append(esc(page.coverUrl()))
                    .append("\" alt=\"\" fetchpriority=\"high\" decoding=\"async\">");
        }
        b.append("<div class=\"head\">");
        language(b, t, url);
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

        // Open or closed is the question the page is opened to answer, so it is its own line with
        // its own dot rather than the first of six grey chips. When it is closed, the next opening
        // is on the same line: "closed" on its own sends a reader away, and "closed, opens at
        // eight tomorrow" is the sentence that keeps them.
        PublicShopPage.Opening opening = page.opening();
        if (opening.openNow()) {
            b.append("<p class=\"status open\">").append(esc(opening.closesAt() == null
                    ? t.openNow() : t.openUntil(opening.closesAt()))).append("</p>");
        } else {
            b.append("<p class=\"status shut\">").append(esc(t.closedNow()));
            if (opening.next() != null) {
                b.append("<span class=\"next\">").append(esc(nextLine(opening.next(), t)))
                        .append("</span>");
            }
            b.append("</p>");
        }

        // Built aside and appended only if it has anything in it: a brand-new shop has no power
        // declaration, no badge and no rating, and an empty <ul> would leave a gap under its name
        // for three things it has not earned yet.
        StringBuilder badges = new StringBuilder(128);
        if (page.power() != null) {
            badges.append("<li class=\"power ").append(page.power().status().name().toLowerCase())
                    .append("\">").append(esc(t.power(page.power().status())));
            if (page.power().note() != null && !page.power().note().isBlank()) {
                badges.append(" · ").append(esc(page.power().note()));
            }
            badges.append(" · ").append(esc(t.ago(page.power().minutesAgo()))).append("</li>");
        }
        if (page.verifiedLocal()) {
            badges.append("<li class=\"badge\">").append(esc(t.verifiedLocal())).append("</li>");
        }
        if (page.rating() != null && page.ratingCount() > 0) {
            badges.append("<li class=\"rating\">")
                    .append(esc(t.rated(page.rating(), page.ratingCount()))).append("</li>");
        }
        if (badges.length() > 0) {
            b.append("<ul class=\"badges\">").append(badges).append("</ul>");
        }

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

    /**
     * The other language, in the corner of the header rather than at the foot of the page.
     *
     * <p>It was reachable only by knowing to add {@code ?lang=ar} to the address, or by scrolling
     * a hundred and twenty items to find it in the footer. On the one page a shopkeeper hands to
     * anybody, in a country where the two languages are used interchangeably, that is a control
     * that may as well not exist.
     *
     * <p>Its own {@code lang} and {@code dir}, because the label is written in the language it
     * switches <em>to</em>: without them a browser reads "العربية" out in an English voice, and
     * lays it out with the surrounding paragraph's direction rather than its own.
     */
    private static void language(StringBuilder b, ShopPageText t, String url) {
        b.append("<p class=\"lang\"><a rel=\"alternate\" hreflang=\"").append(t.other().tag())
                .append("\" lang=\"").append(t.other().tag())
                .append("\" dir=\"").append(t.other().dir())
                .append("\" href=\"").append(esc(url)).append("?lang=").append(t.other().tag())
                .append("\">").append(esc(t.switchLanguage())).append("</a></p>");
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

    /**
     * How long a menu has to be before it is worth offering a way back up.
     *
     * <p>Twelve rows is roughly two phone screens of shelf. Below that the reader can see where
     * they came from, and a "back to the top" link under a four-item shop is a control apologising
     * for a scroll that never happened.
     */
    private static final int LONG_MENU = 12;

    private static void catalogue(StringBuilder b, PublicShopPage page, ShopPageText t) {
        PublicShopPage.Catalogue catalogue = page.catalogue();
        // Named, because the bar's own "back to the top" link points here: the top of the menu is
        // where the search box lives, so going back up is also how a reader reaches it again.
        b.append("<section class=\"block menu\" id=\"menu\"><h2>").append(esc(t.catalogue()))
                .append("</h2>");
        // A shop that has not listed anything yet used to have this section removed from under it,
        // so its page simply stopped after the opening hours and a reader was left to guess
        // whether the shop sells nothing, whether the page was broken, or whether they had missed
        // something. A shop is at its emptiest on the day it opens, which is the day the page
        // matters most, so it says what is happening and points at the two things that are here.
        if (catalogue.sections().isEmpty()) {
            b.append("<p class=\"empty\">").append(esc(t.nothingListedYet())).append("</p>")
                    .append("<p class=\"note\">").append(esc(t.nothingListedHint()))
                    .append("</p></section>");
            return;
        }
        searchBox(b, t);
        sectionBar(b, catalogue, t);
        int index = 0;
        for (PublicShopPage.Section section : catalogue.sections()) {
            String name = section.name().isEmpty() ? t.otherItems() : section.name();
            // A wrapper with a positional id, so a chip on the bar has something to land on and
            // the filter has one element to hide when a search empties the whole aisle. Positional
            // rather than the section's own row id, which has no business being on this page.
            // "pic" when anything in this aisle has a photo, and the stylesheet then holds the
            // picture's column open for the rows that have none, so the names keep one edge. An
            // aisle nobody photographed gets no class and no empty column to explain.
            b.append("<div class=\"sec\" id=\"s").append(++index).append("\">")
                    .append("<h3>").append(esc(name)).append("</h3><ul class=\"items")
                    .append(pictured(section) ? " pic" : "").append("\">");
            for (PublicShopPage.Item item : section.items()) {
                item(b, item, t, page.tableOrdering());
            }
            b.append("</ul></div>");
        }
        if (catalogue.total() > catalogue.shown()) {
            b.append("<p class=\"note\">")
                    .append(esc(t.andMoreInTheApp(catalogue.total() - catalogue.shown())))
                    .append("</p>");
        }
        if (catalogue.shown() > LONG_MENU) {
            // A plain anchor at the section's own id: the way back up works for the reader with no
            // script exactly as it does for everybody else, and it lands on the search box.
            b.append("<p class=\"top\"><a href=\"#menu\">").append(esc(t.backToTop()))
                    .append("</a></p>");
        }
        b.append("</section>");
    }

    /** Whether anything in this aisle has a photo, which decides the aisle's left edge. */
    private static boolean pictured(PublicShopPage.Section section) {
        for (PublicShopPage.Item item : section.items()) {
            if (item.imageUrl() != null) {
                return true;
            }
        }
        return false;
    }

    /**
     * One line of the menu: the picture, the name, what it costs.
     *
     * <p>The three are laid out by the stylesheet as a grid rather than in the order they are
     * written here, so that the prices form a column a reader can run an eye down. What is written
     * here is reading order — name, then whether it can be had at all, then the price — which is
     * the order a screen reader announces and the order the row falls into when there is no
     * stylesheet at all.
     */
    private static void item(StringBuilder b, PublicShopPage.Item item, ShopPageText t,
                             boolean pad) {
        b.append("<li").append(item.inStock() ? "" : " class=\"gone\"").append(">");
        if (item.imageUrl() != null) {
            // Lazy below the fold: a hundred thumbnails fetched eagerly is the difference between
            // a page that opens on a bus and one that does not. The square it lands in is sized by
            // the stylesheet, so the row is its final height before the picture arrives.
            b.append("<img src=\"").append(esc(item.imageUrl()))
                    .append("\" alt=\"\" loading=\"lazy\" decoding=\"async\">");
        }
        // A row with something to say opens where it stands. <details> is the browser's own
        // disclosure: it expands with no script, no page load and no scroll position lost, it
        // carries its own keyboard and screen-reader behaviour, and the reader with scripting off
        // gets exactly the same row as everybody else. The triangle is the signal — a row without
        // one has nothing more behind it.
        boolean expands = item.about() != null && !item.about().isBlank();
        if (expands) {
            b.append("<details><summary>");
        }
        b.append("<span class=\"n\">").append(esc(item.name())).append("</span>");
        if (expands) {
            b.append("</summary><p class=\"d\">").append(esc(item.about()))
                    .append("</p></details>");
        }
        if (!item.inStock()) {
            b.append("<span class=\"x\">").append(esc(t.outOfStock())).append("</span>");
        }
        // The two currencies as two elements rather than one "$1.50 · 135,000 LBP" string, because
        // the price column on a 320 px screen is about eighty pixels wide and that sentence does
        // not fit in it. The dollar figure is the price; the lira is the same price converted, and
        // it sits under it in smaller type saying so by its position.
        b.append("<span class=\"p\">").append(esc(t.usd(item.priceUsd())));
        if (item.priceLbp() != null) {
            b.append("<span class=\"l\">").append(esc(t.lbp(item.priceLbp()))).append("</span>");
        }
        b.append("</span>");
        if (pad && item.inStock()) {
            // Last, because that is reading order for an action: what it is, then what it costs,
            // then the thing to do about it. Nothing that has run out gets one — a button that
            // added something the kitchen cannot make would be the page making a promise for it —
            // and neither does any row at a shop that has not turned table ordering on, where the
            // menu is a menu and there is nothing anywhere on the page to add to.
            //
            // It ships hidden and is revealed by basket.js, the bargain the search field already
            // makes: on a page opened without a table's code there is no pad to add to, and a
            // control that does nothing when tapped is worse than no control. Its accessible name
            // is set by the script from the row's own name, so the merchant's text is not printed a
            // second time here — a hundred and twenty of those is a kilobyte of repeated prose for
            // a label nobody reads twice, and a second path onto the page for a value that would
            // have to be escaped again.
            b.append("<button class=\"a\" type=\"button\" hidden>").append(esc(t.add()))
                    .append("</button>");
        }
        b.append("</li>");
    }

    /**
     * The search field, which only exists once the script has revealed it.
     *
     * <p>It ships {@code hidden} and is revealed by {@code shop.js}. That is the honest way round:
     * filtering happens entirely in the browser ({@code form-action 'none'}, and there is no search
     * endpoint to submit to), so a box left visible for a reader with no script would be a control
     * that swallows what they type. The "nothing matches" line ships with it, in the markup, in the
     * reader's own language, rather than being a string the script would have to carry twice.
     *
     * <p>It sits above the bar and scrolls away with the page, and that is a decision rather than
     * an accident — see {@link #sectionBar}.
     */
    private static void searchBox(StringBuilder b, ShopPageText t) {
        b.append("<div class=\"find\"><p class=\"q\" hidden><label for=\"q\">")
                .append(esc(t.searchThisShop())).append("</label>")
                // dir="auto" so a customer on the Arabic page who types Latin letters — a brand,
                // a "7up" — sees them laid out left to right inside the field they are in.
                .append("<input id=\"q\" type=\"search\" dir=\"auto\" autocomplete=\"off\" ")
                .append("enterkeyhint=\"search\"></p>")
                .append("<p class=\"qn\" role=\"status\" hidden>").append(esc(t.nothingMatches()))
                .append("</p></div>");
    }

    /**
     * The bar of sections that follows the reader down the menu.
     *
     * <p><strong>Plain anchors, and that is all it is.</strong> Every chip is an {@code <a>} at a
     * section this document already contains, so with no script it is a row of working links that
     * lands the reader below the bar — the offset is {@code scroll-margin-top} in the stylesheet,
     * which the browser applies on its own. What the script adds is the mark on the section being
     * read, the sideways scroll that keeps that chip in view, and arrow keys along the row. None of
     * those is load-bearing: without them the bar still navigates.
     *
     * <p><strong>A landmark, not a paragraph.</strong> It was a {@code <p>} beginning with the
     * words "Jump to"; those words are now the {@code <nav>}'s own label, which is what a screen
     * reader announces and what a keyboard user skips the whole row by. On the screen it buys back
     * the width of a label on a bar that is short of width.
     *
     * <p><strong>Only the bar sticks.</strong> On a 320 px screen the field and the bar together
     * were a hundred pixels of permanent furniture on a 568 px screen — a fifth of it — and they
     * answer different questions: search is used once, at the start, by a reader who already knows
     * what they want, while the bar is used continuously by a reader being shown round. So the
     * field stays at the top of the menu and scrolls away, the bar pins at fifty-four pixels, and
     * the way back to the field is the same way back to the top of the menu.
     *
     * <p>Drawn only for a shop with more than one section, because a bar with one chip on it is a
     * heading that has learnt to follow you.
     */
    private static void sectionBar(StringBuilder b, PublicShopPage.Catalogue catalogue,
                                   ShopPageText t) {
        if (catalogue.sections().size() < 2) {
            return;
        }
        b.append("<nav class=\"bar\" aria-label=\"").append(esc(t.jumpTo())).append("\">");
        int index = 0;
        for (PublicShopPage.Section section : catalogue.sections()) {
            b.append("<a href=\"#s").append(++index).append("\">")
                    .append(esc(section.name().isEmpty() ? t.otherItems() : section.name()))
                    .append("</a>");
        }
        b.append("</nav>");
    }


    /**
     * The order pad: what a diner at a table has chosen, and what the food comes to.
     *
     * <p><strong>Every figure in here arrives from {@code /s/{slug}/quote} already added up and
     * already spelled.</strong> Not one number is sent to the browser — the script is handed
     * sentences, which is why it cannot produce a total of its own even by accident. The one place
     * this page could have misled somebody about money is closed by the shape of the data rather
     * than by a rule somebody has to remember.
     *
     * <p><strong>One figure, and it is the food.</strong> No delivery fee, no minimum, no service
     * charge and no tax: the diner pays the restaurant at the table, and the platform is lending it
     * an order pad rather than selling the meal.
     *
     * <p><strong>Drawn only for a shop that has turned this on.</strong> A shop that has not gets
     * {@link #orderWithTheStaff} instead — a sentence for the diner holding a scanned code, and
     * nothing at all for everybody else. And the pad is revealed only on a page opened from a
     * table's own code: a shop's page travels in WhatsApp, and somebody across the city holding
     * that link is not sitting at one of its tables.
     *
     * <p><strong>It asks for nothing about the diner.</strong> No address — there is nowhere to
     * deliver to — no phone, no account. The one thing anybody types here is a note on a line, for
     * the kitchen.
     *
     * <p>The whole panel ships {@code hidden} and is revealed by {@code basket.js}. A diner with no
     * script gets the line that says so and a menu that is still complete — which is the promise
     * this page has always made and the reason the catalogue is in the first response.
     */
    private static void pad(StringBuilder b, PublicShopPage page, ShopPageText t) {
        if (!page.tableOrdering()) {
            orderWithTheStaff(b, t);
            return;
        }
        b.append("<section class=\"block order\" id=\"basket\"><h2>").append(esc(t.yourOrder()))
                .append("</h2>");
        b.append(
                // Visible until the script hides it, rather than hidden until the script shows it:
                // the diner who never gets the file is the one who needs to be told.
                "<p class=\"bkno note\">").append(esc(t.padNeedsScript())).append("</p>")
                // A path, not a URL — and that is not a detail. Every other address this page
                // prints is absolute against the configured base, because a canonical link and an
                // og:url must name the one public address whichever router the request arrived on.
                // This one must do the opposite: the page is served on www.youdrop.shop and on the
                // API host, the policy allows connect-src 'self', and an absolute address would be
                // cross-origin — and therefore blocked — for every reader who reached the page by
                // the other name. A path is same-origin by construction.
                //
                // The language is named on it rather than left to Accept-Language, exactly as the
                // manifest link is and for the same reason: a diner whose phone is set to English
                // reading an Arabic shop's menu in Arabic must not be handed an English total.
                .append("<div class=\"bk\" hidden data-q=\"/s/").append(esc(page.slug()))
                .append("/quote?lang=").append(t.tag())
                .append("\" data-v=\"").append(esc(page.catalogue().version()))
                // The sentences the script needs that are not in any answer: the one for a quote
                // that could not be fetched, and the one for a page opened without a table. Shipped
                // here so they are in the diner's own language without the script carrying a
                // dictionary — the bargain the "nothing matches" line already makes.
                .append("\" data-e=\"").append(esc(t.couldNotPrice()))
                .append("\" data-nt=\"").append(esc(t.scanTheCodeOnYourTable()))
                // Where the order goes, where its ticket is read back, and every word the script
                // needs for what happens after the diner taps: the label on the button while it is
                // in flight, what each state of the ticket means at a table, and a sentence for
                // each way the kitchen can refuse it. All of them here, in the page's own language,
                // for the same reason the two above are — the script carries no dictionary, and a
                // refusal nobody spelled is a refusal the diner is not shown.
                .append("\" data-s=\"").append(SEND_PATH)
                .append("\" data-ss=\"").append(STATUS_PATH)
                .append("\" data-g=\"").append(esc(t.sending()))
                .append("\" data-st=\"").append(esc(t.ticketStates()))
                .append("\" data-r=\"").append(esc(t.sendRefusals()))
                .append("\" data-sd=\"").append(TERMINAL_STATES)
                // The name of the parameter a table's card carries, from the one class that
                // spells it. ShopTableCodes exists because three things had to agree about it and
                // a fourth — the script that reads it back off the address — is now one of them.
                .append("\" data-t=\"").append(esc(ShopTableCodes.PARAM)).append("\">")
                // The table a printed code sent this diner from. Filled by the script from the
                // query string and by nothing else — it is a number in a URL, so it is shown and
                // kept with the pad, and believed about nothing at all. The word is the page's; the
                // code is put after it by the script.
                .append("<p class=\"bktab\" hidden data-l=\"").append(esc(t.tableLabel()))
                .append("\"></p>")
                .append("<p class=\"bkn\" hidden></p>")
                .append("<p class=\"bkempty\">").append(esc(t.emptyPad())).append("</p>")
                // The labels the script puts in front of a line's own name, and the two the note
                // field needs, shipped once here rather than once per line and never built out of
                // anything a merchant typed.
                .append("<ul class=\"bl\" data-more=\"").append(esc(t.addOneMore()))
                .append("\" data-less=\"").append(esc(t.removeOne()))
                .append("\" data-note=\"").append(esc(t.noteOnALine()))
                .append("\" data-eg=\"").append(esc(t.noteExample())).append("\"></ul>")
                .append("<div class=\"bksum\"></div>")
                .append("<p class=\"note bkwhat\" hidden>").append(esc(t.totalIsTheFood()))
                .append("</p>")
                // A live region, because what it says — the kitchen is closed, something has run
                // out, there is no table — appears in answer to something the diner just tapped.
                .append("<p class=\"bksays\" role=\"status\"></p>")
                // Disabled in the markup, so it is disabled for the half-second before the script
                // runs and for ever if it does not. aria-disabled as well: a disabled button is
                // skipped by some screen readers entirely, and this one has something to say.
                //
                // What takes the disabled off is the quote: an answer carrying `send` is the server
                // saying this pad could become a ticket, and nothing else in the browser decides
                // it. A pad that cannot be sent keeps a dead button AND the sentence above it
                // saying why — the two are the same answer, and neither ships without the other.
                .append("<p><button class=\"cta bkgo\" type=\"button\" disabled aria-disabled=\"true\">")
                .append(esc(t.sendToKitchen())).append("</button></p>")
                // What this phone has already sent from this table, under the pad that will send
                // the next round. Built by the script out of the answers it was given and kept in
                // this browser, because there is no account to hang an order history on — and
                // announced politely, so a diner whose order moves from "being made" to "ready"
                // hears it without having to stare at the screen.
                .append("<div class=\"bksent\" hidden><h3>").append(esc(t.alreadySent()))
                .append("</h3><ol class=\"bkgot\" aria-live=\"polite\"></ol></div>")
                .append("</div></section>");
    }

    /**
     * What a shop that has not turned table ordering on says to a diner who scanned one of its
     * cards — and says to nobody else.
     *
     * <p><strong>Hidden, and revealed by {@code shop.js} on an address carrying a table code.</strong>
     * That is not a style choice; it is the only way this sentence can be true. The document is one
     * document per shop and language, memoised, and {@code ?t=} deliberately never reaches it
     * ({@code PublicShopPageApiTest.aTableCodeNeverReachesTheDocument}), so the server rendering it
     * cannot know whether this reader scanned anything. Written visible — as it was — it told every
     * reader of every shop about a restaurant feature they had not asked about: a pharmacy's page,
     * an electronics shop's, a florist's, on the one page the whole merchant-adoption push asks
     * shops to share. A page opened without a code is the menu, and that is the brief's rule.
     *
     * <p><strong>{@code shop.js} and not {@code basket.js}.</strong> Both files are linked on every
     * shop page as it stands, so this is not about a download — it is about which file owns what.
     * {@code basket.js}'s first act is to leave a page with no panel, and a page with no panel is
     * precisely the page this sentence is for; giving the pad's file a second job that only runs
     * when there is no pad would leave neither file with a rule anybody could state.
     * {@code shop.js} shows, hides and marks what the document arrived with, which is exactly this,
     * and is what it already does for the search field.
     *
     * <p><strong>What it costs.</strong> A diner with no script, at a shop that turned ordering off,
     * scans the card and sees no sentence: the menu, complete and priced, and no explanation of why
     * there is nothing to tap. They ask the staff — which is what the sentence would have told them
     * to do. The reader who loses something is the one this page was always able to serve least, and
     * they lose a sentence rather than the menu.
     *
     * <p>The whole section goes, heading included. A visible "Your order" over a hidden sentence
     * would be worse than either.
     */
    private static void orderWithTheStaff(StringBuilder b, ShopPageText t) {
        b.append("<section class=\"block order bkoff\" id=\"basket\" hidden data-t=\"")
                // The name of the parameter a table's card carries, from the one class that spells
                // it — the same attribute the pad ships, read by the same rule in the same file.
                .append(esc(ShopTableCodes.PARAM)).append("\"><h2>").append(esc(t.yourOrder()))
                .append("</h2>")
                .append("<p class=\"note\">").append(esc(t.orderWithTheStaff())).append("</p>")
                .append("</section>");
    }

    /**
     * The strip at the foot of the screen, so a reader forty rows down a menu knows there is a
     * basket and can reach it.
     *
     * <p>An ordinary anchor at the basket's own id, hidden until there is something in it. On the
     * design this is a sidebar beside the menu; this page is one column 720 px wide on purpose —
     * it is opened on a phone from a chat message — so the same job is done the way the app's own
     * menu screen does it.
     */
    private static void basketPeek(StringBuilder b, PublicShopPage page, ShopPageText t) {
        if (!page.tableOrdering()) {
            // No pad, nothing to lead back to. A shop that does not take orders from its tables
            // gets no strip pinned over its menu.
            return;
        }
        b.append("<a class=\"peek\" href=\"#basket\" hidden>").append(esc(t.viewOrder()))
                .append("</a>");
    }

    /**
     * How to order the rest of the way: the app.
     *
     * <p>What this section is for changed when the basket above it appeared. It no longer says the
     * page takes no orders — it takes one as far as a total — but it is still the only way to
     * finish, so it stays, and the basket's own button says plainly where the web stops.
     */
    private static void order(StringBuilder b, ShopPageText t, String base, String url) {
        b.append("<section class=\"block order\"><h2>").append(esc(t.howToOrder()))
                .append("</h2><p>").append(esc(t.orderInTheApp())).append("</p>")
                // One button, and it says what happens when it is pressed: /app hands back the
                // Android build itself, as a download. A reader on an iPhone should find that out
                // from the label rather than from a file they cannot open.
                .append("<p><a class=\"cta\" href=\"").append(esc(base)).append("/app\">")
                .append(esc(t.getTheApp()))
                .append("<span class=\"sub\">").append(esc(t.androidDownload()))
                .append("</span></a></p>")
                // The room the store links will take, held open and honest about being empty.
                // Not anchors: neither listing exists yet, and a dead link on the one page a
                // shopkeeper prints on a sign is worse than a label that says "not yet".
                .append("<ul class=\"stores\"><li>App Store</li><li>Google Play</li></ul>")
                .append("<p class=\"note\">").append(esc(t.storesSoon())).append("</p>")
                .append("<p><a class=\"qr\" href=\"").append(esc(url)).append("/qr.png\">")
                .append(esc(t.printThisPage())).append("</a></p></section>");
    }

    private static void footer(StringBuilder b, PublicShopPage page, ShopPageText t, String url,
                               BigDecimal lbpPerUsd) {
        b.append("<footer class=\"foot\">");
        if (lbpPerUsd != null && lbpPerUsd.signum() > 0) {
            b.append("<p class=\"note\">").append(esc(t.rateNote(lbpPerUsd))).append("</p>");
        }
        // The language link used to live here and now sits in the header, where it is visible
        // without scrolling a hundred and twenty items past it.
        b.append("<p class=\"note\">").append(esc(page.name())).append(" ")
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
     * The same values again, for the one block on this page that is not markup.
     *
     * <p>{@link #esc} is wrong inside {@code <script type="application/ld+json">} in both
     * directions: {@code &amp;quot;} is six literal characters in a JSON string rather than a
     * quote mark, and a backslash — which HTML does not care about at all — ends the string early
     * and turns the rest of a shop's name into JSON syntax.
     *
     * <p>So this escapes what JSON requires, and then three characters JSON does not.
     * {@code <}, {@code >} and {@code &} are written as their numeric JSON escapes (&#92;u003C
     * and friends) because the block lives inside an HTML document: the parser reads it as raw
     * text until it meets {@code </script>}, and a shop called {@code </script><script>} would
     * otherwise close its own data block and open a real one. Escaped that way the JSON parser
     * still sees the characters
     * the merchant typed, and the HTML parser never sees a tag.
     *
     * <p>The invisible characters are dropped here exactly as they are dropped from the markup —
     * {@link #invisible} is the one list — so a right-to-left override cannot reach a crawler's
     * copy of a shop's name by the door the renderer left open. A control character is not
     * merely unwelcome in JSON: it is invalid, and one would make the whole block unparseable.
     */
    static String json(String raw) {
        if (raw == null) {
            return "";
        }
        StringBuilder out = new StringBuilder(raw.length() + 16);
        for (int i = 0; i < raw.length(); i++) {
            char c = raw.charAt(i);
            switch (c) {
                case '"' -> out.append("\\\"");
                case '\\' -> out.append("\\\\");
                case '<' -> out.append("\\u003C");
                case '>' -> out.append("\\u003E");
                case '&' -> out.append("\\u0026");
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
    static boolean invisible(char c) {
        return c < 0x20 || c == 0x7F
                || c == '\u061C' || c == '\u200E' || c == '\u200F'
                || (c >= '\u202A' && c <= '\u202E')
                || (c >= '\u2066' && c <= '\u2069')
                || c == '\uFEFF';
    }
}
