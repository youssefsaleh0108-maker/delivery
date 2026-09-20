package com.delivery.product.shoppage;

import java.nio.charset.StandardCharsets;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.test.web.servlet.MvcResult;

import com.delivery.product.shoppage.ShopPageFixture.Item;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;

/**
 * Two currencies, one rate, and the rate is configuration.
 *
 * <p>Every price on this platform is set and settled in dollars; the lira figure beside it is a
 * CONVERSION at one platform-wide rate ({@code delivery.market.lbp-per-usd}) and not a second
 * price anybody chose. The page does the conversion on the server because it runs no JavaScript —
 * whatever a chat app fetches is the whole page — so the rule that lives in the apps'
 * {@code lira.dart} and in {@code MoneyTransfer.lbpFaceOf} has to be the same rule here: round
 * HALF_UP to the nearest 1,000-lira note, because there is no coin to settle a remainder with.
 */
@DisplayName("prices on a shop page")
class PublicShopPagePricesTest {

    private static String pageOf(ShopPageFixture shop) throws Exception {
        MvcResult result = shop.mvc().perform(get("/s/" + shop.slug())).andReturn();
        result.getResponse().setCharacterEncoding(StandardCharsets.UTF_8.name());
        return result.getResponse().getContentAsString();
    }

    private static ShopPageFixture shopAt(String rate) {
        return new ShopPageFixture()
                .lbpPerUsd(rate)
                .section("Bread", Item.of("Kaak", "1.50"), Item.of("Markouk", "3.25"));
    }

    @Test
    @DisplayName("each item shows dollars and lira, converted at the configured rate")
    void showsBothCurrencies() throws Exception {
        String html = pageOf(shopAt("90000"));

        // 1.50 x 90,000 = 135,000 exactly. 3.25 x 90,000 = 292,500, which rounds up to 293,000.
        assertThat(html)
                .contains("$1.50 · 135,000 LBP")
                .contains("$3.25 · 293,000 LBP")
                .contains("lira converted at 90,000 LBP to the dollar");
    }

    @Test
    @DisplayName("moving the rate moves every lira figure on the page")
    void followsTheRate() throws Exception {
        String before = pageOf(shopAt("90000"));
        String after = pageOf(shopAt("130000"));

        assertThat(before).contains("135,000 LBP").doesNotContain("195,000 LBP");
        // 1.50 x 130,000 = 195,000. 3.25 x 130,000 = 422,500, rounded up to 423,000.
        assertThat(after)
                .contains("$1.50 · 195,000 LBP")
                .contains("$3.25 · 423,000 LBP")
                .contains("lira converted at 130,000 LBP to the dollar");
    }

    @Test
    @DisplayName("the delivery fee and the minimum are converted too, not just the shelf")
    void convertsTheDeliveryTermsAsWell() throws Exception {
        assertThat(pageOf(shopAt("90000")))
                // 2.00 and 5.00 at 90,000.
                .contains("Delivery fee $2.00 · 180,000 LBP")
                .contains("Minimum order $5.00 · 450,000 LBP");
    }

    @Test
    @DisplayName("a rate of zero means no lira at all, not a price of zero lira")
    void zeroMeansDoNotShowLira() throws Exception {
        String html = pageOf(shopAt("0"));

        assertThat(html)
                .contains("$1.50")
                .doesNotContain("LBP")
                .doesNotContain("0 LBP")
                .doesNotContain("converted at");
    }
}
