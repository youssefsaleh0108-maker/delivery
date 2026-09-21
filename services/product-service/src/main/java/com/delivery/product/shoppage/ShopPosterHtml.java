package com.delivery.product.shoppage;

/**
 * The sheet a shop tapes to its own counter, as bytes.
 *
 * <p>Its own file, and deliberately not part of {@link ShopPageHtml}. The page is read on a phone
 * by somebody deciding whether to order; this is read by a printer. They share a QR code and a slug
 * and nothing else — different paper, different rules about what may appear on it, and a change to
 * one must not be able to reach the other.
 *
 * <p><strong>Nothing on it can go out of date.</strong> No prices, no opening hours, no delivery
 * fee, no rating, no power status. A poster is printed once and then lives on a counter for a year;
 * every one of those facts would be wrong within a week and there is no way to correct a sheet of
 * paper. What is left is the three things that survive: the shop's name, the QR code of its page,
 * and that address written out for somebody who would rather type it. The slug behind all three is
 * minted at creation and is not touched by a rename ({@code Store.updateProfile}), so the code and
 * the address stay true for as long as the shop does.
 *
 * <p><strong>Black on white, and no picture but the QR.</strong> The shop's logo is not here: it
 * lives in the object store, so drawing it would mean opening this document's {@code img-src} to
 * another origin, and it would come out of a counter-top inkjet as a grey smudge. One same-origin
 * image means the policy is {@code img-src 'self'} and nothing else, which is stricter than the
 * page's own.
 *
 * <p><strong>Bilingual, always.</strong> The one instruction is printed in Arabic and in English
 * on every copy, whichever language the merchant asked for — a sheet on a counter in Beirut is read
 * by both, and a poster that picked one would be the wrong one for half the people who walk in. The
 * reader's language only decides which of the two lines comes first, and the document's direction.
 */
final class ShopPosterHtml {

    private ShopPosterHtml() {
    }

    /** The shared layout: A5 by default, because the common case is a card beside the till. */
    static final String STYLESHEET = "/s/assets/poster.css";

    /** Laid over the top for the wall-sized copy. Only the paper and the scale differ. */
    static final String STYLESHEET_A4 = "/s/assets/poster-a4.css";

    /** The one line, in the two languages it is always printed in. */
    private static final String ORDER_FROM_US_AR = "اطلب منّا على YouDrop";
    private static final String ORDER_FROM_US_EN = "Order from us on YouDrop";

    /** What a screen reader and a printer with no pictures say instead of the code. */
    private static final String QR_ALT_AR = "رمز QR لصفحة ";
    private static final String QR_ALT_EN = "QR code for ";

    /** The two sheets a counter-top printer actually has. */
    enum Paper {
        A5, A4;

        /**
         * The sheet asked for, A5 when nothing was.
         *
         * <p>A5 is the default because it is the card that stands beside a till; A4 is the copy
         * that goes on a wall or a window, and somebody who wants that asks for it.
         */
        static Paper of(String requested) {
            return requested != null && requested.trim().equalsIgnoreCase("a4") ? A4 : A5;
        }

        String tag() {
            return this == A4 ? "a4" : "a5";
        }
    }

    /**
     * Renders one shop's poster.
     *
     * @param page  the shop, read through the page's own reader so that the poster and the page can
     *              never disagree about which shops exist. Only the name and the slug are drawn.
     * @param paper which sheet, which is the only thing that changes between the two renderings
     * @param base  the public origin, from configuration — the same value the QR code's bytes were
     *              built from, so the printed address and the printed code cannot name different
     *              sites
     */
    static String render(PublicShopPage page, ShopPageText t, Paper paper, String base) {
        String qr = "/s/" + page.slug() + "/qr.png";
        // Without the scheme. Nobody types "https://", and the poster's whole point is the reader
        // who would rather type it than scan it.
        String typed = hostAndPath(base) + "/s/" + page.slug();
        String alt = (t.arabic() ? QR_ALT_AR : QR_ALT_EN) + page.name();

        StringBuilder b = new StringBuilder(1536);
        b.append("<!doctype html><html lang=\"").append(t.tag())
                .append("\" dir=\"").append(t.dir()).append("\"><head>")
                .append("<meta charset=\"utf-8\">")
                .append("<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">")
                // A poster is the shop's page with the useful half removed. Indexing it would put a
                // second, worse result in front of anybody searching for the shop.
                .append("<meta name=\"robots\" content=\"noindex\">")
                .append("<title>").append(ShopPageHtml.esc(page.name())).append(" · YouDrop</title>")
                .append("<link rel=\"stylesheet\" href=\"").append(STYLESHEET).append("\">");
        if (paper == Paper.A4) {
            // Laid over the base rather than replacing it: one @page rule wins, everything else is
            // the same sheet scaled up.
            b.append("<link rel=\"stylesheet\" href=\"").append(STYLESHEET_A4).append("\">");
        }
        b.append("</head><body class=\"poster ").append(paper.tag()).append("\">");

        // Screen only — @media print drops it. The merchant picks the paper here rather than in a
        // printer dialog that cannot resize the artwork.
        b.append("<nav class=\"controls\">")
                .append(link(page.slug(), t, Paper.A5, paper))
                .append(link(page.slug(), t, Paper.A4, paper))
                .append("</nav>");

        b.append("<main class=\"sheet\">")
                .append("<h1 class=\"name\">").append(ShopPageHtml.esc(page.name())).append("</h1>")
                // Width and height so the sheet does not reflow when the image arrives, and so a
                // browser printing with pictures turned off still leaves the square's space.
                .append("<img class=\"qr\" src=\"").append(ShopPageHtml.esc(qr))
                .append("\" alt=\"").append(ShopPageHtml.esc(alt))
                .append("\" width=\"").append(ShopQrCode.SIZE_PX)
                .append("\" height=\"").append(ShopQrCode.SIZE_PX).append("\">");

        // Both lines, every time; the reader's own language first. Each carries its own lang and
        // dir, so the Arabic reads right-to-left inside an English sheet and the English reads
        // left-to-right inside an Arabic one.
        if (t.arabic()) {
            line(b, "ar", "rtl", ORDER_FROM_US_AR);
            line(b, "en", "ltr", ORDER_FROM_US_EN);
        } else {
            line(b, "en", "ltr", ORDER_FROM_US_EN);
            line(b, "ar", "rtl", ORDER_FROM_US_AR);
        }

        // An address is left-to-right in every language: marked so, or an Arabic sheet would print
        // the slug mirrored around the punctuation and it would be typed back wrong.
        b.append("<p class=\"addr\" dir=\"ltr\">").append(ShopPageHtml.esc(typed)).append("</p>")
                .append("</main></body></html>");
        return b.toString();
    }

    private static void line(StringBuilder b, String lang, String dir, String words) {
        b.append("<p class=\"line\" lang=\"").append(lang).append("\" dir=\"").append(dir)
                .append("\">").append(ShopPageHtml.esc(words)).append("</p>");
    }

    /** One paper choice in the on-screen switch; the current one is marked and not a link. */
    private static String link(String slug, ShopPageText t, Paper paper, Paper current) {
        String label = paper == Paper.A4 ? "A4" : "A5";
        if (paper == current) {
            return "<span class=\"on\">" + label + "</span>";
        }
        // The language rides along so that switching paper does not switch the sheet back to
        // whatever the browser happens to prefer.
        return "<a href=\"/s/" + ShopPageHtml.esc(slug) + "/poster?size=" + paper.tag()
                + "&amp;lang=" + t.tag() + "\">" + label + "</a>";
    }

    /**
     * {@code https://www.youdrop.shop} as {@code www.youdrop.shop}.
     *
     * <p>String work rather than {@code URI}, because a base that is not a URL at all must still
     * print something a person can read instead of throwing on the one document that is about
     * printing.
     */
    private static String hostAndPath(String base) {
        String trimmed = base == null ? "" : base.trim();
        int scheme = trimmed.indexOf("://");
        return scheme < 0 ? trimmed : trimmed.substring(scheme + 3);
    }
}
