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

    /** The parameter every table code carries. Agreed with the web ordering work. */
    static final String PARAM = "t";

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
