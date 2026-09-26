package com.delivery.product.shoppage;

import java.nio.charset.StandardCharsets;
import java.util.List;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.mockito.ArgumentCaptor;
import org.springframework.data.domain.Pageable;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;

import com.delivery.product.shoppage.ShopPageFixture.Item;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyCollection;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
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

    /**
     * The day a shop opens is the day this page matters most, and it is the day the shop has
     * nothing on its shelf.
     *
     * <p>The catalogue section used to be removed from under such a shop, so its page stopped
     * after the opening hours and a reader was left to guess whether the shop sells nothing,
     * whether the page was broken, or whether they had missed something.
     */
    @ParameterizedTest(name = "in {0}")
    @ValueSource(strings = {"en", "ar"})
    @DisplayName("a shop that has listed nothing yet says so, rather than stopping mid-page")
    void anEmptyShelfSaysSo(String language) throws Exception {
        ShopPageFixture shop = new ShopPageFixture();
        String html = body(shop.mvc().perform(get("/s/" + shop.slug()).param("lang", language))
                .andExpect(status().isOk()).andReturn());

        assertThat(html).contains("class=\"block menu\"").contains("class=\"empty\"");
        if ("ar".equals(language)) {
            assertThat(html).contains("لم يضف هذا المتجر أي صنف بعد.")
                    .contains("أوقات العمل ومناطق التوصيل في الأعلى");
        } else {
            assertThat(html).contains("This shop has not listed anything here yet.")
                    .contains("Its hours and delivery area are above");
        }
        // Nothing to find and nothing to jump to, so neither control is drawn.
        assertThat(html).doesNotContain("class=\"find\"").doesNotContain("class=\"bar\"")
                .doesNotContain("class=\"items");
    }

    /**
     * The way out of the page, and it is still honest about where the web stops.
     *
     * <p>The page used to say it could not take an order at all, and that sentence has gone because
     * it stopped being true: it takes one as far as a priced basket. What it still cannot do is
     * place it — signing in and sending an order are the next piece of work — so the app is still
     * the one way to finish, and the basket's own button says so where a reader is looking when
     * they want it.
     *
     * <p>What has not changed is the part that made this page safe to publish anonymously: nothing
     * on it takes an address, a name or a phone number. The controls that exist are a button on a
     * row, two counters on a basket line, a dead Checkout, and — only where the shop prices by area
     * — a list of the shop's own area names. There is no form, no text field and no way to type
     * anything about yourself into this page at all.
     */
    @Test
    @DisplayName("one way to finish an order: the app, what the button downloads, and no form here")
    void offersOneWayToOrder() throws Exception {
        ShopPageFixture shop = stocked();
        String html = body(shop.mvc().perform(get("/s/" + shop.slug())).andReturn());

        assertThat(html)
                .contains("Orders from this shop are placed in the YouDrop app.")
                .contains("<a class=\"cta\" href=\"https://www.youdrop.shop/app\">Get the app"
                        + "<span class=\"sub\">Android · direct download</span></a>")
                // Room held for the two listings, without a link to either: neither exists, and a
                // dead one on the page a shopkeeper prints on a sign is worse than saying "not
                // yet".
                .contains("<ul class=\"stores\"><li>App Store</li><li>Google Play</li></ul>")
                .contains("Coming soon to the App Store and Google Play.")
                // This shop does not take orders from its tables, so the page says so where the
                // pad would have been rather than leaving a reader to work it out.
                .contains("This shop does not take orders from the table online.");
        assertThat(html)
                .doesNotContain("<form").doesNotContain("<textarea").doesNotContain("<input type")
                .doesNotContain("type=\"tel\"").doesNotContain("type=\"email\"")
                .doesNotContain("type=\"text\"");
        // The only field of any kind is the catalogue search, which submits nowhere.
        assertThat(html.split("<input", -1).length - 1).isEqualTo(1);
    }

    /**
     * It is still a document, not an app.
     *
     * <p>Two {@code <script>} elements on an ordinary shop's page, and neither of them is code the
     * page was handed: the catalogue filter, a file from this origin, and the structured-data block,
     * which carries a JSON media type a browser parses as data and never executes — which is also
     * why {@code script-src 'self'} does not have to allow anything inline for it. Nothing here is
     * inline JavaScript, and there is no handler attribute anywhere. The page is complete before
     * any of them arrives and stays complete if none does, which is what the whole design rests
     * on: a chat app's preview runs no JavaScript at all.
     *
     * <p>The basket's file is the third, and only on a shop that takes orders from its tables. It
     * is 8.8 kB gzipped and the first thing it does on a page with no pad is leave, so a shop that
     * has not turned table ordering on — which is nearly every shop — was downloading all of it to
     * find out it had nothing to do. See {@code ShopPageHtml.head}.
     */
    @Test
    @DisplayName("no inline code: one script file from this origin, one block of data, no basket")
    void carriesNoInlineScript() throws Exception {
        ShopPageFixture shop = stocked();
        String html = body(shop.mvc().perform(get("/s/" + shop.slug())).andReturn());

        // Every script element on the page is one of the two, by name.
        assertThat(html.split("<script", -1).length - 1).isEqualTo(2);
        assertThat(html)
                .contains("<script src=\"/s/assets/shop.js?v=")
                .doesNotContain("basket.js")
                .contains("\" defer></script>")
                .contains("<script type=\"application/ld+json\">")
                .doesNotContain("javascript:")
                .doesNotContain("onerror=")
                .doesNotContain("onload=")
                .doesNotContain("onclick=")
                // One stylesheet, from this origin. No CDN, and no web font to wait on.
                .contains("<link rel=\"stylesheet\" href=\"/s/assets/shop.css?v=")
                .doesNotContain("<style")
                .doesNotContain("fonts.googleapis.com")
                .doesNotContain("cdn.");

        // And the third file, where there is a pad for it to run: same origin, same deferred link.
        ShopPageFixture tables = stocked().takesTableOrders();
        String withPad = body(tables.mvc().perform(get("/s/" + tables.slug())).andReturn());
        assertThat(withPad.split("<script", -1).length - 1).isEqualTo(3);
        assertThat(withPad).contains("<script src=\"/s/assets/basket.js?v=");
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
                .contains("<meta property=\"og:image\" content=\"" + shop.coverThumbUrl() + "\">")
                // The page's own header still takes the cover whole.
                .contains("<img class=\"cover\" src=\"" + shop.coverUrl() + "\"")
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
                .doesNotContain("commission")
                .doesNotContain("statement")
                // The pin. A shop's district is public; the coordinates of the merchant's premises
                // are a different thing, and this page is crawled.
                .doesNotContain("33.8905")
                .doesNotContain("35.4788");
    }

    /**
     * The exact promise about internal ids, which is narrower than "no ids anywhere".
     *
     * <p>An object key is {@code stores/<storeId>/logo/<fileId>.png} and
     * {@code products/<productId>/<fileId>.jpg} ({@code StoreImageService.presign},
     * {@code StorageService.buildObjectKey}), so the store's id and every pictured product's id are
     * inside the page's picture URLs — including {@code og:image}, which is the one a chat app
     * copies into a preview card.
     *
     * <p><strong>That is allowed, deliberately.</strong> They are the same URLs the app already
     * hands any signed-in customer, out of a public bucket, and a UUID on its own grants nothing:
     * every endpoint that takes a store or product id still checks who is asking, and this page
     * refuses an id in place of a slug ({@link #refusesAnIdInPlaceOfASlug}). Proxying every photo
     * through product-service to hide them would put the whole platform's image traffic through a
     * service with ten database connections, for an id a competitor can read off the app in a
     * minute. So the promise is: <em>the page's own markup names no id</em> — not in the title, a
     * link, a tag, a data attribute or a comment — and ids appear only inside the URL of a picture.
     *
     * <p>Asserted by deleting the picture URLs and searching what is left, so the day somebody
     * prints a store id into a link or an {@code id=} attribute, this fails.
     */
    @Test
    @DisplayName("the markup names no internal id; ids live only inside picture URLs")
    void keepsIdsInsidePictureUrls() throws Exception {
        ShopPageFixture shop = stocked();
        String html = body(shop.mvc().perform(get("/s/" + shop.slug())).andReturn());

        // The shape this decision was made about: if the keys ever stop carrying ids, or start
        // carrying something else, this line fails and the decision gets made again.
        assertThat(shop.coverUrl()).contains(shop.shop().getId().toString());
        assertThat(html).contains(shop.coverUrl()).contains(shop.coverThumbUrl());

        String markup = html.replaceAll(
                java.util.regex.Pattern.quote(ShopPageFixture.IMAGE_ORIGIN) + "/product-images/[^\"]*",
                "[picture]");
        assertThat(markup).doesNotContain(shop.shop().getId().toString());
        for (String productId : shop.productIds()) {
            assertThat(markup).doesNotContain(productId);
        }
        // Nor the ids of anything else the page drew: a section is a Category row, an area a
        // DeliveryZone row, and neither has any business being named here.
        for (String otherId : shop.sectionAndAreaIds()) {
            assertThat(html).doesNotContain(otherId);
        }
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

    @Test
    @DisplayName("the QR code asks whether the shop exists; it does not read the shop's shelf")
    void theCodeDoesNotReadThePage() throws Exception {
        ShopPageFixture shop = stocked();
        MockMvc mvc = shop.mvc();

        MvcResult first = mvc.perform(get("/s/" + shop.slug() + "/qr.png"))
                .andExpect(status().isOk()).andReturn();
        MvcResult again = mvc.perform(get("/s/" + shop.slug() + "/qr.png"))
                .andExpect(status().isOk()).andReturn();

        // The whole point: drawing a square never needed the catalogue, and reading it cost this
        // request six queries and up to a hundred and twenty products that were then thrown away.
        verify(shop.products(), never()).findActiveInStore(any(), any(), anyString(), any());
        // One lookup per request — the shop can still be suspended between two scans — and the
        // same bytes, which the memo hands back without encoding a million pixels again.
        verify(shop.stores(), times(2)).findBySlug(shop.slug());
        assertThat(first.getResponse().getContentAsByteArray())
                .isEqualTo(again.getResponse().getContentAsByteArray());
        assertThat(first.getResponse().getHeader("Cache-Control")).contains("immutable");
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
    @DisplayName("a second reader inside the window costs the database nothing, and gets the same bytes")
    void rendersOncePerWindow() throws Exception {
        ShopPageFixture shop = stocked();
        java.util.concurrent.atomic.AtomicLong nanos =
                new java.util.concurrent.atomic.AtomicLong(1_000_000_000L);
        MockMvc mvc = shop.mvc(nanos::get);

        MvcResult first = mvc.perform(get("/s/" + shop.slug())).andExpect(status().isOk())
                .andReturn();
        for (int reader = 0; reader < 9; reader++) {
            mvc.perform(get("/s/" + shop.slug())).andExpect(status().isOk());
        }

        // Ten readers of a link in a group chat, one render. This is what the page's own
        // Cache-Control already promised anybody in front of it; now the origin keeps it too.
        verify(shop.stores(), times(1)).findBySlug(shop.slug());
        verify(shop.products(), times(1)).findActiveInStore(any(), any(), anyString(), any());

        MvcResult tenth = mvc.perform(get("/s/" + shop.slug())).andReturn();
        assertThat(tenth.getResponse().getContentAsByteArray())
                .isEqualTo(first.getResponse().getContentAsByteArray());
        assertThat(tenth.getResponse().getHeader("ETag"))
                .isEqualTo(first.getResponse().getHeader("ETag"));
        // And the ETag still does its job: a phone that already has the page is told so.
        mvc.perform(get("/s/" + shop.slug())
                        .header("If-None-Match", first.getResponse().getHeader("ETag")))
                .andExpect(status().isNotModified());

        // The other language is another page, not the same one handed over twice.
        mvc.perform(get("/s/" + shop.slug()).param("lang", "ar")).andExpect(status().isOk());
        verify(shop.products(), times(2)).findActiveInStore(any(), any(), anyString(), any());

        // Past the five minutes the response advertised, the shop is read again — which is how a
        // corrected price arrives inside the window the merchant was promised.
        nanos.addAndGet(java.time.Duration.ofMinutes(5).toNanos() + 1);
        mvc.perform(get("/s/" + shop.slug())).andExpect(status().isOk());
        verify(shop.products(), times(3)).findActiveInStore(any(), any(), anyString(), any());
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
                // The catalogue filter, and only from here. A merchant who types a script tag
                // into a product name has nowhere for it to run.
                .contains("script-src 'self'")
                // The shop's own manifest, and nothing else: default-src 'none' would block it.
                .contains("manifest-src 'self'")
                .contains("frame-ancestors 'none'")
                .contains("base-uri 'none'")
                .contains("form-action 'none'")
                // The two that would make this a page that could run something it was handed.
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

    /**
     * Both assets are served {@code immutable} for a year, which is right — they are the same
     * bytes for every shop page a reader ever opens — and which is exactly why the address has to
     * move when the bytes do. It did not, so the next release's markup would have been drawn by a
     * returning reader with the last release's stylesheet.
     *
     * <p>Asserted against the served file rather than against a constant: the fingerprint in the
     * link has to be the fingerprint of the bytes behind it, or it is decoration.
     */
    @Test
    @DisplayName("the asset links carry the fingerprint of the bytes they point at")
    void assetLinksMoveWhenTheAssetsDo() throws Exception {
        ShopPageFixture shop = stocked();
        String html = body(shop.mvc().perform(get("/s/" + shop.slug())).andReturn());

        for (String asset : List.of("/s/assets/shop.css", "/s/assets/shop.js")) {
            byte[] served = shop.mvc().perform(get(asset))
                    .andExpect(status().isOk()).andReturn().getResponse().getContentAsByteArray();
            String digest = java.util.Base64.getUrlEncoder().withoutPadding().encodeToString(
                    java.util.Arrays.copyOf(java.security.MessageDigest.getInstance("SHA-256")
                            .digest(served), 16));

            assertThat(html).as("%s is linked with its own fingerprint", asset)
                    .contains(asset + "?v=" + digest.substring(0, 10));
        }
        // The 404 page is drawn by the same stylesheet, so it carries the same link.
        assertThat(body(shop.mvc().perform(get("/s/nothing-is-here-0000ffff")).andReturn()))
                .contains("/s/assets/shop.css?v=");
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
        // Which shops have a page is decided in SQL now and proved against a real database in
        // PublicShopPageDatabaseTest, over a table that really holds a draft, a suspended, a
        // pinless and a closed-category shop. What is checked here is the other half: whatever the
        // query answers is what the file offers, and nothing is added on the way out.
        ShopPageFixture pinless = new ShopPageFixture().withoutPin();
        assertThat(body(pinless.mvc().perform(get("/sitemap.xml")).andReturn()))
                .doesNotContain(pinless.slug());

        ShopPageFixture suspended = new ShopPageFixture().suspended();
        assertThat(body(suspended.mvc().perform(get("/sitemap.xml")).andReturn()))
                .doesNotContain(suspended.slug());
    }

    @Test
    @DisplayName("the sitemap asks the database, capped at the 50,000 a sitemap may hold")
    void sitemapAsksTheDatabaseForOneCappedList() throws Exception {
        ShopPageFixture shop = stocked();
        shop.mvc().perform(get("/sitemap.xml")).andExpect(status().isOk());

        ArgumentCaptor<Pageable> cap = ArgumentCaptor.forClass(Pageable.class);
        verify(shop.stores()).findPublicPageSlugs(anyCollection(), cap.capture());
        // Past 50,000 a crawler rejects the file whole rather than trimming it, so one shop too
        // many would take every other shop's page out of the index with it.
        assertThat(cap.getValue().getPageSize()).isEqualTo(50_000);
        assertThat(cap.getValue().getPageNumber()).isZero();
        // And no stores.findAll(): this read is about every shop there is, and hydrating the table
        // to throw most of it away is the thing that changed.
        verify(shop.stores(), never()).findAll();
    }

    @Test
    @DisplayName("the sitemap is built once an hour, whatever a crawler does in between")
    void sitemapIsBuiltOncePerHour() throws Exception {
        ShopPageFixture shop = stocked();
        java.util.concurrent.atomic.AtomicLong nanos =
                new java.util.concurrent.atomic.AtomicLong(1_000_000_000L);
        MockMvc mvc = shop.mvc(nanos::get);

        MvcResult first = mvc.perform(get("/sitemap.xml")).andExpect(status().isOk()).andReturn();
        for (int crawler = 0; crawler < 5; crawler++) {
            mvc.perform(get("/sitemap.xml")).andExpect(status().isOk());
        }
        verify(shop.stores(), times(1)).findPublicPageSlugs(anyCollection(), any());
        assertThat(body(mvc.perform(get("/sitemap.xml")).andReturn())).isEqualTo(body(first));

        nanos.addAndGet(java.time.Duration.ofHours(1).toNanos() + 1);
        mvc.perform(get("/sitemap.xml")).andExpect(status().isOk());
        verify(shop.stores(), times(2)).findPublicPageSlugs(anyCollection(), any());
    }

    private static List<String> headerNames(MvcResult result) {
        return result.getResponse().getHeaderNames().stream().sorted().toList();
    }
}
