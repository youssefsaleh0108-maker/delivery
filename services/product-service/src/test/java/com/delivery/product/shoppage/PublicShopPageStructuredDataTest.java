package com.delivery.product.shoppage;

import java.nio.charset.StandardCharsets;
import java.time.LocalTime;
import java.util.ArrayList;
import java.util.List;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
import org.junit.jupiter.params.provider.ValueSource;

import com.delivery.product.domain.Store;
import com.delivery.product.domain.StoreHours;
import com.delivery.product.shoppage.ShopPageFixture.Item;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;

/**
 * What a search engine is told, and the promise that it is not one word more than the page shows.
 *
 * <p>This is how a shop appears when somebody types its name into Google instead of following a
 * link: a panel with the hours, whether it is open, and what it sells. The head's Open Graph tags
 * have always done the equivalent for chat apps.
 *
 * <p>Parsed here rather than pattern-matched. Structured data that does not parse is structured
 * data a search engine drops whole, and the block is assembled by hand from values a merchant
 * typed — so the question "is it still valid JSON after this shop named itself {@code "}" has to
 * be asked of a parser. {@link PublicShopPageInjectionTest} asks it of a hostile shop.
 */
@DisplayName("what the page tells a search engine")
class PublicShopPageStructuredDataTest {

    private static final ObjectMapper JSON = new ObjectMapper();

    private static final String OPEN = "<script type=\"application/ld+json\">";

    static String rendered(ShopPageFixture shop, String language) throws Exception {
        var result = shop.mvc().perform(get("/s/" + shop.slug()).param("lang", language))
                .andReturn();
        result.getResponse().setCharacterEncoding(StandardCharsets.UTF_8.name());
        return result.getResponse().getContentAsString();
    }

    /** The one block, taken out of the page exactly as a crawler's parser would take it. */
    static JsonNode structuredData(String html) throws Exception {
        assertThat(html.split(java.util.regex.Pattern.quote(OPEN), -1).length - 1)
                .as("exactly one structured-data block")
                .isEqualTo(1);
        String block = html.substring(html.indexOf(OPEN) + OPEN.length());
        block = block.substring(0, block.indexOf("</script>"));
        // The block ends where the first </script> does. If a merchant's text had written one,
        // this substring would be truncated JSON and the parse below would fail — which is the
        // assertion, not a side effect of it.
        return JSON.readTree(block);
    }

    private static JsonNode of(ShopPageFixture shop, String language) throws Exception {
        return structuredData(rendered(shop, language));
    }

    private static ShopPageFixture stocked() {
        return new ShopPageFixture()
                .areas("Hamra", "Ras Beirut")
                .section("Bread", Item.of("Kaak", "1.50"), Item.of("Markouk", "2.25"))
                .section("Cold drinks", Item.of("Laban ayran", "0.75").outOfStock());
    }

    // ---------------------------------------------------------------- the business

    @Test
    @DisplayName("the shop, as schema.org understands one")
    void describesTheBusiness() throws Exception {
        ShopPageFixture shop = stocked();
        JsonNode data = of(shop, "en");

        assertThat(data.path("@context").asText()).isEqualTo("https://schema.org");
        assertThat(data.path("@type").asText()).isEqualTo("GroceryStore");
        assertThat(data.path("@id").asText()).isEqualTo(shop.url() + "#shop");
        assertThat(data.path("name").asText()).isEqualTo("Dekkanet Al Rawche");
        assertThat(data.path("url").asText()).isEqualTo(shop.url());
        assertThat(data.path("inLanguage").asText()).isEqualTo("en");
        assertThat(data.path("description").asText())
                .isEqualTo("Everything the corner shop should have");
        assertThat(data.path("image").asText()).isEqualTo(shop.coverUrl());
        assertThat(data.path("logo").asText()).isEqualTo(shop.logoThumbUrl());
        assertThat(data.path("keywords").asText()).isEqualTo("grocery, dekkane");
        assertThat(data.path("address").path("@type").asText()).isEqualTo("PostalAddress");
        assertThat(data.path("address").path("addressLocality").asText()).isEqualTo("Ras Beirut");
        assertThat(data.path("areaServed")).hasSize(2);
        assertThat(data.path("areaServed").get(0).path("name").asText()).isEqualTo("Hamra");
    }

    @ParameterizedTest(name = "{0} is a {1}")
    @CsvSource({"RESTAURANT,Restaurant", "COFFEE,CafeOrCoffeeShop", "GROCERY,GroceryStore",
        "CONVENIENCE,ConvenienceStore", "PHARMACY,Pharmacy", "ELECTRONICS,ElectronicsStore",
        "FLOWERS_GIFTS,Florist"})
    @DisplayName("the vertical the page names in its first line is the type a crawler is given")
    void everyVerticalHasItsType(Store.Vertical vertical, String type) throws Exception {
        ShopPageFixture shop = new ShopPageFixture(vertical);

        assertThat(of(shop, "en").path("@type").asText()).isEqualTo(type);
    }

    @Test
    @DisplayName("a service shop is a LocalBusiness unless schema.org has a real type for it")
    void serviceShopsAreNotGuessedAt() throws Exception {
        assertThat(of(new ShopPageFixture(Store.ServiceCategory.BEAUTY), "en")
                .path("@type").asText()).isEqualTo("BeautySalon");
        // schema.org has no printer and no tutor, and picking the nearest-looking type would be
        // telling a search engine something about the shop that is not true.
        assertThat(of(new ShopPageFixture(Store.ServiceCategory.PRINTING), "en")
                .path("@type").asText()).isEqualTo("LocalBusiness");
        assertThat(of(new ShopPageFixture(Store.ServiceCategory.TAILORING), "en")
                .path("@type").asText()).isEqualTo("LocalBusiness");
    }

    @Test
    @DisplayName("the rating in the badge is the rating in the data")
    void carriesTheRating() throws Exception {
        JsonNode rating = of(stocked(), "en").path("aggregateRating");

        assertThat(rating.path("@type").asText()).isEqualTo("AggregateRating");
        assertThat(rating.path("ratingValue").asText()).isEqualTo("4.6");
        assertThat(rating.path("reviewCount").asInt()).isEqualTo(128);
        assertThat(rating.path("bestRating").asText()).isEqualTo("5");
    }

    @Test
    @DisplayName("a shop nobody has rated claims no rating, which is not a rating of zero")
    void anUnratedShopClaimsNoRating() throws Exception {
        assertThat(of(stocked().noRating(), "en").has("aggregateRating")).isFalse();
    }

    // ---------------------------------------------------------------- the week

    @Test
    @DisplayName("seven identical days are one specification, not seven")
    void groupsTheDaysThatShareTheirHours() throws Exception {
        JsonNode week = of(stocked(), "en").path("openingHoursSpecification");

        assertThat(week).hasSize(1);
        assertThat(week.get(0).path("@type").asText()).isEqualTo("OpeningHoursSpecification");
        assertThat(week.get(0).path("opens").asText()).isEqualTo("08:00");
        assertThat(week.get(0).path("closes").asText()).isEqualTo("23:00");
        List<String> days = new ArrayList<>();
        week.get(0).path("dayOfWeek").forEach(day -> days.add(day.asText()));
        assertThat(days).containsExactly("Monday", "Tuesday", "Wednesday", "Thursday", "Friday",
                "Saturday", "Sunday");
    }

    @Test
    @DisplayName("a split day is two specifications, and a day off is simply absent")
    void splitsAndClosedDays() throws Exception {
        ShopPageFixture shop = stocked().hours(
                new StoreHours(java.time.DayOfWeek.MONDAY, LocalTime.of(8, 0), LocalTime.of(13, 0)),
                new StoreHours(java.time.DayOfWeek.MONDAY, LocalTime.of(16, 0), LocalTime.of(20, 0)),
                new StoreHours(java.time.DayOfWeek.TUESDAY, LocalTime.of(8, 0), LocalTime.of(13, 0)),
                new StoreHours(java.time.DayOfWeek.TUESDAY, LocalTime.of(16, 0), LocalTime.of(20, 0)));
        JsonNode week = of(shop, "en").path("openingHoursSpecification");

        assertThat(week).hasSize(2);
        assertThat(week.get(0).path("opens").asText()).isEqualTo("08:00");
        assertThat(week.get(0).path("closes").asText()).isEqualTo("13:00");
        assertThat(week.get(1).path("opens").asText()).isEqualTo("16:00");
        assertThat(week.get(1).path("closes").asText()).isEqualTo("20:00");
        // Monday and Tuesday keep the same pair of windows, so each window names both days once.
        for (JsonNode window : week) {
            List<String> days = new ArrayList<>();
            window.path("dayOfWeek").forEach(day -> days.add(day.asText()));
            assertThat(days).containsExactly("Monday", "Tuesday");
        }
    }

    @Test
    @DisplayName("a shop whose hours were cleared claims none, rather than claiming it never opens")
    void noHoursMeansNoSpecification() throws Exception {
        assertThat(of(stocked().hours(), "en").has("openingHoursSpecification")).isFalse();
    }

    /**
     * The hours are in the vocabulary's own format in both renderings: Latin digits, 24-hour.
     * The Arabic reader is shown ٠٨:٠٠ two sections up the page, and it is the same hour — this is
     * a field a machine parses, not text a person reads.
     */
    @ParameterizedTest(name = "in {0}")
    @ValueSource(strings = {"en", "ar"})
    @DisplayName("times and prices stay machine-readable whichever language the page is in")
    void machineFieldsAreLanguageIndependent(String language) throws Exception {
        JsonNode data = of(stocked(), language);

        assertThat(data.path("openingHoursSpecification").get(0).path("opens").asText())
                .isEqualTo("08:00");
        assertThat(data.path("priceRange").asText()).isEqualTo("$0.75-$2.25");
        assertThat(firstOffer(data).path("price").asText()).isEqualTo("1.50");
        // But the language it is being read in is declared, and so are the words a person wrote.
        assertThat(data.path("inLanguage").asText()).isEqualTo(language);
    }

    // ---------------------------------------------------------------- the shelf

    private static JsonNode firstOffer(JsonNode data) {
        return data.path("hasOfferCatalog").path("itemListElement").get(0)
                .path("itemListElement").get(0);
    }

    @Test
    @DisplayName("the shelf is an offer catalogue: the aisles the page draws, with their rows")
    void describesTheShelf() throws Exception {
        JsonNode catalogue = of(stocked(), "en").path("hasOfferCatalog");

        assertThat(catalogue.path("@type").asText()).isEqualTo("OfferCatalog");
        assertThat(catalogue.path("name").asText()).isEqualTo("What they sell");
        assertThat(catalogue.path("itemListElement")).hasSize(2);

        JsonNode bread = catalogue.path("itemListElement").get(0);
        assertThat(bread.path("name").asText()).isEqualTo("Bread");
        assertThat(bread.path("itemListElement")).hasSize(2);

        JsonNode kaak = bread.path("itemListElement").get(0);
        assertThat(kaak.path("@type").asText()).isEqualTo("Offer");
        assertThat(kaak.path("itemOffered").path("@type").asText()).isEqualTo("Product");
        assertThat(kaak.path("itemOffered").path("name").asText()).isEqualTo("Kaak");
        assertThat(kaak.path("price").asText()).isEqualTo("1.50");
        assertThat(kaak.path("priceCurrency").asText()).isEqualTo("USD");
        assertThat(kaak.path("availability").asText()).isEqualTo("https://schema.org/InStock");

        JsonNode gone = catalogue.path("itemListElement").get(1).path("itemListElement").get(0);
        assertThat(gone.path("availability").asText()).isEqualTo("https://schema.org/OutOfStock");
    }

    @Test
    @DisplayName("the price range and the currency come off the shelf above, not from anywhere else")
    void thePriceRangeIsDerived() throws Exception {
        assertThat(of(stocked(), "en").path("priceRange").asText()).isEqualTo("$0.75-$2.25");
        assertThat(of(stocked(), "en").path("currenciesAccepted").asText()).isEqualTo("USD, LBP");
        // At a rate of zero the page prints no lira, so the data must not claim any either.
        assertThat(of(stocked().lbpPerUsd("0"), "en").path("currenciesAccepted").asText())
                .isEqualTo("USD");
        // One item is a range of one.
        assertThat(of(new ShopPageFixture().section("Bread", Item.of("Kaak", "1.50")), "en")
                .path("priceRange").asText()).isEqualTo("$1.50");
    }

    @Test
    @DisplayName("a shop with nothing on the shelf claims no catalogue, no range and no currency")
    void anEmptyShelfClaimsNothing() throws Exception {
        JsonNode data = of(new ShopPageFixture(), "en");

        assertThat(data.has("hasOfferCatalog")).isFalse();
        assertThat(data.has("priceRange")).isFalse();
        assertThat(data.has("currenciesAccepted")).isFalse();
        // The shop itself is still described: it exists, it has hours, and it is somewhere.
        assertThat(data.path("name").asText()).isEqualTo("Dekkanet Al Rawche");
    }

    // ---------------------------------------------------------------- and nothing more

    /**
     * The rule the whole block is held to.
     *
     * <p>Structured data that claims more than the page shows is what a search engine calls spam,
     * and on this page it would also be the one place a shop's private details could reach a
     * public document without a reader ever seeing them go.
     */
    @Test
    @DisplayName("it carries nothing the page does not show, and nothing the page refuses to show")
    void saysNothingThePageDoesNot() throws Exception {
        ShopPageFixture shop = stocked();
        String html = rendered(shop, "en");
        JsonNode data = structuredData(html);

        // The pin, a phone number, an email, an owner: none of these is on the page, and none of
        // them may appear here — this block is the easy place to leak one.
        for (String forbidden : List.of("telephone", "geo", "email", "founder", "employee",
                "openingHours", "hasMap", "paymentAccepted", "taxID", "vatID")) {
            assertThat(data.has(forbidden)).as("%s is not on this page", forbidden).isFalse();
        }
        assertThat(data.toString())
                .doesNotContain("33.8905").doesNotContain("35.4788")
                .doesNotContain(ShopPageFixture.MERCHANT)
                .doesNotContain(ShopPageFixture.SKU)
                .doesNotContain(ShopPageFixture.BARCODE);

        // And every name it does carry is a name the reader can see above it.
        String visible = html.substring(0, html.indexOf(OPEN));
        List<JsonNode> names = new ArrayList<>();
        data.findValues("name").forEach(names::add);
        assertThat(names).hasSizeGreaterThan(5);
        for (JsonNode name : names) {
            assertThat(visible).as("\"%s\" is on the page too", name.asText())
                    .contains(name.asText());
        }
    }

    @Test
    @DisplayName("a 404 tells a crawler nothing at all")
    void theRefusalCarriesNoData() throws Exception {
        var refusal = new ShopPageFixture().mvc()
                .perform(get("/s/a-shop-that-never-existed-0000ffff")).andReturn();
        refusal.getResponse().setCharacterEncoding(StandardCharsets.UTF_8.name());

        assertThat(refusal.getResponse().getContentAsString()).doesNotContain("ld+json");
    }
}
