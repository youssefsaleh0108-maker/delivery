package com.delivery.product.shoppage;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.List;

/**
 * A priced order pad as the one thing the page's script is allowed to be handed: words.
 *
 * <p>Every figure in this document has already been added up and already been spelled — in the
 * diner's own language, with Arabic-Indic digits where the page uses them, through the same
 * {@link ShopPageText} that spells the prices in the markup. <strong>There is not a number in it
 * that could be added to another.</strong> That is the point: a total is the server's answer or it
 * is nothing, and the surest way to keep a browser from computing one is to make sure it never
 * holds the parts.
 *
 * <p>Built with a {@code StringBuilder} and {@link ShopPageHtml#json}, like the structured data at
 * the foot of the page and for the same reason: this package has one escaper per context and no
 * template engine, and a shop is allowed to call a dish {@code </script>}. {@code json} escapes
 * what JSON requires and then {@code <}, {@code >} and {@code &} as well, and drops the invisible
 * characters — the bidi overrides above all, which a merchant could otherwise use to turn a price
 * round in a line exactly as they could in the markup.
 *
 * <p>The same escaper covers the one thing here a <em>diner</em> typed — the note on a line — which
 * is the only free text on this surface and comes from somebody nobody has identified.
 *
 * <p>Nothing it <em>draws</em> names a product, a section or a shop beyond what the page already
 * prints: a line is the position it was asked about, the name the page already shows, and what was
 * asked for with it. The one thing here that carries ids is {@code send}, which is the order
 * service's own request for a pad that could be sent — relayed by the browser, drawn by nothing,
 * and absent from every pad that could not. See {@link ShopBasket.Send} for why it is built here.
 */
final class ShopBasketJson {

    private ShopBasketJson() {
    }

    /**
     * @param lbpPerUsd the platform's display rate, so a pad is quoted in the two currencies the
     *                  page already quotes every price in; null or zero means lira are not shown at
     *                  all, exactly as it does everywhere else
     */
    static String render(ShopBasket basket, ShopPageText t, BigDecimal lbpPerUsd) {
        StringBuilder b = new StringBuilder(512);
        b.append("{\"ok\":").append(basket.ok());
        // Named rather than inferred from an empty line list, because the two mean different
        // things to the browser: a pad the shelf has moved under is emptied, and one that is merely
        // waiting for the kitchen to open is kept exactly as the diner left it.
        if (basket.problems().contains(ShopBasket.Problem.STALE)) {
            b.append(",\"stale\":true");
        }
        int things = 0;
        for (ShopBasket.Line line : basket.lines()) {
            things += line.qty();
        }
        // Counted here so the strip at the foot of the screen is handed the sentence rather than
        // the pieces of one — "٣ أصناف" is not "3" with a word after it.
        b.append(",\"count\":\"").append(ShopPageHtml.json(t.itemCount(things))).append('"');

        b.append(",\"lines\":[");
        for (int i = 0; i < basket.lines().size(); i++) {
            ShopBasket.Line line = basket.lines().get(i);
            if (i > 0) {
                b.append(',');
            }
            b.append("{\"at\":").append(line.at())
                    .append(",\"name\":\"").append(ShopPageHtml.json(line.name())).append('"')
                    // A count, spelled: "٢" on the Arabic page and "2" on the English one. The
                    // script prints it and never counts with it.
                    .append(",\"qty\":\"").append(ShopPageHtml.json(t.times(line.qty())))
                    .append('"')
                    .append(",\"price\":\"")
                    .append(ShopPageHtml.json(t.usd(line.lineTotal()))).append('"');
            BigDecimal lira = lbp(line.lineTotal(), lbpPerUsd);
            if (lira != null) {
                b.append(",\"priceLbp\":\"").append(ShopPageHtml.json(t.lbp(lira))).append('"');
            }
            if (line.note() != null) {
                // Echoed back rather than kept in the browser, so what the diner sees on the pad is
                // the note as the server holds it — cut to length and escaped — and not a longer
                // one a phone still had lying about.
                b.append(",\"note\":\"").append(ShopPageHtml.json(line.note())).append('"');
            }
            if (!line.available()) {
                b.append(",\"gone\":\"").append(ShopPageHtml.json(t.outOfStock())).append('"');
            }
            b.append('}');
        }
        b.append(']');

        b.append(",\"total\":\"").append(ShopPageHtml.json(t.usd(basket.total()))).append('"');
        BigDecimal lira = lbp(basket.total(), lbpPerUsd);
        if (lira != null) {
            b.append(",\"totalLbp\":\"").append(ShopPageHtml.json(t.lbp(lira))).append('"');
        }
        // One label, because there is one figure. A delivery receipt has a subtotal, a fee and a
        // total; a table's pad has the food.
        b.append(",\"totalLabel\":\"").append(ShopPageHtml.json(t.totalLine())).append('"');

        if (basket.table() != null) {
            // Spelled, like every other number this page prints: "٧" on the Arabic rendering. The
            // script shows it and does nothing else with it.
            b.append(",\"table\":\"")
                    .append(ShopPageHtml.json(t.number(basket.table()))).append('"');
        }

        b.append(",\"says\":[");
        List<String> says = sentences(basket, t);
        for (int i = 0; i < says.size(); i++) {
            if (i > 0) {
                b.append(',');
            }
            b.append('"').append(ShopPageHtml.json(says.get(i))).append('"');
        }
        b.append(']');
        send(b, basket.send());
        b.append('}');
        return b.toString();
    }

    /**
     * The request that sends this pad to the kitchen, for the browser to relay unread.
     *
     * <p><strong>The only part of this document that is not words</strong>, and the only part
     * nothing draws. The field names are the order service's own, so this is its
     * {@code PlaceTableOrderRequest} written out whole: {@code basket.js} posts it as it stands and
     * reads no field of it. Which is how a total can be inside it without being a number in a
     * browser — the page cannot add up something it never looks at, and
     * {@code ShopBasketScriptTest.neverComputesAPrice} holds the file to that.
     *
     * <p>Absent on every pad that cannot be sent, which is what leaves the button dead: see
     * {@link ShopBasket.Send}. An absent {@code notes} is absent rather than null — a ticket with
     * nothing written on it should print nothing, not the word "null".
     */
    private static void send(StringBuilder b, ShopBasket.Send send) {
        if (send == null) {
            return;
        }
        b.append(",\"send\":{\"storeId\":\"").append(send.storeId())
                .append("\",\"table\":").append(send.table())
                .append(",\"items\":[");
        for (int i = 0; i < send.items().size(); i++) {
            ShopBasket.Send.Item item = send.items().get(i);
            if (i > 0) {
                b.append(',');
            }
            b.append("{\"productId\":\"").append(item.productId())
                    .append("\",\"qty\":").append(item.qty()).append('}');
        }
        // The figure the diner was shown, at the scale the platform stores money in. Mismatched
        // against the catalogue when the send lands is a 409 and no ticket.
        b.append("],\"expectedTotal\":").append(send.expectedTotal());
        if (send.notes() != null) {
            // Written by a diner nobody has identified, through the same escaper as everything a
            // merchant typed — and then into the one field a ticket has for it.
            b.append(",\"notes\":\"").append(ShopPageHtml.json(send.notes())).append('"');
        }
        b.append('}');
    }

    /**
     * Everything standing between this pad and a ticket, in words, in the order a diner needs them:
     * what is wrong with the shop, then with the table, then with the food.
     *
     * <p>All of them before the button that sends it, never after.
     */
    private static List<String> sentences(ShopBasket basket, ShopPageText t) {
        List<String> says = new ArrayList<>(2);
        if (basket.problems().contains(ShopBasket.Problem.STALE)) {
            says.add(t.menuChanged());
            // Nothing else is true of a pad that could not be read at all.
            return says;
        }
        if (basket.problems().contains(ShopBasket.Problem.NOT_OFFERED)) {
            says.add(t.orderWithTheStaff());
        } else if (basket.problems().contains(ShopBasket.Problem.NO_TABLE)) {
            says.add(t.scanTheCodeOnYourTable());
        }
        if (basket.problems().contains(ShopBasket.Problem.CLOSED)) {
            says.add(t.kitchenClosed());
        }
        if (basket.problems().contains(ShopBasket.Problem.GONE)) {
            says.add(t.somethingRanOut());
        }
        return says;
    }

    /**
     * A dollar figure as the lira note it would be handed over in.
     *
     * <p>{@link PublicShopPageService#lbpFaceOf(BigDecimal, BigDecimal)} and no rule of its own:
     * the item prices in the markup were converted by that, and a pad that rounded to a different
     * note would total up to something no column of the menu adds to.
     */
    private static BigDecimal lbp(BigDecimal usd, BigDecimal lbpPerUsd) {
        return PublicShopPageService.lbpFaceOf(usd, lbpPerUsd);
    }
}
