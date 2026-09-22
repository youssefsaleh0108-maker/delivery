package com.delivery.product.shoppage;

import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.concurrent.TimeUnit;

import org.junit.jupiter.api.Assumptions;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;

/**
 * The basket's own script: the rules it must keep, and then the thing itself, run.
 *
 * <p>Half of this feature lives in a browser, and none of that half is in any response — what a tap
 * does, what survives a reload, what a second shop's page sees, what the script believes about a
 * number in a URL. So this asserts two different kinds of thing. First, against the served bytes,
 * the two rules the file is built on. Then, by running it under node over a document made of the
 * elements the page really renders, what it actually does.
 *
 * <p>Node runs the second half, because there is no JavaScript engine on this classpath and adding
 * one to a Spring service so that a 9 kB file can be tested would be the larger dependency — the
 * same bargain {@code ShopPageScrollSpyTest} already makes, and {@code PublicShopPageDatabaseTest}
 * makes with PostgreSQL.
 */
@DisplayName("the basket in a browser")
class ShopBasketScriptTest {

    private static final String SCRIPT = "shoppage/basket.js";
    private static final String HARNESS = "shoppage/basket.test.js";

    private static String served() throws Exception {
        var result = new ShopPageFixture().mvc().perform(get("/s/assets/basket.js")).andReturn();
        result.getResponse().setCharacterEncoding(StandardCharsets.UTF_8.name());
        return result.getResponse().getContentAsString();
    }

    private static int occurrences(String text, String needle) {
        return text.split(java.util.regex.Pattern.quote(needle), -1).length - 1;
    }

    /**
     * The file with its prose taken out, so an assertion about what the code does is not answered
     * by a comment describing it. Block comments go whole; line comments are all at the start of a
     * line in this file, and only those are cut, because a regex literal in the code contains a
     * {@code //} of its own.
     */
    private static String code(String js) {
        return js.replaceAll("(?s)/\\*.*?\\*/", "").replaceAll("(?m)^\\s*//.*$", "");
    }

    // ---------------------------------------------------------------- the two rules

    /**
     * The rule the whole feature rests on, asserted against the file rather than left in a comment.
     *
     * <p>A total is the server's answer or it is nothing. The surest way to keep a browser from
     * producing one of its own is to give it nothing to produce it from — the quote carries spelled
     * strings and no numbers — and the second surest is this: the file contains no arithmetic on
     * anything that came back from the server at all.
     *
     * <p>What it does do with numbers is count things: a quantity goes up by one, and a position is
     * an index into a list of rows. Those are the only two, they are both about rows rather than
     * money, and neither ever touches a value the server sent.
     */
    @Test
    @DisplayName("the script works out no price: there is no money arithmetic in it anywhere")
    void neverComputesAPrice() throws Exception {
        String code = code(served());

        // The two operators a price needs. There is no multiplication and no division in this file
        // at all — a line total, a subtotal and a total are all the server's, and there is nothing
        // here to make one out of.
        assertThat(code).doesNotContain(" * ").doesNotContain(" / ").doesNotContain("*=")
                .doesNotContain("/=");
        // Nor anything that turns a figure the server spelled back into a number to work on.
        assertThat(code)
                .doesNotContain("toFixed")
                .doesNotContain("parseFloat")
                .doesNotContain("parseInt")
                .doesNotContain("Math.round")
                .doesNotContain("Number(");
        // What arithmetic there is: one count going up or down by one, and one age in
        // milliseconds. Both are about rows and time; neither has ever seen a price.
        assertThat(occurrences(code, "+=")).isEqualTo(2);
        assertThat(code).contains("lines[i][1] += by").contains("(Date.now() - held.u) > KEEP");
        // And every figure printed is a field of the answer, assigned as it arrived.
        for (String spelled : List.of("line.price", "answer.total", "answer.totalLbp",
                "answer.count")) {
            assertThat(code).as("%s is printed, not computed", spelled).contains(spelled);
        }
    }

    /**
     * The other rule: it writes text, never markup.
     *
     * <p>A shop names its own products and is allowed to call one {@code <script>}. The markup
     * escapes that on the way out of the server ({@code ShopPageHtml.esc}) and the quote escapes it
     * again for JSON ({@code ShopPageHtml.json}); this is the third door, and it is closed by never
     * handing a string to anything that parses markup. Every value that reaches the document goes
     * through {@code textContent} or an attribute assignment.
     */
    @Test
    @DisplayName("the script builds rows but never markup, and fetches only this origin")
    void writesTextAndFetchesOnlyItself() throws Exception {
        String js = served();

        assertThat(js)
                .doesNotContain("innerHTML")
                .doesNotContain("outerHTML")
                .doesNotContain("insertAdjacent")
                .doesNotContain("document.write")
                .doesNotContain("eval(")
                .doesNotContain("new Function")
                // The address it asks is the one the server printed on the panel — a path — so a
                // basket cannot be posted to another origin whatever anything else says.
                .doesNotContain("http://")
                .doesNotContain("https://")
                .contains("panel.getAttribute('data-q')");
        assertThat(js).contains("textContent");
        // One way to make an element, so every node this script puts on the page is built by the
        // one function that only ever sets a class and a piece of text.
        assertThat(occurrences(code(js), "createElement")).isEqualTo(1);
    }

    @Test
    @DisplayName("the script is served from this origin, cached for a year, and small")
    void isAnAssetLikeTheOthers() throws Exception {
        var result = new ShopPageFixture().mvc().perform(get("/s/assets/basket.js")).andReturn();

        assertThat(result.getResponse().getStatus()).isEqualTo(200);
        assertThat(result.getResponse().getContentType()).startsWith("text/javascript");
        assertThat(result.getResponse().getHeader("Cache-Control"))
                .contains("max-age=31536000").contains("immutable");
        // A basket, its receipt and one request. Anything approaching a framework here would be a
        // second download standing between a reader on 3G and a shop's opening hours.
        //
        // 13 kB on disk and about 4.3 kB over the wire, which is the figure that matters and the
        // one PublicShopPageWeightTest counts: the two rules this file is built on are written at
        // the top of it, and prose gzips to almost nothing. shop.js keeps its comments short
        // because a wrong guess there costs a search box; a wrong guess here costs somebody money.
        assertThat(result.getResponse().getContentAsByteArray().length).isLessThan(13 * 1024);
    }

    @Test
    @DisplayName("the page and the basket agree on the hooks between them")
    void thePageAndTheScriptUseTheSameHooks() throws Exception {
        String js = served();
        ShopPageFixture shop = new ShopPageFixture().takesTableOrders()
                .section("Bread", ShopPageFixture.Item.of("Kaak", "1.50"));
        String html = PublicShopBasketApiTest.page(shop, "en");

        for (String hook : List.of(".bk", ".bl", ".bkempty", ".bksum", ".bkwhat", ".bksays",
                ".bkn", ".bkgo", ".bktab", ".bkno", ".peek", ".a",
                ".menu .sec .items > li")) {
            assertThat(js).as("the script looks for %s", hook).contains("'" + hook + "'");
        }
        for (String attribute : List.of("data-q", "data-v", "data-e", "data-nt", "data-l",
                "data-more", "data-less", "data-note", "data-eg")) {
            assertThat(js).as("the script reads %s", attribute).contains("'" + attribute + "'");
            assertThat(html).as("the page writes %s", attribute).contains(attribute + "=\"");
        }
        for (String css : List.of("class=\"bk\"", "class=\"bl\"", "class=\"bkempty\"",
                "class=\"bksum\"", "class=\"bksays\"", "class=\"peek\"", "class=\"a\"")) {
            assertThat(html).as("the page draws %s", css).contains(css);
        }
    }

    // ---------------------------------------------------------------- and then, running it

    private static Path unpack(Path into, String resource) throws IOException {
        Path file = into.resolve(resource.substring(resource.lastIndexOf('/') + 1));
        try (InputStream in = ShopBasketScriptTest.class.getClassLoader()
                .getResourceAsStream(resource)) {
            assertThat(in).as("%s is on the classpath", resource).isNotNull();
            Files.write(file, in.readAllBytes());
        }
        return file;
    }

    private static boolean nodeIsHere() {
        try {
            Process probe = new ProcessBuilder("node", "--version").redirectErrorStream(true)
                    .start();
            return probe.waitFor(20, TimeUnit.SECONDS) && probe.exitValue() == 0;
        } catch (IOException | InterruptedException absent) {
            Thread.currentThread().interrupt();
            return false;
        }
    }

    /**
     * Adding, changing and removing; surviving a reload; two shops staying apart; a table code
     * kept and a nonsense one ignored; and a total that appears only when the server has sent one.
     *
     * <p>All of it against the real file. The cases and what each one asserts are in
     * {@code basket.test.js} beside this class — they are written there rather than here because
     * they are about a document, and a Java test that built one would be a second, worse browser.
     */
    @Test
    @DisplayName("the basket fills, survives, stays out of the next shop's, and invents no figures")
    void theBasketBehaves(@TempDir Path tmp) throws Exception {
        Assumptions.assumeTrue(nodeIsHere(),
                "node is not on the PATH, so basket.js cannot be run: skipping the basket cases");

        Path script = unpack(tmp, SCRIPT);
        Path harness = unpack(tmp, HARNESS);

        Process run = new ProcessBuilder("node", harness.toString(), script.toString())
                .redirectErrorStream(true)
                .start();
        String output = new String(run.getInputStream().readAllBytes(), StandardCharsets.UTF_8);
        assertThat(run.waitFor(120, TimeUnit.SECONDS)).as("the harness finished").isTrue();

        // The harness prints a line per case; on a failure it is the whole story, so it is
        // attached rather than left in a file nobody opens.
        assertThat(run.exitValue()).as("basket cases:%n%s", output).isZero();
        assertThat(output).contains("basket cases passed");
    }
}
