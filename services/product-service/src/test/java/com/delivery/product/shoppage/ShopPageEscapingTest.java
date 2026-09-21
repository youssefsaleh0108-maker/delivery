package com.delivery.product.shoppage;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * The one function every merchant-typed value passes through on its way onto a public page.
 *
 * <p>Tested on its own as well as through the rendered page, because it is the single point where
 * this whole surface is safe or is not: the renderer has one escape call per value and no template
 * engine behind it, so a character this function lets through is a character on the page.
 *
 * <p>Every invisible character here is written as an escape rather than pasted in. A source file
 * about right-to-left overrides is the last place to keep one where nobody can see it.
 */
@DisplayName("what a merchant may write onto the page")
class ShopPageEscapingTest {

    @Test
    @DisplayName("the five characters that could write markup become entities")
    void escapesTheMarkupCharacters() {
        assertThat(ShopPageHtml.esc("<b>Tom & \"Jerry's\"</b>"))
                .isEqualTo("&lt;b&gt;Tom &amp; &quot;Jerry&#39;s&quot;&lt;/b&gt;");
        // Both quote marks, because these values land in attributes as well as in text.
        assertThat(ShopPageHtml.esc("\" onerror=\"alert(1)"))
                .isEqualTo("&quot; onerror=&quot;alert(1)");
        assertThat(ShopPageHtml.esc(null)).isEmpty();
    }

    @Test
    @DisplayName("a right-to-left override is dropped, not escaped into one that still works")
    void dropsTheBidiOverrides() {
        String hostile = "Dekkane \u202Ereversed\u202C and \u2066isolated\u2069\u200F";

        String safe = ShopPageHtml.esc(hostile);

        assertThat(safe).isEqualTo("Dekkane reversed and isolated");
        // Escaping would have kept the attack: &#x202E; is still an override when it is drawn.
        assertThat(safe).doesNotContain("202E").doesNotContain("#x20").doesNotContain("&#82");
    }

    @Test
    @DisplayName("control characters go; the three that are whitespace become a space")
    void dropsTheControlCharacters() {
        assertThat(ShopPageHtml.esc("Za\u0000ta\u001Br\u007F")).isEqualTo("Zatar");
        assertThat(ShopPageHtml.esc("Open\tall\nnight\r")).isEqualTo("Open all night ");
        assertThat(ShopPageHtml.esc("\uFEFFManakish")).isEqualTo("Manakish");
    }

    // ---------------------------------------------------------------- the other one

    /**
     * The structured data is not markup, and the markup escaper is wrong for it in both
     * directions: {@code &quot;} is six literal characters inside a JSON string rather than a
     * quote mark, and a backslash — which HTML does not care about at all — ends the string early
     * and turns the rest of a shop's name into JSON syntax.
     */
    @Test
    @DisplayName("the JSON escaper escapes what JSON needs, which is not what HTML needs")
    void escapesForJson() {
        assertThat(ShopPageHtml.json("Tom \"Jerry's\" \\ shop"))
                .isEqualTo("Tom \\\"Jerry's\\\" \\\\ shop");
        assertThat(ShopPageHtml.json(null)).isEmpty();
        // An apostrophe is not special in JSON, and escaping it would put a backslash into the
        // name a search engine reads back.
        assertThat(ShopPageHtml.json("Jerry's")).isEqualTo("Jerry's");
    }

    /**
     * The block lives inside an HTML document, and the HTML parser reads it as raw text until it
     * meets {@code </script>} — whatever the JSON around it says. So a shop is allowed to call
     * itself that, and the three characters that could write a tag are escaped numerically: the
     * JSON parser still sees them, and the HTML parser never does.
     */
    @Test
    @DisplayName("a shop that closes the script tag cannot: the three tag characters are escaped")
    void cannotCloseItsOwnDataBlock() {
        String hostile = "</script><script>alert(1)</script>";

        String safe = ShopPageHtml.json(hostile);

        assertThat(safe).doesNotContain("<").doesNotContain(">").doesNotContain("&")
                .isEqualTo("\\u003C/script\\u003E\\u003Cscript\\u003Ealert(1)"
                        + "\\u003C/script\\u003E");
    }

    @Test
    @DisplayName("the same invisible characters go, because a control character is invalid JSON")
    void dropsTheSameInvisibleCharacters() {
        // Not merely unwelcome: a raw control character makes the whole block unparseable, and an
        // override that survived would reverse the shop's name in a search result.
        assertThat(ShopPageHtml.json("Za\u0000ta\u001Br\u007F")).isEqualTo("Zatar");
        assertThat(ShopPageHtml.json("Dekkane \u202Ereversed\u202C")).isEqualTo("Dekkane reversed");
        assertThat(ShopPageHtml.json("Open\tall\nnight\r")).isEqualTo("Open all night ");
        assertThat(ShopPageHtml.json("دكانة الروشة")).isEqualTo("دكانة الروشة");
    }

    @Test
    @DisplayName("Arabic itself is untouched, including the joiners its spelling needs")
    void leavesRealTextAlone() {
        // The page sets its own direction; an Arabic name needs no control character to read
        // right-to-left, and the zero-width joiners are spelling, not formatting.
        assertThat(ShopPageHtml.esc("دكانة الروشة")).isEqualTo("دكانة الروشة");
        assertThat(ShopPageHtml.esc("مي\u200Cم\u200Dيم"))
                .isEqualTo("مي\u200Cم\u200Dيم");
        assertThat(ShopPageHtml.esc("Kaak · 1.50 $ — 135,000 ل.ل"))
                .isEqualTo("Kaak · 1.50 $ — 135,000 ل.ل");
    }
}
