package com.delivery.product.shoppage;

/**
 * The sheet of numbered cards a shop cuts up and puts on its tables, as bytes.
 *
 * <p>Its own file beside {@link ShopPosterHtml} rather than another paper size on it. A poster is
 * one sheet with the shop's address on it; this is a grid of cards, each carrying a different code,
 * that has to survive being cut up with scissors. They share a printer and nothing else.
 *
 * <p><strong>Nothing on a card can go out of date.</strong> The poster's rule, and here it is
 * sharper: a table card is stuck to a table and looked at by every person who sits there for a
 * year. No prices, no hours, no fee. What is left is the table's number, the code, the shop's name
 * and the address written out for somebody who would rather type it — and the slug behind the last
 * two is minted at creation and survives a rename ({@code Store.updateProfile}).
 *
 * <p><strong>A card is a pure function of (slug, table, language).</strong> That is what makes a
 * reprint of table 7 the card that was printed the first time, down to the byte: {@link #card} is
 * the only thing that writes one, the full sheet and the single reprint both call it, and neither
 * passes it anything that varies with when it was asked for. It is also why the card's QR is the
 * service's own {@code /s/{slug}/qr.png?t=7}, which is itself a pure function of that URL.
 *
 * <p><strong>Bilingual, always</strong>, exactly as the poster is: a card on a table in Beirut is
 * read by both, and one that picked a language would be the wrong one for half the people who sit
 * down. The reader's language decides which line comes first and which way the sheet runs, nothing
 * more.
 */
final class ShopTableCardsHtml {

    private ShopTableCardsHtml() {
    }

    /** The sheet's layout. Same origin, so its own {@code style-src 'self'} allows it. */
    static final String STYLESHEET = "/s/assets/tables.css";

    /** The one instruction, in the two languages every card carries it in. */
    private static final String SCAN_AR = "امسح الرمز لترى القائمة وتطلب";
    private static final String SCAN_EN = "Scan to see the menu and order";

    /** What a screen reader, and a printer with pictures turned off, say instead of the code. */
    private static final String QR_ALT_AR = "رمز QR للطاولة ";
    private static final String QR_ALT_EN = "QR code for table ";

    /** The word above the number on a card, in each language. */
    private static final String TABLE_AR = "طاولة";
    private static final String TABLE_EN = "Table";

    /**
     * Every card the shop has, or one of them.
     *
     * @param page  the shop, read through the page's own reader so that this sheet and the page can
     *              never disagree about which shops exist. Only the name, the slug and the table
     *              count are drawn.
     * @param one   the single table to reprint, or null for the whole sheet. Already checked
     *              against {@code page.tables()} by the caller.
     * @param base  the public origin, from configuration — the same value the codes' bytes are
     *              built from, so a printed address and the code above it cannot name different
     *              sites
     */
    static String render(PublicShopPage page, ShopPageText t, Integer one, String base) {
        int first = one == null ? 1 : one;
        int last = one == null ? page.tables() : one;

        StringBuilder b = new StringBuilder(2048 + (last - first + 1) * 512);
        b.append("<!doctype html><html lang=\"").append(t.tag())
                .append("\" dir=\"").append(t.dir()).append("\"><head>")
                .append("<meta charset=\"utf-8\">")
                .append("<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">")
                // A sheet of table cards is the shop's page with everything useful removed.
                // Indexing it would put a second, worse result in front of anybody searching.
                .append("<meta name=\"robots\" content=\"noindex\">")
                .append("<title>").append(ShopPageHtml.esc(page.name())).append(" · YouDrop</title>")
                .append("<link rel=\"stylesheet\" href=\"").append(STYLESHEET).append("\">")
                .append("</head><body class=\"tables").append(one == null ? "" : " one").append("\">");

        // Screen only — @media print drops it. Reprinting one card is a link rather than a control,
        // so it can be sent to whoever has the printer.
        b.append(controls(page, t, one));

        b.append("<ul class=\"cards\">");
        for (int table = first; table <= last; table++) {
            b.append(card(page, t, table, base));
        }
        b.append("</ul></body></html>");
        return b.toString();
    }

    /**
     * One card.
     *
     * <p>The whole point of this method is that it is the only one: the full sheet and a reprint of
     * a single table produce the same element from the same inputs, so the card that replaces a
     * peeled-off one is the card that peeled off.
     */
    static String card(PublicShopPage page, ShopPageText t, int table, String base) {
        String qr = "/s/" + page.slug() + "/qr.png?" + ShopTableCodes.PARAM + "=" + table;
        String typed = ShopTableCodes.typedOf(base, page.slug(), table);
        String alt = (t.arabic() ? QR_ALT_AR : QR_ALT_EN) + table + " · " + page.name();

        StringBuilder b = new StringBuilder(640);
        b.append("<li class=\"card\">")
                // The number, large, beside the code it belongs to.
                //
                // Not decoration. A waiter carrying a tray reads it across a room to know which
                // card goes on which table; a diner whose code will not scan reads it out to the
                // person who can type the address; and a card that was moved to another table is a
                // wrong order rather than a missing one. So it is the biggest thing on the card,
                // set beside the square rather than under it, and it is Western digits marked
                // left-to-right in both languages — the same digits that are printed in the
                // address below and that the order carries.
                .append("<div class=\"head\">")
                .append("<p class=\"word\">").append(t.arabic() ? TABLE_AR : TABLE_EN).append("</p>")
                .append("<p class=\"no\" dir=\"ltr\">").append(table).append("</p>")
                .append("</div>")
                // Width and height so the sheet does not reflow when the images arrive, and so a
                // browser printing with pictures turned off still leaves each square's space.
                .append("<img class=\"qr\" src=\"").append(ShopPageHtml.esc(qr))
                .append("\" alt=\"").append(ShopPageHtml.esc(alt))
                .append("\" width=\"").append(ShopQrCode.SIZE_PX)
                .append("\" height=\"").append(ShopQrCode.SIZE_PX).append("\">")
                .append("<p class=\"shop\">").append(ShopPageHtml.esc(page.name())).append("</p>");

        // Both lines, every time; the reader's own language first. Each carries its own lang and
        // dir, so the Arabic reads right-to-left on an English sheet and the English reads
        // left-to-right on an Arabic one.
        if (t.arabic()) {
            line(b, "ar", "rtl", SCAN_AR);
            line(b, "en", "ltr", SCAN_EN);
        } else {
            line(b, "en", "ltr", SCAN_EN);
            line(b, "ar", "rtl", SCAN_AR);
        }

        // An address is left-to-right in every language: marked so, or an Arabic card would print
        // the slug and the table number mirrored around the punctuation, and be typed back wrong.
        b.append("<p class=\"addr\" dir=\"ltr\">").append(ShopPageHtml.esc(typed)).append("</p>")
                .append("</li>");
        return b.toString();
    }

    private static void line(StringBuilder b, String lang, String dir, String words) {
        b.append("<p class=\"line\" lang=\"").append(lang).append("\" dir=\"").append(dir)
                .append("\">").append(ShopPageHtml.esc(words)).append("</p>");
    }

    /**
     * The on-screen switch: the whole sheet, then one link per table.
     *
     * <p>A link per table rather than a number to type, because this is opened on the phone that is
     * about to print and a merchant replacing the card on table 7 wants to tap 7. The language
     * rides along so that picking a table does not switch the sheet back to whatever the browser
     * happens to prefer.
     */
    private static String controls(PublicShopPage page, ShopPageText t, Integer one) {
        StringBuilder b = new StringBuilder(64 + page.tables() * 96);
        String base = "/s/" + ShopPageHtml.esc(page.slug()) + "/tables?lang=" + t.tag();
        b.append("<nav class=\"controls\">");
        b.append(one == null
                ? "<span class=\"on\">" + (t.arabic() ? "الكل" : "All") + "</span>"
                : "<a href=\"" + base + "\">" + (t.arabic() ? "الكل" : "All") + "</a>");
        for (int table = 1; table <= page.tables(); table++) {
            b.append(one != null && one == table
                    ? "<span class=\"on\">" + table + "</span>"
                    : "<a href=\"" + base + "&amp;" + ShopTableCodes.PARAM + "=" + table + "\">"
                            + table + "</a>");
        }
        return b.append("</nav>").toString();
    }
}
