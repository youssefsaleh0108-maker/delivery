package com.delivery.product.shoppage;

import java.nio.charset.StandardCharsets;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import com.delivery.product.shoppage.ShopPageFixture.Item;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;

/**
 * Saying what a thing actually is, without a page load.
 *
 * <p>"Kaak 1.50" tells a stranger nothing, and the answer cannot be another request: this page is
 * opened once, from a chat message, on a connection that made opening it slow. So a row with
 * something written about it is a {@code <details>} — the browser's own disclosure, which expands
 * with no script, keeps the scroll position, and carries its own keyboard and screen-reader
 * behaviour for free. A reader with JavaScript off gets exactly the same row as everybody else.
 */
@DisplayName("what an item is")
class PublicShopPageItemDetailTest {

    private static String render(ShopPageFixture shop, String language) throws Exception {
        var result = shop.mvc().perform(get("/s/" + shop.slug()).param("lang", language))
                .andReturn();
        result.getResponse().setCharacterEncoding(StandardCharsets.UTF_8.name());
        return result.getResponse().getContentAsString();
    }

    private static String describedItem(String about) throws Exception {
        return render(new ShopPageFixture()
                .section("Bread", Item.of("Kaak", "1.50").describedAs(about)), "en");
    }

    @Test
    @DisplayName("a described row expands where it stands, with no script and no second request")
    void aDescribedRowExpands() throws Exception {
        String html = describedItem("Sesame bread, baked here every morning before six.");

        assertThat(html).contains("<details><summary><span class=\"n\">Kaak</span></summary>"
                + "<p class=\"d\">Sesame bread, baked here every morning before six.</p>"
                + "</details><span class=\"p\">");
        // Nothing a browser would have to be told to do: no handler, no id, no aria wiring.
        assertThat(html).doesNotContain("<details open").doesNotContain("onclick");
    }

    @Test
    @DisplayName("a row with nothing written about it stays one line, and offers no triangle")
    void anUndescribedRowStaysFlat() throws Exception {
        String html = render(new ShopPageFixture()
                .section("Bread", Item.of("Kaak", "1.50"),
                        Item.of("Markouk", "2.25").describedAs("Thin mountain bread.")), "en");

        assertThat(html)
                .contains("<span class=\"n\">Kaak</span><span class=\"p\">")
                .contains("<details><summary><span class=\"n\">Markouk</span></summary>");
        // Exactly one row in the aisle opens: the one with something behind it.
        assertThat(html.split("<details", -1).length - 1).isEqualTo(1);
    }

    @Test
    @DisplayName("a merchant who wrote nothing but spaces has written nothing")
    void blankDescriptionsAreNotADisclosure() throws Exception {
        assertThat(describedItem("   \n  ")).doesNotContain("<details");
    }

    /**
     * The column is {@code text}. A merchant who pastes three paragraphs about one jar of honey is
     * pasting them onto a page a stranger opens on 3G, and a hundred and twenty of those would be
     * the page's whole budget spent on prose nobody scrolled to.
     */
    @Test
    @DisplayName("a very long description is cut to a line or two, on a word, and marked as cut")
    void longDescriptionsAreCutToALineOrTwo() throws Exception {
        String sentence = "Mountain honey from the hives above the village, jarred by hand in "
                + "September and again in May, and it is the only honey we have ever sold here "
                + "since my grandfather opened this shop in 1974.";
        assertThat(sentence.length()).isGreaterThan(PublicShopPageService.MAX_ITEM_DESCRIPTION);

        String html = describedItem(sentence);

        String shown = html.substring(html.indexOf("<p class=\"d\">") + 13);
        shown = shown.substring(0, shown.indexOf("</p>"));
        assertThat(shown).endsWith("…")
                .doesNotEndWith(" …")
                .hasSizeLessThanOrEqualTo(PublicShopPageService.MAX_ITEM_DESCRIPTION + 1);
        // Cut on a word: the last thing shown is a whole one.
        assertThat(sentence).startsWith(shown.substring(0, shown.length() - 1));
        assertThat(sentence.charAt(shown.length() - 1)).isEqualTo(' ');
    }

    @Test
    @DisplayName("one unbroken word is cut at the limit, because there is nowhere else to cut it")
    void oneEnormousWordIsStillBounded() throws Exception {
        String html = describedItem("x".repeat(400));

        String shown = html.substring(html.indexOf("<p class=\"d\">") + 13);
        shown = shown.substring(0, shown.indexOf("</p>"));
        assertThat(shown).isEqualTo("x".repeat(PublicShopPageService.MAX_ITEM_DESCRIPTION)
                + "…");
    }

    @Test
    @DisplayName("Arabic gets the same row, and the page's own direction carries it")
    void arabicDescriptionsRenderTheSameWay() throws Exception {
        String html = render(new ShopPageFixture()
                .section("خبز", Item.of("كعك", "1.50").describedAs("كعك بالسمسم، يُخبز كل صباح.")),
                "ar");

        assertThat(html)
                .contains("dir=\"rtl\"")
                .contains("<details><summary><span class=\"n\">كعك</span></summary>"
                        + "<p class=\"d\">كعك بالسمسم، يُخبز كل صباح.</p></details>");
    }
}
