package com.delivery.product.shoppage;

import java.nio.charset.StandardCharsets;
import java.util.List;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.test.web.servlet.MvcResult;

import com.delivery.product.shoppage.ShopPageFixture.Item;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * {@code GET /s/{slug}}: what a stranger, a crawler and WhatsApp's link preview get.
 *
 * <p>Every assertion here is made against the bytes the controller writes, not against a model.
 * The page's whole reason for existing is that the first response is already complete — a chat app
 * building a preview runs no JavaScript — so a test that inspected a view model rather than the
 * markup would pass while the shared link showed a blank card.
 */
@DisplayName("the public shop page")
class PublicShopPageApiTest {

    private static String body(MvcResult result) throws Exception {
        result.getResponse().setCharacterEncoding(StandardCharsets.UTF_8.name());
        return result.getResponse().getContentAsString();
    }

    private static ShopPageFixture stocked() {
        return new ShopPageFixture()
                .areas("Hamra", "Ras Beirut", "Manara")
                .section("Bread", Item.of("Kaak", "1.50"), Item.of("Markouk", "2.25"))
                .section("Cold drinks", Item.of("Laban ayran", "0.75").outOfStock());
    }

    // ---------------------------------------------------------------- it renders

    @Test
    @DisplayName("a live shop renders everything a customer needs to decide")
    void liveShopRenders() throws Exception {
        ShopPageFixture shop = stocked();
        String html = body(shop.mvc().perform(get("/s/" + shop.slug()))
                .andExpect(status().isOk())
                .andReturn());

        assertThat(html)
                .contains("Dekkanet Al Rawche")
                .contains("Ras Beirut")
                .contains("Grocery")
                .contains("Verified local shop")
                .contains("4.6 from 128 ratings")
                // 15:00Z is 18:00 in Beirut, and the shop shuts at 23:00 its own time.
                .contains("Open until 23:00")
                .contains("Delivers within 2.5 km")
                .contains("20-40 min")
                .contains("Hamra").contains("Manara")
                .contains("Bread").contains("Kaak").contains("Markouk")
                .contains("Cold drinks").contains("Laban ayran")
                .contains("Out of stock")
                .contains("Opening hours")
                .contains("Asia/Beirut")
                .contains("Get the app")
                .contains("/qr.png");
    }

    @Test
    @DisplayName("it is a document, not an app: no script of any kind")
    void carriesNoScript() throws Exception {
        ShopPageFixture shop = stocked();
        String html = body(shop.mvc().perform(get("/s/" + shop.slug())).andReturn());

        assertThat(html)
                .doesNotContain("<script")
                .doesNotContain("javascript:")
                .doesNotContain("onerror=")
                .doesNotContain("onload=")
                // One stylesheet, from this origin. No CDN, and no web font to wait on.
                .contains("<link rel=\"stylesheet\" href=\"/s/assets/shop.css\">")
                .doesNotContain("<style")
                .doesNotContain("fonts.googleapis.com")
                .doesNotContain("cdn.");
    }

    @Test
    @DisplayName("the markup a chat app reads: Open Graph, Twitter and one canonical URL")
    void carriesTheSharingTags() throws Exception {
        ShopPageFixture shop = stocked();
        String html = body(shop.mvc().perform(get("/s/" + shop.slug())).andReturn());

        assertThat(html)
                .contains("<link rel=\"canonical\" href=\"" + shop.url() + "\">")
                .contains("<meta property=\"og:type\" content=\"website\">")
                .contains("<meta property=\"og:site_name\" content=\"YouDrop\">")
                .contains("<meta property=\"og:url\" content=\"" + shop.url() + "\">")
                .contains("<meta property=\"og:title\" content=\"Dekkanet Al Rawche — Ras Beirut · YouDrop\">")
                // The derivative, not the merchant's 4 MB original: a chat app that cannot fetch
                // the picture inside its budget shows the blank card this page exists to avoid.
                .contains("<meta property=\"og:image\" content=\""
                        + ShopPageFixture.IMAGE_ORIGIN + "/product-images/stores/cover_thumb.jpg\">")
                // The page's own header still takes the cover whole.
                .contains("<img class=\"cover\" src=\""
                        + ShopPageFixture.IMAGE_ORIGIN + "/product-images/stores/cover.jpg\"")
                .contains("<meta property=\"og:locale\" content=\"en_US\">")
                .contains("<meta name=\"twitter:card\" content=\"summary_large_image\">")
                .contains("<title>Dekkanet Al Rawche — Ras Beirut · YouDrop</title>")
                .contains("<meta name=\"description\" content=\"")
                // Both renderings of the one page, so a search engine indexes one shop, not two.
                .contains("hreflang=\"ar\" href=\"" + shop.url() + "?lang=ar\"")
                .contains("hreflang=\"en\" href=\"" + shop.url() + "?lang=en\"");
    }

    @Test
    @DisplayName("the canonical URL is the configured public one, not the host the request arrived on")
    void canonicalIgnoresTheRequestHost() throws Exception {
        ShopPageFixture shop = stocked();
        String html = body(shop.mvc()
                .perform(get("/s/" + shop.slug()).header("Host", "product-service.internal:8103"))
                .andReturn());

        assertThat(html)
                .contains("<link rel=\"canonical\" href=\"https://www.youdrop.shop/s/"
                        + shop.slug() + "\">")
                .doesNotContain("product-service.internal");
    }

    // ---------------------------------------------------------------- what a competitor reads

    @Test
    @DisplayName("nothing a merchant-only endpoint returns reaches the page")
    void carriesNoMerchantData() throws Exception {
        ShopPageFixture shop = stocked();
        String html = body(shop.mvc().perform(get("/s/" + shop.slug())).andReturn());

        assertThat(html)
                // The owner. A Keycloak sub identifies a person to anybody who can ask Keycloak.
                .doesNotContain(ShopPageFixture.MERCHANT)
                .doesNotContain("merchantId")
                // The merchant's own item codes, off /api/products.
                .doesNotContain(ShopPageFixture.SKU)
                .doesNotContain(ShopPageFixture.BARCODE)
                // Internal identifiers. The slug is the public name of this shop; the id is not,
                // and an id in the markup is a key into every other endpoint.
                .doesNotContain(shop.shop().getId().toString())
                .doesNotContain("commission")
                .doesNotContain("statement")
                // The pin. A shop's district is public; the coordinates of the merchant's premises
                // are a different thing, and this page is crawled.
                .doesNotContain("33.8905")
                .doesNotContain("35.4788");
    }

    // ---------------------------------------------------------------- the one refusal

    @Test
    @DisplayName("draft, suspended, pinless and never-existed are the same 404, byte for byte")
    void everyRefusalLooksTheSame() throws Exception {
        ShopPageFixture draftShop = new ShopPageFixture(false);
        MvcResult draft = draftShop.mvc().perform(get("/s/" + draftShop.slug())).andReturn();
        ShopPageFixture suspendedShop = new ShopPageFixture().suspended();
        MvcResult suspended = suspendedShop.mvc()
                .perform(get("/s/" + suspendedShop.slug())).andReturn();
        ShopPageFixture pinlessShop = new ShopPageFixture().withoutPin();
        MvcResult pinless = pinlessShop.mvc()
                .perform(get("/s/" + pinlessShop.slug())).andReturn();
        MvcResult unknown = new ShopPageFixture().mvc()
                .perform(get("/s/a-shop-that-never-existed-0000ffff")).andReturn();

        List<MvcResult> refusals = List.of(draft, suspended, pinless, unknown);
        for (MvcResult refusal : refusals) {
            assertThat(refusal.getResponse().getStatus()).isEqualTo(404);
            assertThat(body(refusal)).isEqualTo(body(unknown));
            assertThat(headerNames(refusal)).isEqualTo(headerNames(unknown));
            // Nothing that would let somebody tell the four apart.
            assertThat(refusal.getResponse().getHeader("ETag")).isNull();
            assertThat(refusal.getResponse().getHeader("X-Robots-Tag")).isEqualTo("noindex");
            assertThat(refusal.getResponse().getHeader("Vary")).isEqualTo("Accept-Language");
        }
        assertThat(body(unknown))
                .doesNotContain("Dekkanet")
                .doesNotContain("draft").doesNotContain("suspended").doesNotContain("pin");
    }

    @Test
    @DisplayName("a shop's id is not a second address for its page")
    void refusesAnIdInPlaceOfASlug() throws Exception {
        ShopPageFixture shop = stocked();
        shop.mvc().perform(get("/s/" + shop.shop().getId()))
                .andExpect(status().isNotFound());
    }

    @Test
    @DisplayName("a QR code is refused for a shop nobody may see: a sign pointing at a 404")
    void refusesTheCodeForAShopNobodyMaySee() throws Exception {
        ShopPageFixture hidden = new ShopPageFixture().suspended();
        hidden.mvc().perform(get("/s/" + hidden.slug() + "/qr.png"))
                .andExpect(status().isNotFound());
    }

    // ---------------------------------------------------------------- caching and headers

    @Test
    @DisplayName("public for five minutes, with an ETag that makes the re-check free")
    void cachesForAFewMinutesAndRevalidates() throws Exception {
        ShopPageFixture shop = stocked();
        MvcResult first = shop.mvc().perform(get("/s/" + shop.slug()))
                .andExpect(status().isOk()).andReturn();

        String cacheControl = first.getResponse().getHeader("Cache-Control");
        assertThat(cacheControl).contains("public").contains("max-age=300");
        String etag = first.getResponse().getHeader("ETag");
        assertThat(etag).isNotBlank();
        assertThat(first.getResponse().getHeader("Vary")).isEqualTo("Accept-Language");
        assertThat(first.getResponse().getHeader("Content-Language")).isEqualTo("en");

        MvcResult again = shop.mvc()
                .perform(get("/s/" + shop.slug()).header("If-None-Match", etag))
                .andExpect(status().isNotModified()).andReturn();
        assertThat(again.getResponse().getContentAsByteArray()).isEmpty();
        assertThat(again.getResponse().getHeader("ETag")).isEqualTo(etag);
    }

    @Test
    @DisplayName("a price change is visible within the cache window, and moves the ETag")
    void theEtagFollowsThePage() throws Exception {
        ShopPageFixture before = stocked();
        ShopPageFixture after = new ShopPageFixture()
                .areas("Hamra", "Ras Beirut", "Manara")
                .section("Bread", Item.of("Kaak", "1.75"), Item.of("Markouk", "2.25"))
                .section("Cold drinks", Item.of("Laban ayran", "0.75").outOfStock());

        String firstTag = before.mvc().perform(get("/s/" + before.slug()))
                .andReturn().getResponse().getHeader("ETag");
        String secondTag = after.mvc().perform(get("/s/" + after.slug()))
                .andReturn().getResponse().getHeader("ETag");

        assertThat(secondTag).isNotEqualTo(firstTag);
    }

    @Test
    @DisplayName("the page carries its own policy, allowing the stylesheet and the pictures and nothing else")
    void carriesItsOwnContentSecurityPolicy() throws Exception {
        ShopPageFixture shop = stocked();
        MockHttpServletResponse response = shop.mvc()
                .perform(get("/s/" + shop.slug())).andReturn().getResponse();

        String policy = response.getHeader("Content-Security-Policy");
        assertThat(policy)
                .contains("default-src 'none'")
                .contains("style-src 'self'")
                .contains("img-src 'self' " + ShopPageFixture.IMAGE_ORIGIN)
                .contains("frame-ancestors 'none'")
                .contains("base-uri 'none'")
                .contains("form-action 'none'")
                // The three that would make this a page that could run or leak something.
                .doesNotContain("script-src")
                .doesNotContain("unsafe-inline")
                .doesNotContain("unsafe-eval");
        assertThat(response.getHeader("X-Content-Type-Options")).isEqualTo("nosniff");
        assertThat(response.getHeader("X-Frame-Options")).isEqualTo("DENY");
    }

    @Test
    @DisplayName("the stylesheet is served from this origin and cached for a year")
    void servesItsOwnStylesheet() throws Exception {
        MvcResult css = new ShopPageFixture().mvc().perform(get("/s/assets/shop.css"))
                .andExpect(status().isOk()).andReturn();

        assertThat(css.getResponse().getContentType()).startsWith("text/css");
        assertThat(css.getResponse().getHeader("Cache-Control"))
                .contains("max-age=31536000").contains("immutable");
        assertThat(body(css)).contains("--brand").contains(".items");
    }

    // ---------------------------------------------------------------- the sitemap

    @Test
    @DisplayName("the sitemap lists the pages that exist, with both languages as alternates")
    void sitemapListsLiveShops() throws Exception {
        ShopPageFixture shop = stocked();
        MvcResult result = shop.mvc().perform(get("/sitemap.xml"))
                .andExpect(status().isOk()).andReturn();

        assertThat(result.getResponse().getContentType()).contains("xml");
        assertThat(body(result))
                .contains("<urlset")
                .contains("<loc>" + shop.url() + "</loc>")
                .contains("hreflang=\"ar\"")
                .contains("hreflang=\"en\"");
        assertThat(result.getResponse().getHeader("Cache-Control")).contains("max-age=3600");
    }

    @Test
    @DisplayName("a shop with no page is not offered to a crawler either")
    void sitemapLeavesOutWhatWouldBeA404() throws Exception {
        ShopPageFixture pinless = new ShopPageFixture().withoutPin();
        assertThat(body(pinless.mvc().perform(get("/sitemap.xml")).andReturn()))
                .doesNotContain(pinless.slug());

        ShopPageFixture suspended = new ShopPageFixture().suspended();
        assertThat(body(suspended.mvc().perform(get("/sitemap.xml")).andReturn()))
                .doesNotContain(suspended.slug());
    }

    private static List<String> headerNames(MvcResult result) {
        return result.getResponse().getHeaderNames().stream().sorted().toList();
    }
}
