package com.delivery.product.shoppage;

import java.nio.charset.StandardCharsets;
import java.util.List;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;

import com.delivery.product.shoppage.ShopPageFixture.Item;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Keeping a shop: what "add to home screen" gets.
 *
 * <p>A regular is not going to search for the same dekkane every week, and this page is the only
 * address they have for it. The manifest is what turns that into a shortcut with the shop's own
 * name and the shop's own logo rather than a page title and whatever icon a browser could scrape.
 */
@DisplayName("keeping a shop on a home screen")
class PublicShopPageManifestTest {

    private static final ObjectMapper JSON = new ObjectMapper();

    private static ShopPageFixture stocked() {
        return new ShopPageFixture().section("Bread", Item.of("Kaak", "1.50"));
    }

    private static MvcResult fetch(ShopPageFixture shop, String language) throws Exception {
        MvcResult result = shop.mvc()
                .perform(get("/s/" + shop.slug() + "/manifest.webmanifest").param("lang", language))
                .andReturn();
        result.getResponse().setCharacterEncoding(StandardCharsets.UTF_8.name());
        return result;
    }

    private static JsonNode manifest(ShopPageFixture shop, String language) throws Exception {
        return JSON.readTree(fetch(shop, language).getResponse().getContentAsString());
    }

    @Test
    @DisplayName("the shop's own name, logo and address, as a manifest")
    void describesTheShop() throws Exception {
        ShopPageFixture shop = stocked();
        MvcResult result = fetch(shop, "en");
        JsonNode manifest = JSON.readTree(result.getResponse().getContentAsString());

        assertThat(result.getResponse().getContentType()).startsWith("application/manifest+json");
        assertThat(manifest.path("name").asText()).isEqualTo("Dekkanet Al Rawche");
        assertThat(manifest.path("description").asText())
                .isEqualTo("Everything the corner shop should have");
        assertThat(manifest.path("id").asText()).isEqualTo(shop.url());
        assertThat(manifest.path("scope").asText()).isEqualTo(shop.url());
        assertThat(manifest.path("start_url").asText()).isEqualTo(shop.url() + "?lang=en");
        assertThat(manifest.path("icons")).hasSize(1);
        assertThat(manifest.path("icons").get(0).path("src").asText())
                .isEqualTo(shop.logoThumbUrl());
    }

    /**
     * A page that opened chromeless would be presenting itself as the shop's app. It cannot take
     * an order, has no account and is five minutes stale by design; keeping the address bar is the
     * honest shape for a document somebody chose to keep.
     */
    @Test
    @DisplayName("it asks to be kept, not installed: the address bar stays")
    void doesNotPretendToBeAnApp() throws Exception {
        assertThat(manifest(stocked(), "en").path("display").asText()).isEqualTo("minimal-ui");
    }

    @ParameterizedTest(name = "in {0}")
    @ValueSource(strings = {"en", "ar"})
    @DisplayName("it carries its own language and direction, and opens in the one that was kept")
    void carriesItsOwnLanguage(String language) throws Exception {
        MvcResult result = fetch(stocked(), language);
        JsonNode manifest = JSON.readTree(result.getResponse().getContentAsString());

        // Drawn by the launcher, outside any page that could have set a direction for it.
        assertThat(manifest.path("lang").asText()).isEqualTo(language);
        assertThat(manifest.path("dir").asText()).isEqualTo("ar".equals(language) ? "rtl" : "ltr");
        assertThat(manifest.path("start_url").asText()).endsWith("?lang=" + language);
        assertThat(result.getResponse().getHeader("Content-Language")).isEqualTo(language);
        assertThat(result.getResponse().getHeader("Vary")).isEqualTo("Accept-Language");
    }

    @Test
    @DisplayName("the page links at the manifest for the rendering the reader is looking at")
    void thePageLinksItByLanguage() throws Exception {
        ShopPageFixture shop = stocked();
        for (String language : List.of("en", "ar")) {
            MvcResult page = shop.mvc().perform(get("/s/" + shop.slug()).param("lang", language))
                    .andReturn();
            page.getResponse().setCharacterEncoding(StandardCharsets.UTF_8.name());

            assertThat(page.getResponse().getContentAsString())
                    .contains("<link rel=\"manifest\" href=\"" + shop.url()
                            + "/manifest.webmanifest?lang=" + language + "\">")
                    // iOS takes its home-screen icon from here rather than from the manifest.
                    .contains("<link rel=\"apple-touch-icon\" href=\"" + shop.logoThumbUrl()
                            + "\">")
                    .contains("<meta name=\"theme-color\" content=\"#E11D48\">");
        }
    }

    @Test
    @DisplayName("a shop with no logo declares no icon, rather than a broken one")
    void noLogoMeansNoIcon() throws Exception {
        ShopPageFixture shop = stocked().withoutArtwork();

        assertThat(manifest(shop, "en").has("icons")).isFalse();
        String page = new String(shop.mvc().perform(get("/s/" + shop.slug()))
                .andReturn().getResponse().getContentAsByteArray(), StandardCharsets.UTF_8);
        assertThat(page).doesNotContain("apple-touch-icon")
                // The manifest itself is still linked: the shop's name is worth keeping without a
                // picture.
                .contains("rel=\"manifest\"");
    }

    @Test
    @DisplayName("it is small enough that keeping a shop costs nothing")
    void itIsTiny() throws Exception {
        assertThat(fetch(stocked(), "en").getResponse().getContentAsByteArray().length)
                .isLessThan(768);
    }

    @Test
    @DisplayName("a shop nobody may see has no manifest either: an icon pointing at a 404")
    void refusedForAShopNobodyMaySee() throws Exception {
        ShopPageFixture hidden = new ShopPageFixture().suspended();
        hidden.mvc().perform(get("/s/" + hidden.slug() + "/manifest.webmanifest"))
                .andExpect(status().isNotFound());

        new ShopPageFixture().mvc()
                .perform(get("/s/a-shop-that-never-existed-0000ffff/manifest.webmanifest"))
                .andExpect(status().isNotFound());
    }

    @Test
    @DisplayName("a browser that fetches it on every page load costs the database one read")
    void itIsBuiltOncePerWindow() throws Exception {
        ShopPageFixture shop = stocked();
        MockMvc mvc = shop.mvc();

        for (int reader = 0; reader < 5; reader++) {
            mvc.perform(get("/s/" + shop.slug() + "/manifest.webmanifest"))
                    .andExpect(status().isOk());
        }

        verify(shop.stores(), times(1)).findBySlug(shop.slug());
        verify(shop.products(), times(1)).findActiveInStore(any(), any(), anyString(), any());
    }
}
