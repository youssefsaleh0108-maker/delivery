package com.delivery.product.shoppage;

import java.math.BigDecimal;
import java.util.EnumSet;
import java.util.List;
import java.util.Set;

/**
 * What is on a table's order pad, priced by the server, before anything is spelled.
 *
 * <p>A value in the same spirit as {@link PublicShopPage}, and for the second of the same two
 * reasons: it is read by a stranger, so what may be said about a shop is an explicit list of fields
 * rather than whatever happens to be on an entity. A line is the position it was asked about, a
 * name, and whatever the diner asked for with it — no product id, no store id, no merchant id.
 *
 * <p>The one exception is {@link Send}, and it is an exception with a job: a pad that can be sent
 * carries the request that sends it, ids and all, because a ticket cannot name a dish by where it
 * sat on somebody's screen. It is absent from every pad that cannot be sent, no merchant id is in
 * it, and nothing in it is drawn.
 *
 * <p><strong>There is one figure, and it is the food.</strong> No delivery fee, no minimum, no
 * service charge and no tax: the platform is lending a restaurant an order pad, and the bill is
 * between the diner and the restaurant. A total here is the lines added up and nothing else, which
 * is also why {@link #total} is not a separate number from {@link #subtotal} — there is nothing to
 * put between them, and two names for one figure is how a second one eventually appears.
 *
 * <p><strong>Money here is money, not words.</strong> How a figure is spelled — dollars or lira,
 * Latin or Arabic-Indic digits, which side the sign goes on — is the renderer's business, exactly
 * as it is for the page itself ({@code PublicShopPage}'s note on times and prices). The browser is
 * then handed sentences rather than numbers, which is the strongest form of the rule this whole
 * feature exists for: the page cannot add two figures up, because it is never given two figures.
 */
public record ShopBasket(
        List<Line> lines,
        /** Every line added up. It is the whole of what this order costs. */
        BigDecimal total,
        /**
         * The table this pad belongs to — a number this shop actually has
         * ({@code PublicShopPageService#tableOf}) — or null when the page named none it recognises.
         */
        Integer table,
        /** Everything standing between this pad and a ticket. Empty means nothing is. */
        Set<Problem> problems,
        /**
         * The ticket this pad would become, ready to post, or null when it cannot become one —
         * which is every pad {@link #ok()} is false for. See {@link Send}.
         */
        Send send) {

    public ShopBasket {
        lines = List.copyOf(lines);
        problems = problems.isEmpty() ? Set.of() : Set.copyOf(problems);
    }

    /** A pad with nowhere to go: every refusal, and an empty one. */
    public ShopBasket(List<Line> lines, BigDecimal total, Integer table, Set<Problem> problems) {
        this(lines, total, table, problems, null);
    }

    /** Whether this could be sent to the kitchen as it stands. */
    public boolean ok() {
        return problems.isEmpty();
    }

    /**
     * The order-service request this pad would become — built here, and posted by the browser
     * without being read.
     *
     * <p><strong>Why the server builds the whole body.</strong> A ticket names things this page has
     * never printed and never will: the shop's id and a product id per line. The browser could have
     * been handed those and left to assemble a request around a total — and then the total would be
     * a number in a browser, which is the one thing this whole feature is shaped to prevent. So the
     * server assembles it, the browser relays it, and {@code basket.js} reads no field of it: it
     * exists in that file only as the argument to one {@code JSON.stringify}, which
     * {@code ShopBasketScriptTest} asserts.
     *
     * <p>Present only on a pad that could be sent as it stands. That is what makes the button's
     * state a server decision rather than a guess in a browser — no send, no button — and it is
     * why a pad that is merely empty, or stale, or at a closed kitchen, cannot produce one.
     *
     * <p><strong>A tampered copy buys nothing.</strong> The field names are the order service's own
     * ({@code PlaceTableOrderRequest}), so somebody who edits this in a console is talking to that
     * endpoint on its own terms: the prices come from the catalogue, a total that does not match
     * what the catalogue says is a 409 and no ticket, a shop that is not the products' shop is
     * refused, and the table is checked against the room. What they can do is order food to a table
     * in a restaurant they are not sitting in, which is what the printed card already lets anybody
     * standing near it do, and what the rate limit is for.
     *
     * @param expectedTotal what the diner was shown, so nobody is charged a figure they did not
     *                      see: mismatched is a 409 {@code PRICE_CHANGED} and no ticket
     * @param notes         the diner's line notes gathered into the one field a ticket has, because
     *                      an order line there carries no note of its own
     */
    public record Send(java.util.UUID storeId, int table, List<Item> items,
                       BigDecimal expectedTotal, String notes) {

        public Send {
            items = List.copyOf(items);
        }

        /** One line as the order service names it: the product, and how many. */
        public record Item(java.util.UUID productId, int qty) {
        }
    }

    /**
     * One line of the pad.
     *
     * @param at        where the row sits on the shelf the page drew — the only name a line has
     * @param name      the item's name as it stands now, so a renamed dish is renamed here
     * @param note      what the diner asked for with it — "no onions" — trimmed to
     *                  {@code PublicShopPageService.MAX_LINE_NOTE}; null when they wrote nothing.
     *                  The one piece of free text on this whole surface, which is why it is capped
     *                  here and escaped everywhere it is drawn.
     * @param available false for something the kitchen has run out of; it is kept, said, and
     *                  counted in nothing
     */
    public record Line(int at, String name, String note, int qty, BigDecimal unit,
                       BigDecimal lineTotal, boolean available) {
    }

    /**
     * Why a pad is not a ticket yet.
     *
     * <p>All of them are ordinary — a kitchen closes, a dish runs out, a shop has not turned this
     * on — and all of them are said in words on the page before the diner taps send, rather than
     * after.
     */
    public enum Problem {
        /** Nothing on it. */
        EMPTY,
        /**
         * The shelf has changed since the page this pad was built from was drawn: an item was
         * added, removed, paused or renamed, and the positions no longer name what they named.
         * Refused rather than guessed — see {@code PublicShopPageService#versionOf}.
         */
        STALE,
        /** This shop has not turned table ordering on. */
        NOT_OFFERED,
        /** The page was not opened from a table's code, so there is no ticket to write. */
        NO_TABLE,
        /** The shop is shut. The menu still reads; nothing can be sent to a kitchen that is dark. */
        CLOSED,
        /** Something on the pad has run out. */
        GONE;

        public static Set<Problem> none() {
            return EnumSet.noneOf(Problem.class);
        }
    }
}
