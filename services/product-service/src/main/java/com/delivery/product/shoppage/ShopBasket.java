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
 * rather than whatever happens to be on an entity. There is no product id here, no store id and no
 * merchant id — a line is the position it was asked about, a name, and whatever the diner asked for
 * with it.
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
        /** The table this pad belongs to, as it was shown; null when the page has no table. */
        String table,
        /** Everything standing between this pad and a ticket. Empty means nothing is. */
        Set<Problem> problems) {

    public ShopBasket {
        lines = List.copyOf(lines);
        problems = problems.isEmpty() ? Set.of() : Set.copyOf(problems);
    }

    /** Whether this could be sent to the kitchen as it stands. */
    public boolean ok() {
        return problems.isEmpty();
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
