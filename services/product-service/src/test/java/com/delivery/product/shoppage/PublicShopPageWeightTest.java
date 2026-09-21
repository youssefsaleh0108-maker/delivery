package com.delivery.product.shoppage;

import java.io.ByteArrayOutputStream;
import java.util.ArrayList;
import java.util.List;
import java.util.zip.GZIPOutputStream;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import com.delivery.product.shoppage.ShopPageFixture.Item;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;

/**
 * What a phone on 3G actually downloads.
 *
 * <p>This is the page's hardest requirement and the easiest one to lose: it is opened from a chat
 * message, on a handset, on a network that is often a bar of 3G, by somebody who wants to know
 * whether the shop is open. A budget asserted in a test is the only thing that keeps a page small
 * once people start adding to it — so these numbers fail the build rather than appearing in a
 * report nobody reads afterwards.
 *
 * <p>The budgets cover everything the page needs to be itself: the HTML, the one stylesheet and
 * the one script. Pictures are separate requests, every catalogue thumbnail is
 * {@code loading="lazy"}, and none of them blocks the answer.
 *
 * <p>Measured twice, with the script and without it, because those are two real readers. The page
 * is complete either way — the catalogue is in the markup and the script only filters it — so the
 * reader who never gets the script downloads less, not less of the shop.
 */
@DisplayName("what the page weighs")
class PublicShopPageWeightTest {

    /** A real corner shop's page: four aisles, forty things, photos on all of them. */
    private static ShopPageFixture busyShop() {
        ShopPageFixture shop = new ShopPageFixture()
                .areas("Hamra", "Ras Beirut", "Manara", "Ain El Mreisseh", "Verdun");
        String[] sections = {"Bread and pastry", "Cold drinks", "Dairy", "Household"};
        for (int s = 0; s < sections.length; s++) {
            List<Item> items = new ArrayList<>();
            for (int i = 0; i < 10; i++) {
                items.add(Item.of(sections[s] + " item number " + (i + 1),
                        "1." + String.format("%02d", (i * 7) % 100)));
            }
            shop.section(sections[s], items.toArray(Item[]::new));
        }
        return shop;
    }

    /**
     * The biggest page this service can produce: the whole cap drawn, with more behind it.
     *
     * <p>130 items on the shelf so the query's own limit does the cutting, which is the page a
     * large grocer actually gets — the "forty things" shop above is the common case, not the worst
     * one, and a budget asserted only on the common case is not a budget.
     *
     * <p>And every one of them described, at the full length a row will carry, in words that
     * differ from row to row. Both halves of that matter: a merchant who describes everything is
     * the worst case the service can be asked for, and a hundred and twenty <em>identical</em>
     * descriptions would compress to almost nothing and make this budget look easier than it is.
     */
    private static ShopPageFixture cappedShop() {
        ShopPageFixture shop = new ShopPageFixture()
                .areas("Hamra", "Ras Beirut", "Manara", "Ain El Mreisseh", "Verdun");
        String[] sections = {"Bread and pastry", "Cold drinks", "Dairy", "Household", "Tinned"};
        for (int s = 0; s < sections.length; s++) {
            List<Item> items = new ArrayList<>();
            for (int i = 0; i < 26; i++) {
                items.add(Item.of(sections[s] + " item number " + (i + 1),
                                "1." + String.format("%02d", (i * 7) % 100))
                        .describedAs(describedAtLength(sections[s], i)));
            }
            shop.section(sections[s], items.toArray(Item[]::new));
        }
        return shop;
    }

    /** A description longer than a row will carry, and different from every other one. */
    private static String describedAtLength(String section, int index) {
        String[] words = {"jarred", "pressed", "baked", "salted", "smoked", "bottled", "milled",
            "cured", "dried", "roasted", "brined", "stoneground", "sun-dried", "hand-wrapped"};
        StringBuilder about = new StringBuilder(section).append(" number ").append(index + 1)
                .append(", ");
        while (about.length() < PublicShopPageService.MAX_ITEM_DESCRIPTION + 24) {
            about.append(words[(index * 7 + about.length()) % words.length]).append(' ');
        }
        return about.toString().strip();
    }

    private static int occurrences(String html, String needle) {
        return html.split(java.util.regex.Pattern.quote(needle), -1).length - 1;
    }

    private static int gzipped(byte[] raw) throws Exception {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        try (GZIPOutputStream gzip = new GZIPOutputStream(out)) {
            gzip.write(raw);
        }
        return out.size();
    }

    /**
     * Everything a browser fetches before this page is finished: the markup, the stylesheet and
     * the catalogue filter. Gzipped, because that is what crosses the network.
     *
     * <p>The filter is counted although a reader with scripting off never fetches it — a budget
     * that left out the one optional file would be a budget for the cheaper reader.
     */
    private Fetched fetch(ShopPageFixture shop, String language) throws Exception {
        byte[] html = shop.mvc().perform(get("/s/" + shop.slug()).param("lang", language))
                .andReturn().getResponse().getContentAsByteArray();
        byte[] css = shop.mvc().perform(get("/s/assets/shop.css"))
                .andReturn().getResponse().getContentAsByteArray();
        byte[] js = shop.mvc().perform(get("/s/assets/shop.js"))
                .andReturn().getResponse().getContentAsByteArray();
        return new Fetched(html.length + css.length + js.length,
                gzipped(html) + gzipped(css), gzipped(js), html);
    }

    /**
     * @param withoutScript what a reader with JavaScript off downloads: markup and stylesheet
     * @param script        the one file only a reader with JavaScript on ever asks for
     */
    private record Fetched(int uncompressed, int withoutScript, int script, byte[] html) {

        int withScript() {
            return withoutScript + script;
        }
    }

    private void report(String label, Fetched fetched) {
        System.out.printf("shop page %-28s raw %6d B | gzip: no-js %5d B, with js %5d B "
                        + "(script %d B)%n",
                label, fetched.uncompressed(), fetched.withoutScript(), fetched.withScript(),
                fetched.script());
    }

    @Test
    @DisplayName("a forty-item shop's page fits in what a 3G phone can fetch quickly")
    void theDocumentIsSmall() throws Exception {
        Fetched english = fetch(busyShop(), "en");
        Fetched arabic = fetch(busyShop(), "ar");
        report("busy, 40 items, en", english);
        report("busy, 40 items, ar", arabic);

        // 12 kB over the wire for the shop a reader actually opens. A 3G handset at a realistic
        // 400 kbit/s fetches that in about a quarter of a second, and the budget sits close enough
        // to what the page weighs that the next thing added to it has to be a decision.
        for (Fetched fetched : List.of(english, arabic)) {
            assertThat(fetched.withScript()).isLessThan(12 * 1024);
            assertThat(fetched.uncompressed()).isLessThan(64 * 1024);
        }
    }

    /**
     * The ceiling, on the worst page this service can send.
     *
     * <p>A hundred and twenty items, every one of them described at the full length a row carries,
     * in words that differ from row to row, with a structured-data block naming all of them — and
     * in Arabic as well, which is the longer of the two renderings. 25 kB gzipped is the whole
     * budget for everything the page needs, and nothing that lands here may take it past that.
     */
    @Test
    @DisplayName("the worst page this service can send still fits the whole 25 kB budget")
    void anEnormousShelfIsBounded() throws Exception {
        Fetched english = fetch(cappedShop().shelfTotal(4000), "en");
        Fetched arabic = fetch(cappedShop().shelfTotal(4000), "ar");
        report("capped, 120 items, en", english);
        report("capped, 120 items, ar", arabic);

        String html = new String(english.html(), java.nio.charset.StandardCharsets.UTF_8);
        // The cap drawn, not merely configured: a hundred and twenty item names in the markup.
        assertThat(occurrences(html, "<span class=\"n\">"))
                .isEqualTo(PublicShopPageService.MAX_ITEMS);
        assertThat(html).contains("and 3,880 more in the app");

        for (Fetched fetched : List.of(english, arabic)) {
            // The ceiling the page was given, rather than a line drawn just above where it
            // happens to sit: the two budgets above are the tripwires that catch drift, and this
            // is the number the page may not exceed whatever else is ever added to it.
            assertThat(fetched.withScript()).isLessThan(25 * 1024);
            // Uncompressed too, because gzip is a courtesy: a proxy that strips Accept-Encoding,
            // or a client that never sent it, gets these bytes instead.
            assertThat(fetched.uncompressed()).isLessThan(128 * 1024);
        }
    }

    /**
     * The floor: a shop with three things on its shelf.
     *
     * <p>Almost all of this is the two shared files, which is why this number moved. The sticky
     * section bar and the menu's rewritten rows cost about 2.1 kB gzipped between the stylesheet
     * and the script, and a three-aisle shop pays it in full while a three-<em>item</em> shop pays
     * it for a bar it never draws — one stylesheet and one script serve every shop page there is,
     * cached for a year across all of them, and splitting them so the smallest shop could skip the
     * bar's half would trade a kilobyte for a second request on every other page.
     *
     * <p>So 10 kB, not 9, and the two budgets that matter did not move: the busy shop below the
     * 12 kB a reader actually opens, and the whole thing below the 25 kB ceiling.
     */
    @Test
    @DisplayName("a small shop's page is small, in both languages")
    void aSmallShopIsSmall() throws Exception {
        for (String language : List.of("en", "ar")) {
            Fetched fetched = fetch(new ShopPageFixture()
                    .areas("Hamra")
                    .section("Bread", Item.of("Kaak", "1.50"), Item.of("Markouk", "2.25"),
                            Item.of("Manakish", "2.00")), language);
            report("small, 3 items, " + language, fetched);
            assertThat(fetched.withScript()).isLessThan(10 * 1024);
            // The reader with no script pays for neither the filter nor the bar's behaviour, and
            // still gets the whole shelf and a row of working section links.
            assertThat(fetched.withoutScript()).isLessThan(7 * 1024);
        }
    }

    @Test
    @DisplayName("every catalogue picture is lazy, so none of them delays the text")
    void picturesDoNotBlockTheAnswer() throws Exception {
        ShopPageFixture shop = busyShop();
        String html = new String(shop.mvc().perform(get("/s/" + shop.slug()))
                .andReturn().getResponse().getContentAsByteArray(),
                java.nio.charset.StandardCharsets.UTF_8);

        int images = html.split("<img", -1).length - 1;
        int lazy = html.split("loading=\"lazy\"", -1).length - 1;
        // Everything except the cover and the logo, which are the page's first impression.
        assertThat(images).isEqualTo(lazy + 2);
    }
}
