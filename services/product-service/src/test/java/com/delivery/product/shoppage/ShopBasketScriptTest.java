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
     * producing one of its own is to give it nothing to produce it from — every figure the quote
     * spells is a string — and the second surest is this: the file contains no arithmetic on
     * anything that came back from the server at all.
     *
     * <p>What it does do with numbers is count things: a quantity goes up by one, a position is an
     * index into a list of rows, and two ages in milliseconds say whether a pad or a receipt is too
     * old to keep. They are about rows and time; not one of them has ever seen a price.
     *
     * <p><strong>The one number that does reach the browser is sealed.</strong> A quote for a pad
     * that can be sent carries {@code send} — the order service's own request, total included —
     * because a ticket cannot name a dish by where it sat on somebody's screen
     * ({@link ShopBasket.Send}). The script relays it: it appears in the file exactly once, as the
     * argument of one {@code JSON.stringify}, and no field of it is ever read. That is asserted here
     * rather than described in a comment, because it is the whole of what makes an amount of money
     * passing through a browser harmless.
     */
    @Test
    @DisplayName("the script works out no price, and never opens the request that carries one")
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
        // What arithmetic there is: one count going up or down by one, and two ages — the pad's and
        // a sent round's, each against how long it is worth keeping.
        assertThat(occurrences(code, "+=")).isEqualTo(2);
        assertThat(code).contains("lines[i][1] += by")
                .contains("(Date.now() - was.u) > KEEP")
                .contains("(Date.now() - round.u) < TOLD");
        // And every figure printed is a field of the answer, assigned as it arrived.
        for (String spelled : List.of("line.price", "answer.total", "answer.totalLbp",
                "answer.count")) {
            assertThat(code).as("%s is printed, not computed", spelled).contains(spelled);
        }

        // The sealed request: posted once, opened never. `send` is read off the answer and handed
        // straight to stringify, and the only other names it goes by are the two that carry it —
        // so there is no path in this file from the total inside it to anything on the screen.
        assertThat(occurrences(code, "JSON.stringify")).isEqualTo(3);
        assertThat(code).contains("JSON.stringify(going.body)").contains("body: answer.send");
        for (String reaching : List.of("send.expectedTotal", "send.items", "send.storeId",
                "send.table", "body.expectedTotal", "body.items", ".expectedTotal")) {
            assertThat(code).as("nothing in the file reads %s", reaching).doesNotContain(reaching);
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
        // The ceiling was 13 kB, then 14 when the pad learnt to take an order at a table. It is 28
        // now, and this is what bought it: the pad could be filled and priced but not SENT — the
        // button was disabled in a line of this file with nothing on the screen to explain it — and
        // sending is not one line. It is the post, the receipt of what went, the ticket's state as
        // the kitchen moves it, a sentence for every way a send can be refused, and a memory of
        // what this phone has already sent from this table.
        //
        // The real numbers, because a ceiling nobody can name the cost of is one that gets nudged
        // again next time: 26.9 kB on disk (27,518 B against a 28,672 B ceiling) and 8.8 kB gzipped,
        // up from 13.4 kB and 4.7 kB. Gzipped is the figure that matters and the one
        // PublicShopPageWeightTest counts; a busy 40-item shop's whole page is 24.1 kB over the
        // wire against the 35 kB the brief allowed.
        //
        // And it is now linked only where there is a pad to run (ShopPageHtml.head), which is what
        // makes that affordable: a shop with table ordering off used to download all of this to
        // discover it had nothing to do, and nearly every shop has it off.
        assertThat(result.getResponse().getContentAsByteArray().length).isLessThan(28 * 1024);
    }

    @Test
    @DisplayName("the page and the basket agree on the hooks between them")
    void thePageAndTheScriptUseTheSameHooks() throws Exception {
        String js = served();
        ShopPageFixture shop = new ShopPageFixture().takesTableOrders()
                .section("Bread", ShopPageFixture.Item.of("Kaak", "1.50"));
        String html = PublicShopBasketApiTest.page(shop, "en");

        for (String hook : List.of(".bk", ".bl", ".bkempty", ".bksum", ".bkwhat", ".bksays",
                ".bkn", ".bkgo", ".bktab", ".bkno", ".bksent", ".bkgot", ".peek", ".a",
                ".menu .sec .items > li")) {
            assertThat(js).as("the script looks for %s", hook).contains("'" + hook + "'");
        }
        for (String attribute : List.of("data-q", "data-v", "data-e", "data-nt", "data-l",
                "data-more", "data-less", "data-note", "data-eg",
                // And the half of the pad that sends it: where to, where the ticket is read back,
                // and every sentence about what happens after the tap.
                "data-s", "data-ss", "data-g", "data-st", "data-r", "data-sd")) {
            assertThat(js).as("the script reads %s", attribute).contains("'" + attribute + "'");
            assertThat(html).as("the page writes %s", attribute).contains(attribute + "=\"");
        }
        for (String css : List.of("class=\"bk\"", "class=\"bl\"", "class=\"bkempty\"",
                "class=\"bksum\"", "class=\"bksays\"", "class=\"bksent\"", "class=\"bkgot\"",
                "class=\"peek\"", "class=\"a\"")) {
            assertThat(html).as("the page draws %s", css).contains(css);
        }
        // The two addresses, exactly as the deployment routes them, and both relative: the page is
        // served on two hostnames under connect-src 'self', so an absolute one would be blocked for
        // every reader who arrived by the other name. ShopPageHtml.SEND_PATH says it at length.
        assertThat(html).contains("data-s=\"/api/table-orders\"")
                .contains("data-ss=\"/api/table-orders/status/\"");
    }

    /**
     * That the one action on this page is wired to anything at all.
     *
     * <p><strong>This is the assertion whose absence shipped the defect.</strong> A diner could scan
     * a card, fill a pad, read a correct server-priced total — and not send it, because this file
     * said {@code go.disabled = true} with a comment explaining that there was nowhere for it to go.
     * There was, by then: the endpoint, its refusals and its status link were built, merged and
     * deployed. Every test passed, because no test connected the two halves.
     *
     * <p>What the pressing of the button does is a question about a document, so
     * {@link #theBasketBehaves} answers it, under node, which is not on every machine. This case is
     * the half that cannot skip: the button has an action, the action posts to the address the page
     * printed, and what takes the disabled off is the server's answer and nothing else.
     */
    @Test
    @DisplayName("the send is wired: the button has an action, and the server is what enables it")
    void theButtonIsWiredToASend() throws Exception {
        String js = code(served());

        assertThat(js)
                .as("the button has an action")
                .contains("go.onclick = fire")
                .as("which posts to the path the page printed, not to an address of its own")
                .contains("request.open('POST', sendPath, true)")
                .contains("panel.getAttribute('data-s')")
                .as("and the ticket's own link is read back the same way")
                .contains("request.open('GET', statusPath + round.i, true)");
        // What enables it: one place, and its condition is a field of the server's answer. There is
        // no second path to a live button and no way for the browser to decide it has one.
        assertThat(occurrences(js, "go.disabled = false")).isEqualTo(1);
        assertThat(js).contains("if (answer.send) { allow(answer); }");
        // And what disables it: one place too, so "dead" and "the reason is on the screen" cannot
        // come apart.
        assertThat(occurrences(js, "go.disabled = true")).isEqualTo(1);
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
     * Adding, changing and removing; surviving a reload; two shops staying apart; a table code kept
     * and a nonsense one ignored; a total that appears only when the server has sent one — and then
     * the tap: that the button can be pressed at all, that one press is one ticket, that a second
     * round is a second ticket, what the diner is shown afterwards, and every refusal in words.
     *
     * <p>All of it against the real file. The cases and what each one asserts are in
     * {@code basket.test.js} beside this class — they are written there rather than here because
     * they are about a document, and a Java test that built one would be a second, worse browser.
     *
     * <p><strong>Skipping this skips the reachability of the send.</strong>
     * {@link #theButtonIsWiredToASend} is the part that cannot skip, and it is deliberately narrow:
     * it reads the file, not the screen. A build with no node has not been told that a diner can
     * order.
     */
    @Test
    @DisplayName("the basket fills, sends, remembers what it sent, and says every refusal")
    void theBasketBehaves(@TempDir Path tmp) throws Exception {
        Assumptions.assumeTrue(nodeIsHere(), "node is not on the PATH, so basket.js cannot be run: "
                + "skipping the basket cases, INCLUDING whether the send button can be pressed");

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
