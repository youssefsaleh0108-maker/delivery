package com.delivery.product.shoppage;

import java.nio.charset.StandardCharsets;
import java.util.concurrent.atomic.AtomicLong;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpHeaders;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import com.delivery.product.shoppage.ShopPageFixture.Item;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * {@code GET /s/{slug}/poster}: the sheet a shop tapes to its own counter.
 *
 * <p>Asserted against the bytes, like the page's own tests, because the whole of this feature is
 * the bytes — there is no client to interpret them, only a printer. The two questions that matter
 * are what is printed (a name, a code and an address) and, more importantly, what is <em>not</em>:
 * a poster that carried a price or an opening hour would be wrong within a week and nobody would
 * reprint it.
 */
@DisplayName("the printable shop poster")
class ShopPosterApiTest {

    private static String body(MvcResult result) throws Exception {
        result.getResponse().setCharacterEncoding(StandardCharsets.UTF_8.name());
        return result.getResponse().getContentAsString();
    }

    /** The poster controller over one fixture's shop, on the same base URL the page uses. */
    private static MockMvc mvcOf(ShopPageFixture shop) {
        return MockMvcBuilders
                .standaloneSetup(new ShopPosterController(shop.service(), ShopPageFixture.BASE))
                .build();
    }

    /** A shop with a shelf and a delivery area, so "nothing that goes stale" has something to omit. */
    private static ShopPageFixture stocked() {
        return new ShopPageFixture()
                .areas("Hamra", "Ras Beirut")
                .section("Bread", Item.of("Kaak", "1.50"), Item.of("Markouk", "2.25"));
    }

    // ---------------------------------------------------------------- what it prints

    @Test
    @DisplayName("it prints the shop's name, its QR code and the address in words")
    void printsTheThreeThings() throws Exception {
        ShopPageFixture shop = stocked();
        String html = body(mvcOf(shop).perform(get("/s/" + shop.slug() + "/poster"))
                .andExpect(status().isOk())
                .andReturn());

        assertThat(html)
                .contains("<h1 class=\"name\">Dekkanet Al Rawche</h1>")
                .contains("src=\"/s/" + shop.slug() + "/qr.png\"")
                // Without the scheme: this line exists for the person who types it instead of
                // scanning it, and nobody types "https://".
                .contains("www.youdrop.shop/s/" + shop.slug())
                .doesNotContain("https://www.youdrop.shop/s/");
    }

    @Test
    @DisplayName("the one instruction is printed in both languages, every time")
    void printsBothLanguages() throws Exception {
        ShopPageFixture shop = stocked();

        String english = body(mvcOf(shop).perform(get("/s/" + shop.slug() + "/poster?lang=en"))
                .andReturn());
        String arabic = body(mvcOf(shop).perform(get("/s/" + shop.slug() + "/poster?lang=ar"))
                .andReturn());

        // A counter in Beirut is read by both. Whichever language was asked for, the other is still
        // on the sheet — only the order changes.
        assertThat(english).contains("Order from us on YouDrop").contains("اطلب منّا على YouDrop");
        assertThat(arabic).contains("Order from us on YouDrop").contains("اطلب منّا على YouDrop");
        assertThat(english.indexOf("Order from us")).isLessThan(english.indexOf("اطلب"));
        assertThat(arabic.indexOf("اطلب")).isLessThan(arabic.indexOf("Order from us"));
    }

    @Test
    @DisplayName("nothing on it can go out of date")
    void printsNothingPerishable() throws Exception {
        ShopPageFixture shop = stocked()
                .power(com.delivery.product.domain.Store.PowerStatus.GENERATOR, "until 6",
                        "2026-09-20T14:30:00Z");
        String html = body(mvcOf(shop).perform(get("/s/" + shop.slug() + "/poster")).andReturn());

        assertThat(html)
                // Prices and the shelf.
                .doesNotContain("Kaak").doesNotContain("Markouk")
                .doesNotContain("1.50").doesNotContain("$").doesNotContain("LBP")
                // Hours, and whether it happens to be open as the sheet comes out of the printer.
                .doesNotContain("Open").doesNotContain("Closed").doesNotContain("23:00")
                // Everything else a merchant can change on a Tuesday.
                .doesNotContain("Delivery fee").doesNotContain("Minimum order")
                .doesNotContain("Hamra").doesNotContain("2.5 km")
                .doesNotContain("4.6").doesNotContain("ratings")
                .doesNotContain("generator");
    }

    @Test
    @DisplayName("A5 by default; ?size=a4 lays the bigger paper over it")
    void choosesItsPaper() throws Exception {
        ShopPageFixture shop = stocked();

        String a5 = body(mvcOf(shop).perform(get("/s/" + shop.slug() + "/poster")).andReturn());
        String a4 = body(mvcOf(shop).perform(get("/s/" + shop.slug() + "/poster?size=a4"))
                .andReturn());

        assertThat(a5)
                .contains("<link rel=\"stylesheet\" href=\"/s/assets/poster.css\">")
                .doesNotContain("poster-a4.css")
                .contains("class=\"poster a5\"");
        assertThat(a4)
                .contains("<link rel=\"stylesheet\" href=\"/s/assets/poster.css\">")
                .contains("<link rel=\"stylesheet\" href=\"/s/assets/poster-a4.css\">")
                .contains("class=\"poster a4\"");
    }

    @Test
    @DisplayName("the paper switch keeps the language, and is not printed")
    void paperSwitchKeepsTheLanguage() throws Exception {
        ShopPageFixture shop = stocked();
        String html = body(mvcOf(shop).perform(get("/s/" + shop.slug() + "/poster?lang=ar"))
                .andReturn());

        assertThat(html)
                .contains("/s/" + shop.slug() + "/poster?size=a4&amp;lang=ar")
                // The one already being looked at is marked, not linked.
                .contains("<span class=\"on\">A5</span>")
                .contains("<nav class=\"controls\">");
    }

    @Test
    @DisplayName("Arabic: the sheet is right-to-left, but the address is not")
    void arabicSheetKeepsTheAddressLeftToRight() throws Exception {
        ShopPageFixture shop = stocked();
        String html = body(mvcOf(shop).perform(get("/s/" + shop.slug() + "/poster")
                        .header(HttpHeaders.ACCEPT_LANGUAGE, "ar-LB,ar;q=0.9,en;q=0.5"))
                .andReturn());

        assertThat(html)
                .contains("<html lang=\"ar\" dir=\"rtl\">")
                .contains("<p class=\"line\" lang=\"ar\" dir=\"rtl\">")
                .contains("<p class=\"line\" lang=\"en\" dir=\"ltr\">")
                // A slug typed back from a mirrored address is a different slug.
                .contains("<p class=\"addr\" dir=\"ltr\">www.youdrop.shop/s/" + shop.slug());
    }

    @Test
    @DisplayName("a shop that names itself <script> is printed, not executed")
    void escapesWhatTheMerchantTyped() throws Exception {
        ShopPageFixture shop = stocked()
                .profile("<script>alert(1)</script>", "t", "d", java.util.List.of(), "Ras Beirut");
        String html = body(mvcOf(shop).perform(get("/s/" + shop.slug() + "/poster")).andReturn());

        assertThat(html)
                .doesNotContain("<script")
                .contains("&lt;script&gt;alert(1)&lt;/script&gt;");
    }

    @Test
    @DisplayName("it is a document, not an app: no script, and nothing of the merchant's own")
    void carriesNothingPrivate() throws Exception {
        ShopPageFixture shop = stocked();
        String html = body(mvcOf(shop).perform(get("/s/" + shop.slug() + "/poster")).andReturn());

        assertThat(html)
                .doesNotContain("<script").doesNotContain("javascript:").doesNotContain("onload=")
                .doesNotContain("<style")
                .doesNotContain(ShopPageFixture.MERCHANT)
                .doesNotContain(ShopPageFixture.SKU)
                .doesNotContain(ShopPageFixture.BARCODE)
                .doesNotContain(shop.shop().getId().toString())
                // No artwork from the object store, which is why img-src can be 'self' alone.
                .doesNotContain(ShopPageFixture.IMAGE_ORIGIN);
    }

    // ---------------------------------------------------------------- when there is no page

    @Test
    @DisplayName("a shop with no pin gets the page's own 404, byte for byte")
    void aPinlessShopGetsTheSame404AsThePage() throws Exception {
        ShopPageFixture pinless = stocked().withoutPin();
        MockHttpServletResponse poster = mvcOf(pinless)
                .perform(get("/s/" + pinless.slug() + "/poster"))
                .andExpect(status().isNotFound())
                .andReturn().getResponse();

        MockHttpServletResponse unknown = mvcOf(pinless)
                .perform(get("/s/a-slug-nobody-has-ever-had/poster"))
                .andExpect(status().isNotFound())
                .andReturn().getResponse();

        // The same bytes as a slug that never existed: a poster that refused a real-but-pinless
        // shop differently would answer "does this shop exist" for anybody who asked it.
        //
        // Against the POSTER, not against the page: the poster serves its refusal under its own
        // policy, default-src 'none', which forbids the stylesheet the page's refusal links. The
        // two endpoints answering in their own voice tells a stranger nothing; two answers from
        // THIS endpoint differing would.
        assertThat(poster.getContentAsByteArray()).isEqualTo(unknown.getContentAsByteArray());
        assertThat(new String(poster.getContentAsByteArray(), java.nio.charset.StandardCharsets.UTF_8))
                .doesNotContain("<link rel=\"stylesheet\"");
        assertThat(poster.getHeader("X-Robots-Tag")).isEqualTo("noindex");
        assertThat(poster.getHeader(HttpHeaders.VARY)).isEqualTo(HttpHeaders.ACCEPT_LANGUAGE);
        assertThat(poster.getHeader(HttpHeaders.ETAG)).isNull();
    }

    @Test
    @DisplayName("a draft shop, a suspended shop and an unknown slug are one answer")
    void everyShopWithoutAPageIsRefusedTheSameWay() throws Exception {
        ShopPageFixture draft = new ShopPageFixture(false);
        ShopPageFixture suspended = new ShopPageFixture().suspended();
        ShopPageFixture live = stocked();

        byte[] forDraft = mvcOf(draft).perform(get("/s/" + draft.slug() + "/poster"))
                .andExpect(status().isNotFound()).andReturn().getResponse().getContentAsByteArray();
        byte[] forSuspended = mvcOf(suspended).perform(get("/s/" + suspended.slug() + "/poster"))
                .andExpect(status().isNotFound()).andReturn().getResponse().getContentAsByteArray();
        byte[] forNobody = mvcOf(live).perform(get("/s/nobody/poster"))
                .andExpect(status().isNotFound()).andReturn().getResponse().getContentAsByteArray();

        assertThat(forDraft).isEqualTo(forNobody);
        assertThat(forSuspended).isEqualTo(forNobody);
    }

    // ---------------------------------------------------------------- how it is served

    @Test
    @DisplayName("its own policy, stricter than the page's: one picture, from here")
    void carriesItsOwnContentSecurityPolicy() throws Exception {
        ShopPageFixture shop = stocked();
        MockHttpServletResponse response = mvcOf(shop)
                .perform(get("/s/" + shop.slug() + "/poster")).andReturn().getResponse();

        assertThat(response.getHeader("Content-Security-Policy"))
                .isEqualTo("default-src 'none'; img-src 'self'; style-src 'self'; "
                        + "base-uri 'none'; form-action 'none'; frame-ancestors 'none'");
        assertThat(response.getHeader("X-Content-Type-Options")).isEqualTo("nosniff");
        assertThat(response.getHeader("X-Frame-Options")).isEqualTo("DENY");
        assertThat(response.getHeader("Referrer-Policy"))
                .isEqualTo("strict-origin-when-cross-origin");
        assertThat(response.getHeader("Content-Security-Policy"))
                .doesNotContain(ShopPageFixture.IMAGE_ORIGIN);
    }

    @Test
    @DisplayName("cached like the QR — a year — but still revalidated, because the name can change")
    void cachedLikeTheQrCode() throws Exception {
        ShopPageFixture shop = stocked();
        MockHttpServletResponse first = mvcOf(shop)
                .perform(get("/s/" + shop.slug() + "/poster")).andReturn().getResponse();

        String cacheControl = first.getHeader(HttpHeaders.CACHE_CONTROL);
        assertThat(cacheControl).contains("max-age=31536000").contains("public")
                // The QR is a pure function of a slug that never moves and may say so; this sheet
                // also carries a name that Store.updateProfile can change, and immutable would stop
                // a reload from ever finding that out.
                .doesNotContain("immutable");
        assertThat(first.getHeader(HttpHeaders.CONTENT_LANGUAGE)).isEqualTo("en");
        assertThat(first.getHeader(HttpHeaders.VARY)).isEqualTo(HttpHeaders.ACCEPT_LANGUAGE);

        String tag = first.getHeader(HttpHeaders.ETAG);
        assertThat(tag).isNotNull();
        MockHttpServletResponse again = mvcOf(shop)
                .perform(get("/s/" + shop.slug() + "/poster").header(HttpHeaders.IF_NONE_MATCH, tag))
                .andExpect(status().isNotModified())
                .andReturn().getResponse();
        assertThat(again.getContentAsByteArray()).isEmpty();
        assertThat(again.getHeader("Content-Security-Policy")).isNotNull();
    }

    @Test
    @DisplayName("the two paper sizes are two documents, with two tags")
    void eachPaperHasItsOwnTag() throws Exception {
        ShopPageFixture shop = stocked();
        String a5 = mvcOf(shop).perform(get("/s/" + shop.slug() + "/poster"))
                .andReturn().getResponse().getHeader(HttpHeaders.ETAG);
        String a4 = mvcOf(shop).perform(get("/s/" + shop.slug() + "/poster?size=a4"))
                .andReturn().getResponse().getHeader(HttpHeaders.ETAG);

        assertThat(a5).isNotEqualTo(a4);
    }

    @Test
    @DisplayName("the stylesheets are this build's own bytes: a year, and immutable")
    void servesItsStylesheets() throws Exception {
        MockMvc mvc = mvcOf(stocked());

        for (String path : java.util.List.of("/s/assets/poster.css", "/s/assets/poster-a4.css")) {
            MockHttpServletResponse css = mvc.perform(get(path))
                    .andExpect(status().isOk()).andReturn().getResponse();
            assertThat(css.getContentType()).startsWith("text/css");
            assertThat(css.getHeader(HttpHeaders.CACHE_CONTROL))
                    .contains("max-age=31536000").contains("immutable");
            css.setCharacterEncoding(StandardCharsets.UTF_8.name());
            assertThat(css.getContentAsString()).contains("@page");
        }
    }

    @Test
    @DisplayName("printing the same sheet twice reads the shop once")
    void asecondAskInsideTheWindowReadsNothing() throws Exception {
        ShopPageFixture shop = stocked();
        AtomicLong clock = new AtomicLong();
        MockMvc mvc = MockMvcBuilders.standaloneSetup(
                new ShopPosterController(shop.service(), ShopPageFixture.BASE, clock::get)).build();

        mvc.perform(get("/s/" + shop.slug() + "/poster")).andExpect(status().isOk());
        mvc.perform(get("/s/" + shop.slug() + "/poster")).andExpect(status().isOk());

        // A merchant lining up a print run asks for the same sheet several times in a minute, and
        // building one costs a full page read — six queries and a shelf of products — to print a
        // name and a slug.
        verify(shop.stores(), times(1)).findBySlug(shop.slug());
        verify(shop.products(), times(1)).findActiveInStore(any(), any(), anyString(), any());
    }
}
