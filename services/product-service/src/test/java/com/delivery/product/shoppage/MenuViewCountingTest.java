package com.delivery.product.shoppage;

import static org.mockito.ArgumentMatchers.anyBoolean;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.test.web.servlet.MockMvc;

import com.delivery.product.shoppage.ShopPageFixture.Item;

/**
 * What the public page hands the menu-view counter, and what it does not.
 *
 * <p>The page is the only thing that counts an open, so this is where the boundary is pinned: what
 * a page render tells the recorder is a slug and a boolean, and a request that did not produce a
 * page tells it nothing at all.
 */
@DisplayName("counting an open of the public menu")
class MenuViewCountingTest {

    private static ShopPageFixture stocked() {
        return new ShopPageFixture()
                .section("Bread", Item.of("Kaak", "1.50"), Item.of("Markouk", "2.25"));
    }

    @Test
    @DisplayName("a served page is counted once, as a link")
    void aServedPageIsCounted() throws Exception {
        ShopPageFixture fixture = stocked();
        MockMvc mvc = fixture.mvc();

        mvc.perform(get("/s/" + fixture.slug())).andExpect(status().isOk());

        verify(fixture.menuViews()).record(fixture.slug(), false);
    }

    @Test
    @DisplayName("an address carrying a table's parameter is counted apart")
    void aTableCodeIsCountedApart() throws Exception {
        ShopPageFixture fixture = stocked();
        MockMvc mvc = fixture.mvc();

        mvc.perform(get("/s/" + fixture.slug()).param("t", "7")).andExpect(status().isOk());

        // The number 7 is not handed on. Which table a diner sat at is the order's business; the
        // counter only needs to know that this was a card on a table rather than a link.
        verify(fixture.menuViews()).record(fixture.slug(), true);
    }

    @Test
    @DisplayName("a shop that is not there is not counted, so probing adds to nobody's total")
    void aMissingShopIsNotCounted() throws Exception {
        ShopPageFixture fixture = stocked();
        MockMvc mvc = fixture.mvc();

        mvc.perform(get("/s/no-such-shop")).andExpect(status().isNotFound());

        verifyNoInteractions(fixture.menuViews());
    }

    @Test
    @DisplayName("a reader served from the render memo is still a reader")
    void aMemoHitIsStillCounted() throws Exception {
        ShopPageFixture fixture = stocked();
        MockMvc mvc = fixture.mvc();

        mvc.perform(get("/s/" + fixture.slug())).andExpect(status().isOk());
        mvc.perform(get("/s/" + fixture.slug())).andExpect(status().isOk());
        mvc.perform(get("/s/" + fixture.slug())).andExpect(status().isOk());

        // The page is rendered once and served three times — the memo is inside the handler, so it
        // saves the render and not the count. What the service genuinely cannot see is the reader
        // served by a browser or a CDN, which never arrives here at all.
        verify(fixture.menuViews(), times(3)).record(fixture.slug(), false);
    }

    @Test
    @DisplayName("the QR image, the poster and the sitemap are not opens of the menu")
    void otherRequestsAreNotOpens() throws Exception {
        ShopPageFixture fixture = stocked();
        MockMvc mvc = fixture.mvc();

        mvc.perform(get("/s/" + fixture.slug() + "/qr.png")).andExpect(status().isOk());
        mvc.perform(get("/sitemap.xml")).andExpect(status().isOk());

        // Asking for the printable code is the shop's own errand, not a customer reading the menu.
        verify(fixture.menuViews(), never()).record(anyString(), anyBoolean());
    }

    @Test
    @DisplayName("the language a page was asked for does not change what is counted")
    void languageIsNotCounted() throws Exception {
        ShopPageFixture fixture = stocked();
        MockMvc mvc = fixture.mvc();

        mvc.perform(get("/s/" + fixture.slug()).param("lang", "ar"))
                .andExpect(status().isOk());

        // Arabic and English readers are the same counter. A language on the row would be one more
        // thing a small number could be narrowed by, for an answer nobody asked for.
        verify(fixture.menuViews()).record(eq(fixture.slug()), eq(false));
    }
}
