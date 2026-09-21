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
        // Nothing arrives hidden except the two controls the script owns: the search field and
        // the line it shows when a search finds nothing. Not one item, and not one aisle.
        assertThat(occurrences(html, "hidden")).isEqualTo(2);
        assertThat(html)
                .contains("<p class=\"q\" hidden>")
                .contains("<p class=\"qn\" role=\"status\" hidden>");
    }

    @Test
    @DisplayName("the jump links are plain anchors at sections that exist")
    void jumpLinksNeedNoScript() throws Exception {
        String html = render(aisled(), "en");

        assertThat(html)
                .contains("<a href=\"#s1\">Bread</a>")
                .contains("<a href=\"#s2\">Cold drinks</a>")
                .contains("<a href=\"#s3\">Household</a>")
                .contains("<div class=\"sec\" id=\"s1\">")
                .contains("<div class=\"sec\" id=\"s2\">")
                .contains("<div class=\"sec\" id=\"s3\">");
        assertThat(occurrences(html, "<div class=\"sec\"")).isEqualTo(3);
    }

    @Test
    @DisplayName("a shop with one aisle gets no jump links: there is nowhere to jump to")
    void oneSectionNeedsNoJumpLinks() throws Exception {
        String html = render(new ShopPageFixture().section("Bread", Item.of("Kaak", "1.50")), "en");

        assertThat(html).doesNotContain("class=\"jump\"").contains("id=\"s1\"");
    }

    @ParameterizedTest(name = "in {0}")
    @ValueSource(strings = {"en", "ar"})
    @DisplayName("the search box and its empty line ship hidden, in the reader's own language")
    void theSearchBoxArrivesHidden(String language) throws Exception {
        String html = render(aisled(), language);

        assertThat(html)
                .contains("<p class=\"q\" hidden>")
                .contains("<input id=\"q\" type=\"search\" autocomplete=\"off\" "
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
        // A filter for a list that is already on the page. Anything approaching a framework here
        // would be a second download standing between a reader and the shop's opening hours.
        assertThat(result.getResponse().getContentAsByteArray().length).isLessThan(4 * 1024);
    }

    /**
     * The one rule, asserted against the file rather than left in a comment.
     *
     * <p>The script may hide rows the document already has. It may not fetch, and it may not build
     * markup — the moment it did, a reader with no script would be looking at a different page
     * from the one this service promises, and the merchant's own text would be going through a
     * second, unescaped path onto the page.
     */
    @Test
    @DisplayName("the script only hides what is already there: it fetches nothing and writes no markup")
    void theScriptOnlyFilters() throws Exception {
        String js = script();

        assertThat(js)
                .doesNotContain("innerHTML")
                .doesNotContain("outerHTML")
                .doesNotContain("insertAdjacent")
                .doesNotContain("createElement")
                .doesNotContain("document.write")
                .doesNotContain("fetch(")
                .doesNotContain("XMLHttpRequest")
                .doesNotContain("eval(")
                .doesNotContain("localStorage")
                .doesNotContain("cookie");
        // What it does instead: read the rows, and set hidden on them.
        assertThat(js).contains(".hidden =");
    }

    @Test
    @DisplayName("the page and the script agree on the hooks between them")
    void theScriptAndThePageUseTheSameHooks() throws Exception {
        String html = render(aisled(), "en");
        String js = script();

        for (String hook : List.of(".find", ".q", ".qn", ".jump", ".menu .sec", ".items > li",
                ".n")) {
            assertThat(js).as("the script looks for %s", hook).contains("'" + hook + "'");
        }
        assertThat(html)
                .contains("class=\"find\"")
                .contains("class=\"jump\"")
                .contains("class=\"sec\"")
                .contains("class=\"items\"")
                .contains("class=\"n\"");
    }
}
