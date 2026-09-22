package com.delivery.product.shoppage;

import java.nio.charset.StandardCharsets;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * The table QR codes: {@code GET /s/{slug}/qr.png?t=7} and {@code GET /s/{slug}/tables}.
 *
 * <p>Asserted against the bytes, like the poster's tests and for the same reason: there is no
 * client to interpret a card, only a printer and then a phone's camera. Three things have to be
 * true or the feature is a wall of squares that go to the wrong place — every table gets a
 * <em>different</em> code, every one of them points at <em>this</em> shop carrying <em>its own</em>
 * table, and a reprint of one card is the card that was printed the first time.
 */
@DisplayName("the shop's table QR codes and the sheet they print on")
class ShopTableCardsApiTest {

    private static String body(MvcResult result) throws Exception {
        result.getResponse().setCharacterEncoding(StandardCharsets.UTF_8.name());
        return result.getResponse().getContentAsString();
    }

    /** The printing controller over one fixture's shop, on the base URL the page uses. */
    private static MockMvc sheets(ShopPageFixture shop) {
        return MockMvcBuilders
                .standaloneSetup(new ShopPosterController(shop.service(), ShopPageFixture.BASE))
                .build();
    }

    /** The page controller, which is where the codes themselves are drawn. */
    private static MockMvc codes(ShopPageFixture shop) {
        return MockMvcBuilders.standaloneSetup(shop.controller()).build();
    }

    private static ShopPageFixture roomOfTwelve() {
        return new ShopPageFixture()
                .tables(12)
                .section("Bread", ShopPageFixture.Item.of("Kaak", "1.50"));
    }

    // ---------------------------------------------------------------- the codes

    @Test
    @DisplayName("a shop with twelve tables gets twelve distinct codes, each carrying its own table")
    void twelveTablesTwelveCodes() throws Exception {
        ShopPageFixture shop = roomOfTwelve();
        MockMvc mvc = codes(shop);

        java.util.Set<String> distinct = new java.util.LinkedHashSet<>();
        for (int table = 1; table <= 12; table++) {
            byte[] png = mvc.perform(get("/s/{slug}/qr.png", shop.slug()).param("t", "" + table))
                    .andExpect(status().isOk())
                    .andReturn().getResponse().getContentAsByteArray();
            assertThat(png).as("table %d's code", table).isNotEmpty();
            distinct.add(java.util.Base64.getEncoder().encodeToString(png));
        }
        assertThat(distinct).as("twelve tables, twelve different codes").hasSize(12);

        // And the plain counter code is a thirteenth thing again: a card on a table must not be the
        // code that means "the shop", or an order from table 7 would arrive with no table on it.
        byte[] plain = mvc.perform(get("/s/{slug}/qr.png", shop.slug()))
                .andExpect(status().isOk())
                .andReturn().getResponse().getContentAsByteArray();
        assertThat(distinct).doesNotContain(java.util.Base64.getEncoder().encodeToString(plain));
    }

    @Test
    @DisplayName("every code is this shop's page with its own table in the query string")
    void everyCodeIsThisShopAndThisTable() {
        ShopPageFixture shop = roomOfTwelve();
        for (int table = 1; table <= 12; table++) {
            assertThat(ShopTableCodes.urlOf(ShopPageFixture.BASE, shop.slug(), table))
                    .isEqualTo(ShopPageFixture.BASE + "/s/" + shop.slug() + "?t=" + table);
        }
        // The parameter the web basket reads back. Agreed with that work, and spelled once.
        assertThat(ShopTableCodes.PARAM).isEqualTo("t");
    }

    @Test
    @DisplayName("a table the shop has not said it has is the same 404 as a shop nobody may see")
    void refusesATableTheShopDoesNotHave() throws Exception {
        MockMvc mvc = codes(roomOfTwelve());
        String slug = roomOfTwelve().slug();
        for (String table : new String[] {"0", "-1", "13", "9999"}) {
            mvc.perform(get("/s/{slug}/qr.png", slug).param("t", table))
                    .andExpect(status().isNotFound());
        }
    }

    @Test
    @DisplayName("a shop that has asked for no tables has no card to print and no code to draw")
    void aShopWithNoTables() throws Exception {
        ShopPageFixture shop = new ShopPageFixture();
        codes(shop).perform(get("/s/{slug}/qr.png", shop.slug()).param("t", "1"))
                .andExpect(status().isNotFound());
        sheets(shop).perform(get("/s/{slug}/tables", shop.slug()))
                .andExpect(status().isNotFound());
        // The counter code is untouched: not having tables is not the same as not having a page.
        codes(shop).perform(get("/s/{slug}/qr.png", shop.slug())).andExpect(status().isOk());
    }

    @Test
    @DisplayName("a shop nobody may see cannot print table cards either")
    void hiddenShopsPrintNothing() throws Exception {
        ShopPageFixture draft = new ShopPageFixture(false).tables(6);
        sheets(draft).perform(get("/s/{slug}/tables", draft.slug()))
                .andExpect(status().isNotFound());
        codes(draft).perform(get("/s/{slug}/qr.png", draft.slug()).param("t", "3"))
                .andExpect(status().isNotFound());
    }

    // ---------------------------------------------------------------- the sheet

    @Test
    @DisplayName("the sheet prints one card per table, each with its own code and address")
    void theSheetPrintsEveryTable() throws Exception {
        ShopPageFixture shop = roomOfTwelve();
        String sheet = body(sheets(shop).perform(get("/s/{slug}/tables", shop.slug()))
                .andExpect(status().isOk())
                .andReturn());

        assertThat(sheet).contains("<html lang=\"en\" dir=\"ltr\"");
        assertThat(java.util.regex.Pattern.compile("<li class=\"card\">").matcher(sheet).results())
                .as("one card per table").hasSize(12);
        for (int table = 1; table <= 12; table++) {
            assertThat(sheet).contains("/s/" + shop.slug() + "/qr.png?t=" + table);
            assertThat(sheet).contains("Table " + table);
            assertThat(sheet).contains("www.youdrop.shop/s/" + shop.slug() + "?t=" + table);
        }
        assertThat(sheet).contains("Dekkanet Al Rawche");
    }

    @Test
    @DisplayName("nothing on a card can go out of date")
    void nothingStaleOnACard() throws Exception {
        ShopPageFixture shop = new ShopPageFixture()
                .tables(3)
                .areas("Hamra")
                .section("Bread", ShopPageFixture.Item.of("Kaak", "1.50"));
        String sheet = body(sheets(shop).perform(get("/s/{slug}/tables", shop.slug()))
                .andExpect(status().isOk())
                .andReturn());

        // A card lives on a table for a year. A price, an opening hour or a delivery fee printed on
        // one would be wrong within a week, and there is no way to correct a piece of paper.
        assertThat(sheet).doesNotContain("Kaak").doesNotContain("1.50").doesNotContain("Hamra")
                .doesNotContain("23:00").doesNotContain("Open");
    }

    @Test
    @DisplayName("a reprint of table 7 is the card the whole sheet printed, byte for byte")
    void reprintingOneCardMatchesTheOriginal() throws Exception {
        ShopPageFixture shop = roomOfTwelve();
        MockMvc mvc = sheets(shop);

        String whole = body(mvc.perform(get("/s/{slug}/tables", shop.slug()))
                .andExpect(status().isOk()).andReturn());
        String reprint = body(mvc.perform(get("/s/{slug}/tables", shop.slug()).param("t", "7"))
                .andExpect(status().isOk()).andReturn());

        // The card itself — the thing that gets cut out and stuck down — is one function of one set
        // of inputs, so the two renderings produce the same element character for character.
        String card = ShopTableCardsHtml.card(
                shop.service().read(shop.slug()), ShopPageText.EN, 7, ShopPageFixture.BASE);
        assertThat(whole).contains(card);
        assertThat(reprint).contains(card);
        assertThat(java.util.regex.Pattern.compile("<li class=\"card\">").matcher(reprint).results())
                .as("a reprint is one card, not a page with eleven blanks").hasSize(1);

        // And the code on it: the same bytes, because the image is a pure function of a URL that is
        // a pure function of the slug and the table.
        MockMvc pngs = codes(shop);
        byte[] first = pngs.perform(get("/s/{slug}/qr.png", shop.slug()).param("t", "7"))
                .andReturn().getResponse().getContentAsByteArray();
        byte[] again = pngs.perform(get("/s/{slug}/qr.png", shop.slug()).param("t", "7"))
                .andReturn().getResponse().getContentAsByteArray();
        assertThat(again).isEqualTo(first);
    }

    @Test
    @DisplayName("the Arabic sheet is right-to-left and still prints both instructions and the address")
    void theArabicSheet() throws Exception {
        ShopPageFixture shop = roomOfTwelve();
        String sheet = body(sheets(shop)
                .perform(get("/s/{slug}/tables", shop.slug()).param("lang", "ar"))
                .andExpect(status().isOk())
                .andReturn());

        assertThat(sheet).contains("<html lang=\"ar\" dir=\"rtl\"");
        assertThat(sheet).contains("طاولة 7");
        assertThat(sheet).contains("امسح الرمز لترى القائمة وتطلب");
        // Both languages on every card, whichever one the merchant asked for.
        assertThat(sheet).contains("Scan to see the menu and order");
        // An address is left-to-right in every language, or the table number is typed back wrong.
        assertThat(sheet).contains("<p class=\"addr\" dir=\"ltr\">www.youdrop.shop/s/"
                + shop.slug() + "?t=7</p>");
    }

    @Test
    @DisplayName("the sheet carries the poster's own narrow policy and loads only its own pictures")
    void carriesTheStrictPolicy() throws Exception {
        ShopPageFixture shop = roomOfTwelve();
        String policy = sheets(shop).perform(get("/s/{slug}/tables", shop.slug()))
                .andExpect(status().isOk())
                .andReturn().getResponse().getHeader("Content-Security-Policy");

        assertThat(policy).isEqualTo("default-src 'none'; img-src 'self'; style-src 'self'; "
                + "base-uri 'none'; form-action 'none'; frame-ancestors 'none'");

        // Its one stylesheet is served by this service, so style-src 'self' is the whole of it.
        sheets(shop).perform(get("/s/assets/tables.css")).andExpect(status().isOk());
    }

    @Test
    @DisplayName("a sheet of cards is not something a search engine should index")
    void notIndexed() throws Exception {
        ShopPageFixture shop = roomOfTwelve();
        assertThat(body(sheets(shop).perform(get("/s/{slug}/tables", shop.slug())).andReturn()))
                .contains("<meta name=\"robots\" content=\"noindex\">");
    }
}
