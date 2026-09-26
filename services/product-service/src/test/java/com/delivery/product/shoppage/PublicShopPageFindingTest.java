package com.delivery.product.shoppage;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

import com.delivery.product.shoppage.ShopPageFixture.Item;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;

/**
 * Finding one thing in a shop that sells a hundred and twenty of them — with the script, and
 * without it.
 *
 * <p>The rule this whole feature is built on is that the script may only <em>hide</em>. The
 * catalogue is in the first response in full, so the reader on the bad connection this page exists
 * for sees the entire shelf whether {@code shop.js} arrives, arrives late, or never arrives at
 * all. Every assertion here is about the delivered bytes, because that is the only state a reader
 * with no script ever reaches.
 */
@DisplayName("finding something in the shop")
class PublicShopPageFindingTest {

    private static ShopPageFixture aisled() {
        return new ShopPageFixture()
                .section("Bread", Item.of("Kaak", "1.50"), Item.of("Markouk", "2.25"))
                .section("Cold drinks", Item.of("Laban ayran", "0.75"))
                .section("Household", Item.of("Dish soap", "3.00"));
    }

    private static String render(ShopPageFixture shop, String language) throws Exception {
        var result = shop.mvc().perform(get("/s/" + shop.slug()).param("lang", language))
                .andReturn();
        result.getResponse().setCharacterEncoding(StandardCharsets.UTF_8.name());
        return result.getResponse().getContentAsString();
    }

    private static int occurrences(String html, String needle) {
        return html.split(java.util.regex.Pattern.quote(needle), -1).length - 1;
    }

    private static String script() throws Exception {
        var result = new ShopPageFixture().mvc().perform(get("/s/assets/shop.js")).andReturn();
        result.getResponse().setCharacterEncoding(StandardCharsets.UTF_8.name());
        return result.getResponse().getContentAsString();
    }

    // ---------------------------------------------------------------- with no script at all

    @Test
    @DisplayName("the whole shelf is in the first response, with nothing hidden on it")
    void everythingIsInTheMarkup() throws Exception {
        ShopPageFixture shop = new ShopPageFixture();
        List<String> names = new ArrayList<>();
        for (int aisle = 0; aisle < 4; aisle++) {
            List<Item> items = new ArrayList<>();
            for (int i = 0; i < 12; i++) {
                String name = "Aisle " + aisle + " item " + i;
                names.add(name);
                items.add(Item.of(name, "1.25"));
            }
            shop.section("Aisle " + aisle, items.toArray(Item[]::new));
        }
        String html = render(shop, "en");

        for (String name : names) {
            assertThat(html).contains("<span class=\"n\">" + name + "</span>");
        }
        assertThat(occurrences(html, "<span class=\"n\">")).isEqualTo(names.size());
        // A shop that does not take orders from its tables — which is every shop on the platform
        // until one turns it on — has the two hidden controls it has always had, the search field
        // and its "nothing matches" line, and one more: the section that says to order with the
        // staff. That sentence is for a diner who scanned a card, and this shop's page is read by
        // people who scanned nothing, so it arrives hidden and shop.js reveals it on a `?t=`
        // address. No pad, no Add buttons, no strip.
        assertThat(occurrences(html, "hidden")).isEqualTo(3);
        assertThat(html)
                .contains("<p class=\"q\" hidden>")
                .contains("<p class=\"qn\" role=\"status\" hidden>")
                .contains("<section class=\"block order bkoff\" id=\"basket\" hidden data-t=\"t\">")
                .doesNotContain("class=\"bk\"")
                .doesNotContain("class=\"peek\"");
        // The shelf itself: every row is there, visible, priced, whatever happens to the scripts.
        assertThat(occurrences(html, "<li hidden")).isZero();
        assertThat(occurrences(html, "<div class=\"sec\" hidden")).isZero();
    }

    /**
     * The same shop with table ordering on: every control the pad owns arrives hidden.
     *
     * <p>The pad, the strip that leads back to it, the table line, the counter, the note about
     * what the total is — and an Add button on every row that is in stock. All of them are
     * controls a script owns, and a control that does nothing when it is tapped is worse than no
     * control. Not one <em>item</em> is hidden, which is the promise the catalogue has always made.
     */
    @Test
    @DisplayName("with table ordering on, the pad's controls arrive hidden and the shelf does not")
    void theTableOrderingControlsAllShipHidden() throws Exception {
        String html = render(aisled().takesTableOrders(), "en");

        // Four rows in the fixture, all in stock, so four Add buttons; plus the two search
        // controls and the six parts of the pad — the sixth being the list of rounds this table has
        // already sent, which is empty until one has been.
        assertThat(occurrences(html, "hidden")).isEqualTo(2 + 4 + 6);
        assertThat(html)
                .contains("<div class=\"bk\" hidden")
                .contains("<div class=\"bksent\" hidden><h3>Sent from this table</h3>")
                .contains("<a class=\"peek\" href=\"#basket\" hidden>Your order</a>")
                .contains("<button class=\"a\" type=\"button\" hidden>Add</button>");
        assertThat(occurrences(html, "<li hidden")).isZero();
    }

    /**
     * What a diner with no JavaScript is told about the pad.
     *
     * <p>The panel ships hidden and one line ships visible, which is the honest way round: the
     * diner who never gets {@code basket.js} is the one who needs to be told there is a pad they
     * cannot have, and the one who does get it never sees the line because the script hides it.
     * Either way the menu above is complete, which is the promise this page has always made.
     */
    @Test
    @DisplayName("with no script the pad is honestly absent, and the menu is still whole")
    void theBasketSaysSoWhenItCannotWork() throws Exception {
        String html = render(aisled().takesTableOrders(), "en");

        assertThat(html)
                .contains("<p class=\"bkno note\">Ordering from the table needs JavaScript. "
                        + "The menu and the prices above are complete without it.</p>")
                .contains("<div class=\"bk\" hidden")
                // Priced rows, section links and the whole shelf: none of it waits on a script.
                .contains("<span class=\"n\">Kaak</span>")
                .contains("<span class=\"p\">$1.50")
                .contains("<a href=\"#s1\">Bread</a>");
        // And the one control that would send food to a kitchen is dead in the markup, not merely
        // dead once a script has been and gone.
        assertThat(html).contains("<button class=\"cta bkgo\" type=\"button\" disabled "
                + "aria-disabled=\"true\">Send to the kitchen</button>");
    }

    /**
     * The bar, as the reader with no script gets it.
     *
     * <p>Everything the bar does when it is being followed down a menu — the mark on the section
     * being read, the sideways scroll, the arrow keys — is added by {@code shop.js} to markup that
     * already works without it. What is asserted here is the part that must never depend on a
     * script: a navigation landmark of ordinary anchors at sections that exist, arriving visible,
     * in the order the shop filed them.
     */
    @Test
    @DisplayName("the bar is a landmark of plain anchors at sections that exist")
    void theBarNeedsNoScript() throws Exception {
        String html = render(aisled(), "en");

        assertThat(html)
                .contains("<nav class=\"bar\" aria-label=\"Jump to\">"
                        + "<a href=\"#s1\">Bread</a>"
                        + "<a href=\"#s2\">Cold drinks</a>"
                        + "<a href=\"#s3\">Household</a></nav>")
                .contains("<div class=\"sec\" id=\"s1\">")
                .contains("<div class=\"sec\" id=\"s2\">")
                .contains("<div class=\"sec\" id=\"s3\">")
                // Nothing a browser has to be told to do, and nothing to undo if the script never
                // arrives: no handler, no tabindex of ours, no chip marked by the server.
                .doesNotContain("<nav class=\"bar\" hidden")
                .doesNotContain("aria-current")
                .doesNotContain("tabindex")
                .doesNotContain("onclick");
        assertThat(occurrences(html, "<div class=\"sec\"")).isEqualTo(3);
    }

    @ParameterizedTest(name = "in {0}")
    @ValueSource(strings = {"en", "ar"})
    @DisplayName("the bar names itself in the reader's language, and mirrors with the page")
    void theBarIsLabelledInBothLanguages(String language) throws Exception {
        String html = render(aisled(), language);

        // The label is the <nav>'s own, not a line of text taking width from a bar that is short
        // of it. Direction is the document's: one stylesheet, mirrored by dir.
        assertThat(html).contains("<nav class=\"bar\" aria-label=\""
                + ("ar".equals(language) ? "انتقل إلى" : "Jump to") + "\">");
        assertThat(html).contains("dir=\"" + ("ar".equals(language) ? "rtl" : "ltr") + "\"");
    }

    @Test
    @DisplayName("a shop with one aisle gets no bar: there is nowhere to jump to")
    void oneSectionNeedsNoBar() throws Exception {
        String html = render(new ShopPageFixture().section("Bread", Item.of("Kaak", "1.50")), "en");

        assertThat(html).doesNotContain("class=\"bar\"").contains("id=\"s1\"");
    }

    @Test
    @DisplayName("a long menu offers a way back to the top, and a short one does not")
    void aLongMenuCanBeClimbedBackUp() throws Exception {
        ShopPageFixture longMenu = new ShopPageFixture();
        List<Item> items = new ArrayList<>();
        for (int i = 0; i < 13; i++) {
            items.add(Item.of("Thing " + i, "1.25"));
        }
        longMenu.section("Bread", items.toArray(Item[]::new));

        // A plain anchor at the menu's own id, so it works with no script — and it lands on the
        // search box, which is the other thing a reader at the bottom of a long shelf wants.
        assertThat(render(longMenu, "en"))
                .contains("<section class=\"block menu\" id=\"menu\">")
                .contains("<p class=\"top\"><a href=\"#menu\">Back to the top of the menu</a></p>");
        assertThat(render(aisled(), "en")).doesNotContain("class=\"top\"");
    }

    @ParameterizedTest(name = "in {0}")
    @ValueSource(strings = {"en", "ar"})
    @DisplayName("the search box and its empty line ship hidden, in the reader's own language")
    void theSearchBoxArrivesHidden(String language) throws Exception {
        String html = render(aisled(), language);

        assertThat(html)
                .contains("<p class=\"q\" hidden>")
                // dir="auto" so a customer on the Arabic page who types a Latin brand name sees
                // it laid out left to right inside the field they are typing into.
                .contains("<input id=\"q\" type=\"search\" dir=\"auto\" autocomplete=\"off\" "
                        + "enterkeyhint=\"search\">")
                .contains("<p class=\"qn\" role=\"status\" hidden>");
        if ("ar".equals(language)) {
            assertThat(html).contains("ابحث في المتجر").contains("انتقل إلى")
                    .contains("لا يوجد صنف يطابق بحثك.");
        } else {
            assertThat(html).contains("Search this shop").contains("Jump to")
                    .contains("Nothing in this shop matches that.");
        }
    }

    // ---------------------------------------------------------------- the script itself

    @Test
    @DisplayName("the script is served from this origin, cached for a year, and small")
    void theScriptIsAnAssetLikeTheStylesheet() throws Exception {
        var result = new ShopPageFixture().mvc().perform(get("/s/assets/shop.js")).andReturn();

        assertThat(result.getResponse().getStatus()).isEqualTo(200);
        assertThat(result.getResponse().getContentType()).startsWith("text/javascript");
        assertThat(result.getResponse().getHeader("Cache-Control"))
                .contains("max-age=31536000").contains("immutable");
        // A filter and a scroll-spy for a list that is already on the page. It was 4 kB when it
        // only filtered; marking the section being read, scrolling its chip into view and walking
        // the bar with the arrow keys is the other half. Anything approaching a framework here
        // would still be a second download standing between a reader and the shop's opening hours.
        assertThat(result.getResponse().getContentAsByteArray().length).isLessThan(8 * 1024);
    }

    /**
     * The one rule, asserted against the file rather than left in a comment.
     *
     * <p>The script may hide rows the document already has, and mark one of the links it arrived
     * with. It may not fetch, and it may not build markup — the moment it did, a reader with no
     * script would be looking at a different page from the one this service promises, and the
     * merchant's own text would be going through a second, unescaped path onto the page.
     */
    @Test
    @DisplayName("the script only hides and marks what is already there: it fetches nothing and writes no markup")
    void theScriptOnlyFilters() throws Exception {
        String js = script();

        assertThat(js)
                .doesNotContain("innerHTML")
                .doesNotContain("outerHTML")
                .doesNotContain("insertAdjacent")
                .doesNotContain("createElement")
                .doesNotContain("appendChild")
                .doesNotContain("document.write")
                .doesNotContain("fetch(")
                .doesNotContain("XMLHttpRequest")
                .doesNotContain("eval(")
                .doesNotContain("localStorage")
                .doesNotContain("cookie");
        // What it does instead: read the rows and set hidden on them, and put one attribute — the
        // standard one, which the stylesheet draws the mark from — on the chip being read.
        assertThat(js).contains(".hidden =").contains("setAttribute('aria-current', 'true')");
        // The only attribute it is allowed to write. A second setAttribute here would be a value
        // reaching the page by a path that never went through ShopPageHtml.esc.
        assertThat(occurrences(js, "setAttribute(")).isEqualTo(1);
    }

    @Test
    @DisplayName("the page and the script agree on the hooks between them")
    void theScriptAndThePageUseTheSameHooks() throws Exception {
        String html = render(aisled(), "en");
        String js = script();

        for (String hook : List.of(".menu", ".find", ".q", ".qn", ".bar", ".sec", ".items > li",
                ".n", ".d")) {
            assertThat(js).as("the script looks for %s", hook).contains("'" + hook + "'");
        }
        assertThat(html)
                .contains("class=\"find\"")
                .contains("class=\"bar\"")
                .contains("class=\"sec\"")
                .contains("<ul class=\"items")
                .contains("class=\"n\"");
    }

    /**
     * The stylesheet and the markup agree on where a section lands.
     *
     * <p>Two numbers have to match for a tapped chip to leave its heading visible: the height the
     * bar is pinned at, and the room a section leaves above itself. They are one custom property
     * so that they cannot drift, and this reads the served stylesheet to prove it is still so —
     * it is the offset that works with no script at all, and nothing else on the page would fail
     * loudly if it were wrong.
     */
    @Test
    @DisplayName("the bar's height and a section's landing offset are the same one number")
    void theBarAndTheSectionsAgreeOnTheOffset() throws Exception {
        var result = new ShopPageFixture().mvc().perform(get("/s/assets/shop.css")).andReturn();
        result.getResponse().setCharacterEncoding(StandardCharsets.UTF_8.name());
        String css = result.getResponse().getContentAsString();

        assertThat(css)
                .containsPattern("--bar:\\s*\\d+px")
                .contains("min-height: var(--bar)")
                .contains("scroll-margin-top: calc(var(--bar)");
    }
}
