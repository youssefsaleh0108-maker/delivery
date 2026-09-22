package com.delivery.product.shoppage;

import java.nio.charset.StandardCharsets;
import java.util.List;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MvcResult;

import com.delivery.product.shoppage.ShopPageFixture.Item;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * What a table's order pad comes to, and who says so.
 *
 * <p><strong>The figure a diner reads is the server's.</strong> Not a sum in a browser, not a sum
 * the page and the till might each reach separately. These tests ask the endpoint and read its
 * bytes; they also assert the shape that makes the rule hold on its own rather than by anybody
 * remembering it — the answer carries no number at all. Every figure in it has already been added
 * up and already been spelled, in the diner's language, by the same {@link ShopPageText} that
 * spells the prices in the markup.
 *
 * <p><strong>And there is one figure.</strong> No delivery fee, no minimum, no service charge, no
 * tax: the diner is sitting in the restaurant and will pay the restaurant. A second money line
 * appearing here would be the platform inserting itself into a bill it is not part of.
 */
@DisplayName("what a table's order comes to")
class PublicShopBasketApiTest {

    private static final ObjectMapper JSON = new ObjectMapper();

    /** A restaurant that takes orders from its tables, with two aisles on its menu. */
    private static ShopPageFixture aShop() {
        return new ShopPageFixture().takesTableOrders()
                .section("Mezze", Item.of("Hummus", "1.50"), Item.of("Fattoush", "2.25"))
                .section("Drinks", Item.of("Jallab", "0.75"));
    }

    // ---------------------------------------------------------------- asking

    /** The shelf fingerprint the page prints, which is the only name a pad's positions have. */
    static String versionOf(String html) {
        int at = html.indexOf("data-v=\"");
        assertThat(at).as("the page carries a shelf version").isNotEqualTo(-1);
        return html.substring(at + 8, html.indexOf('"', at + 8));
    }

    static String page(ShopPageFixture shop, String language) throws Exception {
        MvcResult result = shop.mvc()
                .perform(get("/s/" + shop.slug()).param("lang", language)).andReturn();
        result.getResponse().setCharacterEncoding(StandardCharsets.UTF_8.name());
        return result.getResponse().getContentAsString();
    }

    /** One quote, as the page's own script asks for it: same shop, same language, JSON both ways. */
    static String quote(ShopPageFixture shop, String language, String body) throws Exception {
        MvcResult result = shop.mvc()
                .perform(post("/s/" + shop.slug() + "/quote").param("lang", language)
                        .contentType(MediaType.APPLICATION_JSON).content(body))
                .andReturn();
        result.getResponse().setCharacterEncoding(StandardCharsets.UTF_8.name());
        return result.getResponse().getContentAsString();
    }

    /** A pad at table 7, which is the ordinary case this whole feature is for. */
    private static JsonNode atTable7(ShopPageFixture shop, String language, String lines)
            throws Exception {
        String version = versionOf(page(shop, language));
        return JSON.readTree(quote(shop, language, "{\"version\":\"" + version
                + "\",\"table\":\"7\",\"lines\":" + lines + "}"));
    }

    private static JsonNode atTable7(ShopPageFixture shop, String lines) throws Exception {
        return atTable7(shop, "en", lines);
    }

    // ---------------------------------------------------------------- the sum

    @Test
    @DisplayName("the lines and the total come back from the server, already added up")
    void pricesAPad() throws Exception {
        // Two hummus at 1.50 and one fattoush at 2.25.
        JsonNode answer = atTable7(aShop(), "[{\"at\":0,\"qty\":2},{\"at\":1,\"qty\":1}]");

        assertThat(answer.path("lines")).hasSize(2);
        assertThat(answer.path("lines").get(0).path("name").asText()).isEqualTo("Hummus");
        assertThat(answer.path("lines").get(0).path("qty").asText()).isEqualTo("2×");
        assertThat(answer.path("lines").get(0).path("price").asText()).isEqualTo("$3.00");
        assertThat(answer.path("total").asText()).isEqualTo("$5.25");
        assertThat(answer.path("totalLabel").asText()).isEqualTo("Total");
        assertThat(answer.path("table").asText()).isEqualTo("7");
        assertThat(answer.path("count").asText()).isEqualTo("3 items");
        assertThat(answer.path("ok").asBoolean()).isTrue();
        assertThat(answer.path("says")).isEmpty();
    }

    /**
     * The one figure, and the absence of every other one.
     *
     * <p>A delivery receipt has a subtotal, a fee and a total. A table's pad has the food. This is
     * the assertion that keeps it that way: no field here is named for a charge the platform is not
     * entitled to make, and there is no second money line for one to hide in.
     */
    @Test
    @DisplayName("the food is the whole bill: no fee, no minimum, no service charge, no tax")
    void chargesForNothingButTheFood() throws Exception {
        ShopPageFixture shop = aShop();
        // A shop that has delivery terms set, to prove they are not what is being read.
        assertThat(shop.shop().getDeliveryFee()).isEqualByComparingTo("2.00");
        assertThat(shop.shop().getMinOrder()).isEqualByComparingTo("5.00");

        JsonNode answer = atTable7(shop, "[{\"at\":2,\"qty\":1}]");

        // Seventy-five cents of jallab, and seventy-five cents is the bill — not $2.75, and not a
        // refusal for being under a five-dollar delivery minimum that has nothing to do with
        // sitting at a table.
        assertThat(answer.path("total").asText()).isEqualTo("$0.75");
        assertThat(answer.path("ok").asBoolean()).isTrue();
        for (String charge : List.of("fee", "deliveryFee", "subtotal", "minimum", "shortfall",
                "vat", "tax", "serviceCharge", "discount", "eta")) {
            assertThat(answer.has(charge)).as("a pad has no %s", charge).isFalse();
        }
    }

    /**
     * The shape that makes the rule keep itself.
     *
     * <p>A page cannot add two prices together if it never receives two prices. Every money field
     * is a string that has already been through {@code ShopPageText}, and the only numbers in the
     * document at all are the positions a line was asked about — which are not money, cannot be
     * added to money, and are how the server knows which row is meant.
     */
    @Test
    @DisplayName("the answer holds no number a browser could add to another")
    void handsTheBrowserWordsAndNotFigures() throws Exception {
        JsonNode answer = atTable7(aShop(), "[{\"at\":0,\"qty\":2},{\"at\":2,\"qty\":3}]");

        for (String field : List.of("total", "totalLbp", "count")) {
            assertThat(answer.path(field).isTextual())
                    .as("%s is a spelled figure, not a number", field).isTrue();
        }
        for (JsonNode line : answer.path("lines")) {
            assertThat(line.path("price").isTextual()).isTrue();
            assertThat(line.path("qty").isTextual()).isTrue();
            // The one number on a line is where it sits on the shelf.
            assertThat(line.path("at").isInt()).isTrue();
        }
    }

    @Test
    @DisplayName("a price corrected on the server is the price the pad is quoted at")
    void aChangedPriceChangesTheTotal() throws Exception {
        ShopPageFixture cheap = new ShopPageFixture().takesTableOrders()
                .section("Mezze", Item.of("Hummus", "1.50"));
        ShopPageFixture dear = new ShopPageFixture().takesTableOrders()
                .section("Mezze", Item.of("Hummus", "2.50"));

        assertThat(atTable7(cheap, "[{\"at\":0,\"qty\":2}]").path("total").asText())
                .isEqualTo("$3.00");
        assertThat(atTable7(dear, "[{\"at\":0,\"qty\":2}]").path("total").asText())
                .isEqualTo("$5.00");
    }

    @Test
    @DisplayName("the lira beside the total is the same note the menu above already quotes")
    void quotesTheSameLiraTheMenuDoes() throws Exception {
        ShopPageFixture shop = aShop();
        assertThat(page(shop, "en")).contains("135,000 LBP");

        JsonNode answer = atTable7(shop, "[{\"at\":0,\"qty\":1}]");
        assertThat(answer.path("lines").get(0).path("priceLbp").asText()).isEqualTo("135,000 LBP");
        assertThat(answer.path("totalLbp").asText()).isEqualTo("135,000 LBP");
    }

    // ---------------------------------------------------------------- the note

    /**
     * The one thing anybody types on this page.
     *
     * <p>It is free text from somebody nobody has identified, it ends up on a ticket a waiter
     * reads, and it comes back through a JSON document into a browser — so it is cut to length on
     * the server rather than wherever it is drawn, and escaped by the same rule as everything a
     * merchant typed.
     */
    @Test
    @DisplayName("a note on a line is kept, cut to length, and handed back as the server holds it")
    void keepsAShortNoteOnALine() throws Exception {
        JsonNode answer = atTable7(aShop(),
                "[{\"at\":0,\"qty\":1,\"note\":\"  no onions please  \"}]");

        assertThat(answer.path("lines").get(0).path("note").asText()).isEqualTo("no onions please");

        JsonNode long_ = atTable7(aShop(),
                "[{\"at\":0,\"qty\":1,\"note\":\"" + "x".repeat(400) + "\"}]");
        assertThat(long_.path("lines").get(0).path("note").asText())
                .hasSize(PublicShopPageService.MAX_LINE_NOTE);

        // Nothing written is nothing carried: a blank note is absent rather than an empty string
        // for a ticket to print a gap for.
        JsonNode blank = atTable7(aShop(), "[{\"at\":0,\"qty\":1,\"note\":\"   \"}]");
        assertThat(blank.path("lines").get(0).has("note")).isFalse();
    }

    /**
     * A diner is not a trusted author either.
     *
     * <p>The merchant's own text has been escaped since this page existed; the note is a second
     * source of free text on the same surface, from a stranger, and it goes through the same
     * escaper — what JSON requires, then {@code <}, {@code >} and {@code &}, and the invisible
     * characters dropped so a right-to-left override cannot turn a price round on the pad.
     */
    @Test
    @DisplayName("a note that tries to write markup is escaped exactly as a merchant's text is")
    void escapesWhatTheDinerTyped() throws Exception {
        ShopPageFixture shop = aShop();
        String version = versionOf(page(shop, "en"));
        String json = quote(shop, "en", "{\"version\":\"" + version + "\",\"table\":\"7\","
                + "\"lines\":[{\"at\":0,\"qty\":1,\"note\":"
                + "\"</script><script>a&b\\u202Eflip\"}]}");

        assertThat(json).doesNotContain("<").doesNotContain(">").doesNotContain("‮")
                .contains("\\u003C").contains("\\u003E").contains("\\u0026");
        assertThat(JSON.readTree(json).path("lines").get(0).path("note").asText())
                .isEqualTo("</script><script>a&bflip");
    }

    // ---------------------------------------------------------------- who may send to a kitchen

    /**
     * The rule that keeps a shop's shared link from reaching its kitchen.
     *
     * <p>A shop's page lives in WhatsApp statuses; somebody on the other side of the city holding
     * that link is not sitting at one of its tables. Without a table there is no pad on the page
     * and no answer from the endpoint but the sentence saying so.
     */
    @Test
    @DisplayName("no table, no pad: the endpoint says to scan the code and prices nothing")
    void refusesAPadWithNoTable() throws Exception {
        ShopPageFixture shop = aShop();
        String version = versionOf(page(shop, "en"));

        for (String table : List.of("", "\"\"", "null")) {
            String body = "{\"version\":\"" + version + "\""
                    + ("null".equals(table) ? ",\"table\":null" : ",\"table\":\"\"")
                    + ",\"lines\":[{\"at\":0,\"qty\":2}]}";
            JsonNode answer = JSON.readTree(quote(shop, "en", body));
            assertThat(answer.path("ok").asBoolean()).isFalse();
            assertThat(answer.path("says").get(0).asText())
                    .isEqualTo("Scan the code on your table to order from here.");
            assertThat(answer.has("table")).isFalse();
        }
        // And the page itself draws no pad controls for a reader who arrived without one — that
        // half is basket.js's, and ShopBasketScriptTest runs it.
    }

    @Test
    @DisplayName("a table code that is not one is not a table")
    void refusesANonsenseTable() throws Exception {
        ShopPageFixture shop = aShop();
        String version = versionOf(page(shop, "en"));

        // A stray space either side is trimmed rather than refused — a QR decoder that hands back
        // " 7" has not made the diner a liar — but everything else here is not a table number.
        //
        // "٧" is in this list because Integer.parseInt accepts it: it takes every decimal digit
        // Unicode has, so an Arabic-Indic seven parsed to 7 and would have named a table nobody
        // could find a card for. "99" is here because the room seats twelve — a number this shop
        // does not have is not a table, whatever it looks like, which is the difference between a
        // rule about characters and a rule about this restaurant.
        for (String table : List.of("<script>", "7 OR 1=1", "../../etc/passwd", "ABCDEFGHIJ",
                "٧", "7‮", "a b", "7;12", "B4", "0", "-1", "99", "0007")) {
            JsonNode answer = JSON.readTree(quote(shop, "en", JSON.writeValueAsString(
                    java.util.Map.of("version", version, "table", table,
                            "lines", List.of(java.util.Map.of("at", 0, "qty", 1))))));
            assertThat(answer.path("ok").asBoolean()).as("%s is refused", table).isFalse();
            assertThat(answer.has("table")).as("%s is not echoed", table).isFalse();
        }
        // What a printed card actually carries — a number the shop has — is kept, and echoed
        // spelled the way the page spells every other number.
        for (String table : List.of("1", "7", "12", " 7 ")) {
            JsonNode answer = JSON.readTree(quote(shop, "en", "{\"version\":\"" + version
                    + "\",\"table\":\"" + table + "\",\"lines\":[{\"at\":0,\"qty\":4}]}"));
            assertThat(answer.path("table").asText()).as("%s is a table", table)
                    .isEqualTo(table.trim());
            assertThat(answer.path("ok").asBoolean()).isTrue();
        }
    }

    /**
     * A shop opts in before anything can reach its kitchen.
     *
     * <p>Off for every shop that exists, because the endpoint behind this is anonymous by necessity
     * — a diner who scanned a sticker has no account and will not be asked for one — and a release
     * must not start printing paper in a restaurant that never asked for it.
     */
    @Test
    @DisplayName("a shop that has not turned this on answers with a line about the staff")
    void refusesAShopThatDoesNotOfferIt() throws Exception {
        ShopPageFixture shop = new ShopPageFixture()
                .section("Mezze", Item.of("Hummus", "1.50"));
        String html = page(shop, "en");

        assertThat(html)
                .contains("This shop does not take orders from the table online. "
                        + "Please order with the staff.")
                // Not a hidden pad waiting to be unhidden: there is no pad in the document at all.
                .doesNotContain("class=\"bk\"")
                .doesNotContain("class=\"peek\"")
                .doesNotContain("class=\"a\" type=\"button\"");

        // Refused before the shelf is even read, so there is no shelf version to quote it with —
        // which is the point: a caller poking at this endpoint learns nothing about a shop that
        // has not opted in.
        JsonNode answer = JSON.readTree(quote(shop, "en",
                "{\"version\":\"anything\",\"table\":\"7\",\"lines\":[{\"at\":0,\"qty\":1}]}"));
        assertThat(answer.path("ok").asBoolean()).isFalse();
        assertThat(answer.path("lines")).isEmpty();
        assertThat(answer.has("stale")).isFalse();
        assertThat(answer.path("says").get(0).asText())
                .isEqualTo("This shop does not take orders from the table online. "
                        + "Please order with the staff.");
    }

    // ---------------------------------------------------------------- what else can be wrong

    @Test
    @DisplayName("a closed kitchen: the pad is priced, and said before the diner taps send")
    void saysWhenTheKitchenIsShut() throws Exception {
        ShopPageFixture shut = new ShopPageFixture().takesTableOrders()
                .at("2026-09-20T02:00:00Z")
                .section("Mezze", Item.of("Hummus", "1.50"));

        JsonNode answer = atTable7(shut, "[{\"at\":0,\"qty\":6}]");

        assertThat(answer.path("total").asText()).isEqualTo("$9.00");
        assertThat(answer.path("ok").asBoolean()).isFalse();
        assertThat(answer.path("says").get(0).asText())
                .isEqualTo("The kitchen is closed right now, so this cannot be sent.");
    }

    @Test
    @DisplayName("a dish that has run out is priced and named, and is in no total")
    void leavesSoldOutThingsOutOfTheSum() throws Exception {
        ShopPageFixture shop = new ShopPageFixture().takesTableOrders()
                .section("Mezze", Item.of("Hummus", "1.50"),
                        Item.of("Fattoush", "2.25").outOfStock());

        JsonNode answer = atTable7(shop, "[{\"at\":0,\"qty\":4},{\"at\":1,\"qty\":2}]");

        assertThat(answer.path("lines").get(1).path("name").asText()).isEqualTo("Fattoush");
        assertThat(answer.path("lines").get(1).path("price").asText()).isEqualTo("$4.50");
        assertThat(answer.path("lines").get(1).path("gone").asText()).isEqualTo("Out of stock");
        // Six dollars of hummus, and not a cent of the fattoush.
        assertThat(answer.path("total").asText()).isEqualTo("$6.00");
        assertThat(answer.path("ok").asBoolean()).isFalse();
        assertThat(answer.path("says").get(0).asText())
                .isEqualTo("Something on your order has run out. Remove it to send the rest.");
    }

    @Test
    @DisplayName("an empty pad is not an order")
    void anEmptyPadIsNotOrderable() throws Exception {
        JsonNode answer = atTable7(aShop(), "[]");

        assertThat(answer.path("lines")).isEmpty();
        assertThat(answer.path("ok").asBoolean()).isFalse();
    }

    // ---------------------------------------------------------------- a shelf that moved

    /**
     * The case a positional pad exists to fail on.
     *
     * <p>A pad names its lines by where they sat, so the moment the shelf moves those positions
     * mean something else. The query sorts by name, so a <em>rename</em> moves rows without adding
     * or removing one — which is exactly the case a digest of ids alone would have missed, and
     * exactly the case that would otherwise send a kitchen a dish nobody ordered.
     */
    @Test
    @DisplayName("a renamed dish moves the shelf under a pad, and the pad is refused")
    void refusesAPadBuiltOnAShelfThatMoved() throws Exception {
        String stale = versionOf(page(aShop(), "en"));
        // The same three dishes, one renamed so it sorts first. Nothing was added or taken away;
        // every position after it now names something else.
        ShopPageFixture renamed = new ShopPageFixture().takesTableOrders()
                .section("Mezze", Item.of("Aa hummus", "1.50"), Item.of("Fattoush", "2.25"))
                .section("Drinks", Item.of("Jallab", "0.75"));

        JsonNode answer = JSON.readTree(quote(renamed, "en", "{\"version\":\"" + stale
                + "\",\"table\":\"7\",\"lines\":[{\"at\":1,\"qty\":2}]}"));

        assertThat(answer.path("stale").asBoolean()).isTrue();
        assertThat(answer.path("ok").asBoolean()).isFalse();
        assertThat(answer.path("lines")).isEmpty();
        assertThat(answer.path("says").get(0).asText()).isEqualTo(
                "This shop’s menu changed, so your order was cleared. "
                        + "Reload the page and start again.");
    }

    @Test
    @DisplayName("a made-up shelf version, and a position off the end of a real one, are both refused")
    void refusesPositionsItCannotResolve() throws Exception {
        ShopPageFixture shop = aShop();

        assertThat(JSON.readTree(quote(shop, "en",
                "{\"version\":\"not-a-shelf\",\"table\":\"7\",\"lines\":[{\"at\":0,\"qty\":1}]}"))
                .path("stale").asBoolean()).isTrue();

        String version = versionOf(page(shop, "en"));
        for (int at : new int[] {9000, -1}) {
            assertThat(JSON.readTree(quote(shop, "en", "{\"version\":\"" + version
                    + "\",\"table\":\"7\",\"lines\":[{\"at\":" + at + ",\"qty\":1}]}"))
                    .path("stale").asBoolean()).isTrue();
        }
    }

    @Test
    @DisplayName("a body with nothing in it, or nonsense in it, is answered rather than swallowed")
    void toleratesAnEmptyOrBrokenBody() throws Exception {
        ShopPageFixture shop = aShop();

        assertThat(JSON.readTree(quote(shop, "en", "{}")).path("stale").asBoolean()).isTrue();
        String version = versionOf(page(shop, "en"));
        // A line with holes in it is skipped rather than guessed at.
        assertThat(JSON.readTree(quote(shop, "en", "{\"version\":\"" + version
                + "\",\"table\":\"7\",\"lines\":[{\"at\":null,\"qty\":2},{\"at\":0,\"qty\":null}]}"))
                .path("lines")).isEmpty();
    }

    /**
     * The caps, which are about a kitchen rather than a database.
     *
     * <p>This endpoint is anonymous and ends as paper in a restaurant, so what one order may ask
     * for is what a table plausibly orders in a round — not what a column could hold.
     */
    @Test
    @DisplayName("one order is bounded: twenty lines, and twenty of any one dish")
    void boundsWhatOneOrderCanAskFor() throws Exception {
        ShopPageFixture shop = new ShopPageFixture().takesTableOrders();
        List<Item> items = new java.util.ArrayList<>();
        for (int i = 0; i < 40; i++) {
            items.add(Item.of("Dish " + (i < 10 ? "0" + i : i), "1.00"));
        }
        shop.section("Everything", items.toArray(Item[]::new));
        String version = versionOf(page(shop, "en"));

        StringBuilder lines = new StringBuilder("[");
        for (int i = 0; i < 40; i++) {
            lines.append(i > 0 ? "," : "").append("{\"at\":").append(i).append(",\"qty\":1}");
        }
        assertThat(JSON.readTree(quote(shop, "en", "{\"version\":\"" + version
                + "\",\"table\":\"7\",\"lines\":" + lines.append(']') + "}")).path("lines"))
                .hasSize(PublicShopPageService.MAX_BASKET_LINES);

        assertThat(JSON.readTree(quote(shop, "en", "{\"version\":\"" + version
                + "\",\"table\":\"7\",\"lines\":[{\"at\":0,\"qty\":1000000}]}"))
                .path("total").asText()).isEqualTo("$20.00");
        assertThat(JSON.readTree(quote(shop, "en", "{\"version\":\"" + version
                + "\",\"table\":\"7\",\"lines\":[{\"at\":0,\"qty\":-5}]}"))
                .path("total").asText()).isEqualTo("$1.00");
    }

    // ---------------------------------------------------------------- who may ask

    /**
     * The refusal is the page's, not a variant of it.
     *
     * <p>A draft shop, a suspended shop and a slug nobody has ever had all have no page, and
     * therefore no pad. Answering any of them differently here would make this endpoint a way to
     * ask whether a shop the platform is hiding exists.
     */
    @Test
    @DisplayName("a shop with no page has no pad, and the refusal is the page's own")
    void refusesEveryShopTheReaderMayNotSee() throws Exception {
        String body = "{\"version\":\"anything\",\"table\":\"7\",\"lines\":[{\"at\":0,\"qty\":1}]}";

        ShopPageFixture draft = new ShopPageFixture(false).section("Mezze",
                Item.of("Hummus", "1.50"));
        ShopPageFixture suspended = aShop().suspended();

        for (ShopPageFixture hidden : List.of(draft, suspended)) {
            MvcResult refused = hidden.mvc()
                    .perform(post("/s/" + hidden.slug() + "/quote")
                            .contentType(MediaType.APPLICATION_JSON).content(body))
                    .andExpect(status().isNotFound()).andReturn();
            assertThat(refused.getResponse().getContentAsString())
                    .contains("This link does not point at a shop on YouDrop.");
        }
        MvcResult nobody = aShop().mvc()
                .perform(post("/s/nothing-is-here-0000ffff/quote")
                        .contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isNotFound()).andReturn();
        assertThat(nobody.getResponse().getContentAsString())
                .contains("This link does not point at a shop on YouDrop.");
    }

    @Test
    @DisplayName("a quote names no id: not a dish's, not a section's, not the shop's")
    void namesNothingThePageDoesNot() throws Exception {
        ShopPageFixture shop = aShop().areas("Hamra");
        String json = quote(shop, "en", "{\"version\":\"" + versionOf(page(shop, "en"))
                + "\",\"table\":\"7\",\"lines\":[{\"at\":0,\"qty\":1},{\"at\":2,\"qty\":1}]}");

        assertThat(json).doesNotContain(shop.shop().getId().toString())
                .doesNotContain(ShopPageFixture.MERCHANT)
                .doesNotContain(ShopPageFixture.SKU)
                .doesNotContain(ShopPageFixture.BARCODE);
        for (String id : shop.productIds()) {
            assertThat(json).doesNotContain(id);
        }
        for (String id : shop.sectionAndAreaIds()) {
            assertThat(json).doesNotContain(id);
        }
    }

    // ---------------------------------------------------------------- the table and the page

    /**
     * A table code changes nothing about the document, and that is the point.
     *
     * <p>The page is memoised per shop per language and served {@code Cache-Control: public}; a
     * rendering that baked a table code in would be one entry per table, and one mistake in the
     * memo key away from handing table 7's page to table 12. The code reaches the script from the
     * address bar and the server only ever sees it in a request body it re-checks.
     */
    @Test
    @DisplayName("a table code changes not one byte of the page, whatever it says")
    void aTableCodeNeverReachesTheDocument() throws Exception {
        ShopPageFixture shop = aShop();
        byte[] plain = shop.mvc().perform(get("/s/" + shop.slug()))
                .andReturn().getResponse().getContentAsByteArray();

        for (String table : List.of("7", "B12", "<script>alert(1)</script>", "../../etc/passwd",
                "‮7", "' or 1=1--", "7\" onmouseover=\"x")) {
            var response = shop.mvc().perform(get("/s/" + shop.slug()).param("t", table))
                    .andExpect(status().isOk()).andReturn().getResponse();
            assertThat(response.getContentAsByteArray())
                    .as("?t=%s renders the same page", table).isEqualTo(plain);
        }
        // The word the script puts the code after is on the page; the code never is.
        assertThat(new String(plain, StandardCharsets.UTF_8))
                .contains("<p class=\"bktab\" hidden data-l=\"Table\"></p>");
    }

    // ---------------------------------------------------------------- how it is served

    /**
     * A quote is never stored anywhere.
     *
     * <p>It is the one answer on this surface that a diner's own choices shaped, and it is about
     * prices and stock as they are this second. A shared cache holding one and handing it to the
     * next reader would be somebody else's order, or this one's at yesterday's prices.
     */
    @Test
    @DisplayName("nothing caches a quote, and it carries the page's own policy and headers")
    void isNeverStored() throws Exception {
        ShopPageFixture shop = aShop();
        var response = shop.mvc()
                .perform(post("/s/" + shop.slug() + "/quote").param("lang", "ar")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"version\":\"" + versionOf(page(shop, "en"))
                                + "\",\"table\":\"7\",\"lines\":[]}"))
                .andExpect(status().isOk()).andReturn().getResponse();

        assertThat(response.getHeader(HttpHeaders.CACHE_CONTROL)).contains("no-store");
        assertThat(response.getContentType()).contains("application/json");
        assertThat(response.getHeader(HttpHeaders.CONTENT_LANGUAGE)).isEqualTo("ar");
        assertThat(response.getHeader(HttpHeaders.VARY)).isEqualTo(HttpHeaders.ACCEPT_LANGUAGE);
        assertThat(response.getHeader("X-Content-Type-Options")).isEqualTo("nosniff");
        assertThat(response.getHeader("Content-Security-Policy")).contains("default-src 'none'");
    }

    /**
     * The one thing the page's policy had to be opened for, and no further.
     *
     * <p>{@code default-src 'none'} was blocking every fetch, which was right while the page had
     * nothing to fetch. It has exactly one request now and it is answered by this service at this
     * origin, so the policy names {@code 'self'} and not an API host — which is also why the
     * endpoint lives under {@code /s/} at all: the page is served on www.youdrop.shop as well, and
     * a call to the API host from there would be cross-origin.
     */
    @Test
    @DisplayName("the policy allows exactly one connection, to this origin")
    void allowsOnlyItsOwnOrigin() throws Exception {
        ShopPageFixture shop = aShop();
        String policy = shop.mvc().perform(get("/s/" + shop.slug()))
                .andReturn().getResponse().getHeader("Content-Security-Policy");

        assertThat(policy).contains("connect-src 'self'").doesNotContain("connect-src *");
        String html = page(shop, "en");
        assertThat(html).contains("data-q=\"/s/" + shop.slug() + "/quote?lang=en\"")
                .doesNotContain("data-q=\"http");
        // The rest of the page still names the one public address, exactly as it always has.
        assertThat(html).contains("<link rel=\"canonical\" href=\"" + shop.url() + "\">");
    }

    @ParameterizedTest(name = "in {0}")
    @ValueSource(strings = {"en", "ar"})
    @DisplayName("the answer is spelled in the language the page was rendered in")
    void answersInTheReadersOwnLanguage(String language) throws Exception {
        JsonNode answer = atTable7(aShop(), language, "[{\"at\":2,\"qty\":2}]");

        if ("ar".equals(language)) {
            // Arabic-Indic digits, the lira in Arabic, and the words in Arabic — the pad is not
            // the one surface on the platform that counts in Latin figures.
            assertThat(answer.path("lines").get(0).path("qty").asText()).isEqualTo("٢×");
            assertThat(answer.path("total").asText()).isEqualTo("١٫٥٠ $");
            assertThat(answer.path("totalLbp").asText()).isEqualTo("١٣٥٬٠٠٠ ل.ل.");
            assertThat(answer.path("count").asText()).isEqualTo("٢ أصناف");
            assertThat(answer.path("totalLabel").asText()).isEqualTo("المجموع");
        } else {
            assertThat(answer.path("lines").get(0).path("qty").asText()).isEqualTo("2×");
            assertThat(answer.path("total").asText()).isEqualTo("$1.50");
            assertThat(answer.path("count").asText()).isEqualTo("2 items");
            assertThat(answer.path("totalLabel").asText()).isEqualTo("Total");
        }
    }

    @Test
    @DisplayName("the pad asks for its figures in the language the page was rendered in")
    void asksForTheRenderingsOwnLanguage() throws Exception {
        ShopPageFixture shop = aShop();

        assertThat(page(shop, "ar")).contains("/quote?lang=ar\"");
        assertThat(page(shop, "en")).contains("/quote?lang=en\"");
    }

    /**
     * The design's receipt says "Total (incl. VAT)". This platform has no VAT, and a table order
     * has no charge of any kind beyond the food.
     */
    @Test
    @DisplayName("nothing on this page claims a tax or a charge the platform does not have")
    void saysNothingAboutVat() throws Exception {
        ShopPageFixture shop = aShop();
        String html = page(shop, "en");
        String json = quote(shop, "en", "{\"version\":\"" + versionOf(html)
                + "\",\"table\":\"7\",\"lines\":[{\"at\":0,\"qty\":4}]}");

        for (String claim : List.of("VAT", VAT_AR, "incl. tax", "Tax", "Service charge")) {
            assertThat(html).as("the page does not mention %s", claim).doesNotContain(claim);
            assertThat(json).as("a quote does not mention %s", claim).doesNotContain(claim);
        }
        assertThat(html).contains(
                "The food, and nothing else. You pay the restaurant at the table, as usual.");
    }

    private static final String VAT_AR = "ضريبة";
}
