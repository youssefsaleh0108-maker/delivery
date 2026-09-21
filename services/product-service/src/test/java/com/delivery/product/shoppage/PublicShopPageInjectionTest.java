package com.delivery.product.shoppage;

import java.nio.charset.StandardCharsets;
import java.util.List;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.test.web.servlet.MvcResult;

import com.delivery.product.domain.Store;
import com.delivery.product.shoppage.ShopPageFixture.Item;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;

/**
 * A shop that writes markup into every field it owns.
 *
 * <p>Every word on this page except the labels is typed by a merchant, and the page is anonymous,
 * cached, crawled and — the part that matters — pasted into chats, where WhatsApp, Facebook and
 * Instagram read the {@code og:} tags out of the head and draw them as a card nobody can inspect.
 * A shop is allowed to call itself {@code </title><script>}, and there is no template engine here
 * that would escape it by default: {@link ShopPageHtml} is a {@code StringBuilder} and one
 * {@code esc} call per value, so the safety of this whole surface is a call somebody has to
 * remember to write.
 *
 * <p>So this test gives one shop a payload in <em>every</em> merchant-typed field — its name,
 * tagline, description, tags, district, power note, a section heading, an item name and a delivery
 * area — each with its own marker, and each carrying the five characters that could write markup, a
 * {@code </title><script>} sequence aimed at breaking out of the head, and a right-to-left override.
 * Then it reads the rendered bytes back: the escaped form must be there, the raw form must be
 * nowhere, in both languages. A marker per field is what makes it a real test — drop {@code esc}
 * from one path and only that field's raw payload appears, which is exactly the assertion that
 * fails.
 */
@DisplayName("a shop that types markup into its own page")
class PublicShopPageInjectionTest {

    /**
     * The five characters that can end an attribute or open a tag, a sequence aimed at closing the
     * title and opening a script in the head, and an override that turns the text after it around.
     */
    private static final String HOSTILE = "<>&\"'</title><script>\u202E";

    /** What the merchant typed, in the field marked {@code marker}. */
    private static String typed(String marker) {
        return marker + HOSTILE;
    }

    /** The bytes that must be on the page instead: escaped, with the override gone. */
    private static String rendered(String marker) {
        return marker + "&lt;&gt;&amp;&quot;&#39;&lt;/title&gt;&lt;script&gt;";
    }

    private static final String NAME = "shopname";
    private static final String TAGLINE = "tagline";
    private static final String ABOUT = "about";
    private static final String TAG = "tagchip";
    private static final String DISTRICT = "district";
    private static final String POWER = "powernote";
    private static final String SECTION = "section";
    private static final String SECTION2 = "secondsection";
    private static final String ITEM = "itemname";
    private static final String ITEM_ABOUT = "itemabout";
    private static final String AREA = "areaname";

    private static final List<String> FIELDS = List.of(NAME, TAGLINE, ABOUT, TAG, DISTRICT, POWER,
            SECTION, SECTION2, ITEM, ITEM_ABOUT, AREA);

    /**
     * Two sections, because a section name is now typed onto the page twice.
     *
     * <p>It was only a heading. It is now also a chip on the bar that follows the reader down the
     * menu — a second path onto the page for a value the merchant typed, and one the bar only draws
     * for a shop with more than one section. A hostile shop with a single aisle would never have
     * rendered it, and this test would have passed over the new path without touching it.
     */
    private static ShopPageFixture hostileShop() {
        return new ShopPageFixture()
                .profile(typed(NAME), typed(TAGLINE), typed(ABOUT), List.of(typed(TAG)),
                        typed(DISTRICT))
                // 14:30Z against the fixture's 15:00Z clock: recent enough that the page draws it.
                .power(Store.PowerStatus.GENERATOR, typed(POWER), "2026-09-20T14:30:00Z")
                .areas(typed(AREA))
                .section(typed(SECTION),
                        Item.of(typed(ITEM), "1.50").describedAs(typed(ITEM_ABOUT)))
                .section(typed(SECTION2), Item.of("Plain second item", "2.50"));
    }

    private static String page(String language) throws Exception {
        return render(hostileShop(), language);
    }

    private static String render(ShopPageFixture shop, String language) throws Exception {
        MvcResult result = shop.mvc()
                .perform(get("/s/" + shop.slug()).param("lang", language)).andReturn();
        result.getResponse().setCharacterEncoding(StandardCharsets.UTF_8.name());
        return result.getResponse().getContentAsString();
    }

    @ParameterizedTest(name = "in {0}")
    @ValueSource(strings = {"en", "ar"})
    @DisplayName("every merchant-typed field arrives escaped, and none of them raw")
    void escapesEveryFieldInEveryLanguage(String language) throws Exception {
        String html = page(language);

        for (String field : FIELDS) {
            assertThat(html)
                    .as("%s is on the page, escaped", field)
                    .contains(rendered(field))
                    .as("%s is not on the page as the merchant typed it", field)
                    .doesNotContain(typed(field));
        }
    }

    @ParameterizedTest(name = "in {0}")
    @ValueSource(strings = {"en", "ar"})
    @DisplayName("nothing a merchant typed became markup: no script, no second title, no override")
    void writesNoMarkupOfTheMerchantsOwn(String language) throws Exception {
        String html = page(language);

        assertThat(html)
                // The page's own two: the filter this service serves, and a block of data. A
                // merchant's "</title><script>" must not become a third.
                .contains("<script src=\"/s/assets/shop.js?v=")
                .contains("<script type=\"application/ld+json\">")
                .doesNotContain("</title><script")
                .doesNotContain("javascript:")
                .doesNotContain("onerror=")
                // Escaped, it would still be an override where it is drawn. It is dropped instead.
                .doesNotContain("\u202E")
                .doesNotContain("&#8238;")
                .doesNotContain("&#x202E");
        // One title element, opened and closed once: the head is still the head. And exactly the
        // page's own two script elements, no more.
        assertThat(html.split("<title>", -1).length - 1).isEqualTo(1);
        assertThat(html.split("</title>", -1).length - 1).isEqualTo(1);
        assertThat(html.split("<script", -1).length - 1).isEqualTo(2);
    }

    @Test
    @DisplayName("the head a chat app reads: title, Open Graph and Twitter all carry escaped bytes")
    void escapesWhatTheChatAppsRead() throws Exception {
        String html = page("en");
        String title = rendered(NAME) + " — " + rendered(DISTRICT) + " · YouDrop";

        assertThat(html)
                .contains("<title>" + title + "</title>")
                .contains("<meta property=\"og:title\" content=\"" + title + "\">")
                .contains("<meta name=\"twitter:title\" content=\"" + title + "\">")
                // The tagline is this page's description everywhere a description is asked for.
                .contains("<meta name=\"description\" content=\"" + rendered(TAGLINE) + "\">")
                .contains("<meta property=\"og:description\" content=\"" + rendered(TAGLINE) + "\">")
                .contains("<meta name=\"twitter:description\" content=\"" + rendered(TAGLINE)
                        + "\">")
                // An attribute whose value is the shop's own name, in the head, next to the picture.
                .contains("<meta property=\"og:image:alt\" content=\"" + rendered(NAME) + "\">");
    }

    @Test
    @DisplayName("the body: heading, district, badges, tags, areas, section and item")
    void escapesWhatTheReaderSees() throws Exception {
        String html = page("en");

        assertThat(html)
                .contains("<h1>" + rendered(NAME) + "</h1>")
                .contains(" · " + rendered(DISTRICT) + "</p>")
                .contains(rendered(POWER))
                .contains("<li>" + rendered(TAG) + "</li>")
                .contains("<li>" + rendered(AREA) + "</li>")
                .contains("<h3>" + rendered(SECTION) + "</h3>")
                .contains("<h3>" + rendered(SECTION2) + "</h3>")
                .contains("<span class=\"n\">" + rendered(ITEM) + "</span>")
                // Inside the row that expands, which is a second path onto the page for text the
                // merchant typed — and one <details> the payload must not have closed.
                .contains("<p class=\"d\">" + rendered(ITEM_ABOUT) + "</p></details>")
                .contains("<p class=\"tagline\">" + rendered(TAGLINE) + "</p>")
                .contains("<p class=\"about\">" + rendered(ABOUT) + "</p>");
    }

    /**
     * The bar that follows the reader, which is the newest place a merchant's text is printed.
     *
     * <p>A chip is the section's own name inside an anchor, and the bar's label is a string of the
     * page's own — so both go through {@code esc}, and the chip's payload must not have closed the
     * anchor, opened a tag, or turned the rest of the bar round. The {@code href} beside it is
     * built from a counter and can carry nothing a merchant typed at all.
     */
    @ParameterizedTest(name = "in {0}")
    @ValueSource(strings = {"en", "ar"})
    @DisplayName("the bar's chips carry escaped section names, and the bar is still a bar")
    void escapesTheSectionBar(String language) throws Exception {
        String html = page(language);

        assertThat(html)
                .contains("<a href=\"#s1\">" + rendered(SECTION) + "</a>")
                .contains("<a href=\"#s2\">" + rendered(SECTION2) + "</a>")
                .doesNotContain(typed(SECTION))
                .doesNotContain(typed(SECTION2));
        // One nav, opened and closed once, with exactly the two anchors it meant to have: a
        // section called "</a><a href=..." must not have added a third.
        assertThat(html.split("<nav class=\"bar\"", -1).length - 1).isEqualTo(1);
        assertThat(html.split("</nav>", -1).length - 1).isEqualTo(1);
        String bar = html.substring(html.indexOf("<nav class=\"bar\""), html.indexOf("</nav>"));
        assertThat(bar.split("<a ", -1).length - 1).isEqualTo(2);
        assertThat(bar).doesNotContain("<script").doesNotContain("‮");
    }

    @Test
    @DisplayName("the shop cannot rewrite the links on its own page either")
    void doesNotReachTheLinks() throws Exception {
        ShopPageFixture shop = hostileShop();
        String html = render(shop, "en");

        // Every URL on the page is built from the configured base and the slug, and the slug was
        // minted from the name the shop opened with — renaming it cannot move the page.
        assertThat(html)
                .contains("<link rel=\"canonical\" href=\"" + shop.url() + "\">")
                .contains("<meta property=\"og:url\" content=\"" + shop.url() + "\">")
                .contains("href=\"" + shop.url() + "/qr.png\"");
        assertThat(shop.slug()).startsWith("dekkanet-al-rawche-");
    }

    /**
     * The structured data, which is the one part of this page that is not markup.
     *
     * <p>A second escaper, a second set of rules, and every one of the same values going through
     * it. {@code &amp;quot;} is six literal characters to a JSON parser rather than a quote mark,
     * a backslash means nothing in HTML and ends a string in JSON, and the block sits inside an
     * HTML document where {@code </script>} closes it whatever the JSON says. So this asks a real
     * parser, on a shop that typed all of it: the block must still be one JSON object, the shop's
     * name must come back out of it exactly as the merchant typed it, and the page must still have
     * only the two script elements it wrote itself.
     */
    @ParameterizedTest(name = "in {0}")
    @ValueSource(strings = {"en", "ar"})
    @DisplayName("the structured data is still JSON a crawler can parse, and still says only this")
    void keepsTheStructuredDataParseable(String language) throws Exception {
        String html = page(language);

        var data = PublicShopPageStructuredDataTest.structuredData(html);

        // Out of the parser, the merchant's own characters — not entities, and not a truncated
        // string that stopped at the first quote mark they typed.
        assertThat(data.path("name").asText()).isEqualTo(typed(NAME).replace("‮", ""));
        assertThat(data.path("address").path("addressLocality").asText())
                .isEqualTo(typed(DISTRICT).replace("‮", ""));
        assertThat(data.path("areaServed").get(0).path("name").asText())
                .isEqualTo(typed(AREA).replace("‮", ""));
        var aisle = data.path("hasOfferCatalog").path("itemListElement").get(0);
        assertThat(aisle.path("name").asText()).isEqualTo(typed(SECTION).replace("‮", ""));
        assertThat(aisle.path("itemListElement").get(0).path("itemOffered").path("name").asText())
                .isEqualTo(typed(ITEM).replace("‮", ""));

        // And none of it wrote a tag on the way in: the block is closed by this page's own
        // </script>, and the page still has exactly the two script elements it meant to have.
        assertThat(html.split("<script", -1).length - 1).isEqualTo(2);
        assertThat(html.split("</script>", -1).length - 1).isEqualTo(2);
    }

    @Test
    @DisplayName("the sitemap is XML a crawler can parse, whatever the shop calls itself")
    void keepsTheSitemapWellFormed() throws Exception {
        ShopPageFixture shop = hostileShop();
        MvcResult result = shop.mvc().perform(get("/sitemap.xml")).andReturn();
        result.getResponse().setCharacterEncoding(StandardCharsets.UTF_8.name());
        String xml = result.getResponse().getContentAsString();

        assertThat(xml).contains("<loc>" + shop.url() + "</loc>").doesNotContain("<script");
        // Parsed rather than pattern-matched: a sitemap that does not parse is a sitemap Google
        // drops whole, and this is the one document on the page's surface that must be XML.
        javax.xml.parsers.DocumentBuilderFactory factory =
                javax.xml.parsers.DocumentBuilderFactory.newInstance();
        factory.setFeature("http://apache.org/xml/features/disallow-doctype-decl", true);
        assertThat(factory.newDocumentBuilder()
                .parse(new java.io.ByteArrayInputStream(xml.getBytes(StandardCharsets.UTF_8)))
                .getDocumentElement().getTagName())
                .isEqualTo("urlset");
    }
}
