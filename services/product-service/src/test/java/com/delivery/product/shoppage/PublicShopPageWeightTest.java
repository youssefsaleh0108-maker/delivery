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
 * <p>The budgets are for the <em>document</em>: the HTML and the one stylesheet, which is
 * everything needed to render the page's text. Pictures are separate requests, every catalogue
 * thumbnail is {@code loading="lazy"}, and none of them blocks the answer.
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
     */
    private static ShopPageFixture cappedShop() {
        ShopPageFixture shop = new ShopPageFixture()
                .areas("Hamra", "Ras Beirut", "Manara", "Ain El Mreisseh", "Verdun");
        String[] sections = {"Bread and pastry", "Cold drinks", "Dairy", "Household", "Tinned"};
        for (int s = 0; s < sections.length; s++) {
            List<Item> items = new ArrayList<>();
            for (int i = 0; i < 26; i++) {
                items.add(Item.of(sections[s] + " item number " + (i + 1),
                        "1." + String.format("%02d", (i * 7) % 100)));
            }
            shop.section(sections[s], items.toArray(Item[]::new));
        }
        return shop;
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

    @Test
    @DisplayName("a forty-item shop's document fits in what a 3G phone can fetch quickly")
    void theDocumentIsSmall() throws Exception {
        ShopPageFixture shop = busyShop();
        byte[] html = shop.mvc().perform(get("/s/" + shop.slug()))
                .andReturn().getResponse().getContentAsByteArray();
        byte[] css = shop.mvc().perform(get("/s/assets/shop.css"))
                .andReturn().getResponse().getContentAsByteArray();

        int total = html.length + css.length;
        int compressed = gzipped(html) + gzipped(css);
        System.out.printf("shop page: html %d B (gzip %d B), css %d B (gzip %d B), "
                        + "document %d B (gzip %d B)%n",
                html.length, gzipped(html), css.length, gzipped(css), total, compressed);

        // 64 kB uncompressed and 16 kB over the wire. A 3G handset at a realistic 400 kbit/s
        // fetches 16 kB in about a third of a second; the budget is deliberately close to what the
        // page weighs today, so the next thing added to it has to be a decision.
        assertThat(total).isLessThan(64 * 1024);
        assertThat(compressed).isLessThan(16 * 1024);
    }

    @Test
    @DisplayName("a shop with an enormous catalogue draws the cap itself, and says so honestly")
    void anEnormousShelfIsBounded() throws Exception {
        ShopPageFixture shop = cappedShop().shelfTotal(4000);
        byte[] bytes = shop.mvc().perform(get("/s/" + shop.slug()))
                .andReturn().getResponse().getContentAsByteArray();
        String html = new String(bytes, java.nio.charset.StandardCharsets.UTF_8);

        // The cap drawn, not merely configured: a hundred and twenty item names in the markup.
        assertThat(occurrences(html, "<span class=\"n\">"))
                .isEqualTo(PublicShopPageService.MAX_ITEMS);
        assertThat(html).contains("and 3,880 more in the app");

        System.out.printf("capped shop page: html %d B (gzip %d B), %d items%n",
                bytes.length, gzipped(bytes), PublicShopPageService.MAX_ITEMS);
        // The worst page this service can send still fits the budget the common one is held to.
        assertThat(bytes.length).isLessThan(64 * 1024);
        assertThat(gzipped(bytes)).isLessThan(16 * 1024);
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
