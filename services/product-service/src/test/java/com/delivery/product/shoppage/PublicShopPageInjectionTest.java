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
    private static final String HOSTILE = "<>&\"'</title><script>‮";

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
    private static final String ITEM = "itemname";
    private static final String AREA = "areaname";

    private static final List<String> FIELDS =
            List.of(NAME, TAGLINE, ABOUT, TAG, DISTRICT, POWER, SECTION, ITEM, AREA);

    private static ShopPageFixture hostileShop() {
        return new ShopPageFixture()
                .profile(typed(NAME), typed(TAGLINE), typed(ABOUT), List.of(typed(TAG)),
                        typed(DISTRICT))
                // 14:30Z against the fixture's 15:00Z clock: recent enough that the page draws it.
                .power(Store.PowerStatus.GENERATOR, typed(POWER), "2026-09-20T14:30:00Z")
                .areas(typed(AREA))
                .section(typed(SECTION), Item.of(typed(ITEM), "1.50"));
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
                .doesNotContain("<script")
                .doesNotContain("</title><script")
                .doesNotContain("javascript:")
                .doesNotContain("onerror=")
                // Escaped, it would still be an override where it is drawn. It is dropped instead.
                .doesNotContain("‮")
                .doesNotContain("&#8238;")
                .doesNotContain("&#x202E");
        // One title element, opened and closed once: the head is still the head.
        assertThat(html.split("<title>", -1).length - 1).isEqualTo(1);
        assertThat(html.split("</title>", -1).length - 1).isEqualTo(1);
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
                .contains("<span class=\"n\">" + rendered(ITEM) + "</span>")
                .contains("<p class=\"tagline\">" + rendered(TAGLINE) + "</p>")
                .contains("<p class=\"about\">" + rendered(ABOUT) + "</p>");
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
