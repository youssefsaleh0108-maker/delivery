package com.delivery.product.shoppage;

/**
 * What a table's QR code carries: the shop's own page, and which table the phone is sitting at.
 *
 * <p>One class for one sentence, because three things have to agree about it and they are in
 * different places. {@link PublicShopPageController} draws the code from this URL,
 * {@link ShopTableCardsHtml} prints that same address under it for somebody who would rather type
 * it, and the web basket reads the parameter back off the page it lands on. A second spelling in
 * any of the three is a code that scans to a page that does not know which table it came from — and
 * nothing would fail, which is the worst kind of disagreement to have.
 *
 * <p><strong>The parameter is {@code t}, and its value is the table's number as the shop knows
 * it.</strong> Not an opaque token: a merchant whose card got peeled off table 7 has to be able to
 * reprint table 7, a customer who mistyped has to be able to read the number off the card, and a
 * shop that renumbers its room is renumbering the cards it prints, not rotating a set of secrets.
 * There is nothing to protect here — the page is public, and the table number is written on the
 * table.
 *
 * <p>Note what this is <em>not</em>: it is not an order, a session or a claim. Scanning a table's
 * code opens the shop's page with a number in the query string. What the page and the basket do
 * with it is theirs.
 */
final class ShopTableCodes {

    private ShopTableCodes() {
    }

    /**
     * The parameter every table code carries. Agreed with the web ordering work.
     *
     * <p><strong>The table code is not a secret and nothing may ever treat it as one.</strong> It
     * is printed on a card in a public room, it is the number written on the table itself, and
     * anybody who knows a shop's slug can type one. It decides which ticket a kitchen sees and
     * nothing else: never who the diner is, never a price, never a discount, never whether an
     * order may be placed at all. Everything that actually protects the kitchen — the shop's own
     * switch, the table being one the shop has, and the per-table and per-shop rate limits — is
     * decided on the server from the shop's own record, and none of it trusts this value for
     * anything beyond naming a table.
     */
    static final String PARAM = "t";

    /**
     * Whether a {@code ?t=} value looks like one of this shop's printed cards, for counting only.
     *
     * <p>Used by nothing that decides anything. The page renders identically either way — see
     * {@code PublicShopBasketApiTest.aTableCodeNeverReachesTheDocument} — and whether an order may
     * actually be placed at a table is settled on the server against the shop's own record. This
     * answers a narrower question, asked once per page render by {@code MenuViewRecorder}: should
     * this open be counted against the table codes or against every other way in.
     *
     * <p><strong>A value that is not a plain positive number counts as a link, not as a table.</strong>
     * Cards only ever print one ({@link #urlOf}), so {@code ?t=B12} was typed or mangled by
     * somebody rather than scanned off a card, and counting it as a table code would put a figure
     * in front of a merchant that anybody could inflate by editing an address bar. Undercounting
     * in the doubtful direction is the same choice the rest of that screen makes.
     */
    static boolean looksLikeATable(String value) {
        if (value == null || value.isEmpty() || value.length() > 4) {
            return false;
        }
        for (int i = 0; i < value.length(); i++) {
            if (value.charAt(i) < '0' || value.charAt(i) > '9') {
                return false;
            }
        }
        // "0" is not a table anybody prints: ShopTableCodes.urlOf is only ever called for 1..n.
        return !value.equals("0") && value.charAt(0) != '0';
    }

    /**
     * The address of a shop's page for one table.
     *
     * @param base  the public origin, trimmed of its trailing slash by the caller — the same value
     *              the plain page QR is built from, so the two codes on one counter cannot name
     *              different sites
     * @param slug  the shop's slug, which is lower-case letters, digits and hyphens and so needs no
     *              escaping in a path
     * @param table the table's number, already checked against what the shop says it has
     */
    static String urlOf(String base, String slug, int table) {
        return base + "/s/" + slug + "?" + PARAM + "=" + table;
    }

    /**
     * The same address without its scheme, for the line printed under the code.
     *
     * <p>Nobody types "https://", and a card's whole point is the reader who would rather type the
     * address than scan it.
     */
    static String typedOf(String base, String slug, int table) {
        String url = urlOf(base, slug, table);
        int scheme = url.indexOf("://");
        return scheme < 0 ? url : url.substring(scheme + 3);
    }
}
