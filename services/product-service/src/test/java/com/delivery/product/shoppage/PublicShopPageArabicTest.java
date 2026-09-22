package com.delivery.product.shoppage;

import java.nio.charset.StandardCharsets;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;

import com.delivery.product.shoppage.ShopPageFixture.Item;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;

/**
 * The Arabic rendering: right to left, and in the digits the rest of the platform writes.
 *
 * <p>The apps' Arabic strings carry Arabic-Indic numerals literally ({@code "شارع الاختبار ١٢"})
 * and everything interpolated goes through {@code Intl} in {@code ar}, which writes U+0660..U+0669
 * with U+066C between thousands and U+066B before a fraction. This page is the platform's front
 * door for somebody who has never opened the app, so it writes them the same way; Latin digits here
 * would make it the one Arabic surface that did not.
 */
@DisplayName("a shop page in Arabic")
class PublicShopPageArabicTest {

    /** Eastern Arabic-Indic zero through nine. */
    private static final String ARABIC_DIGITS = "٠١٢٣٤٥٦٧٨٩";

    private static ShopPageFixture stocked() {
        return new ShopPageFixture()
                .areas("الحمرا", "المنارة")
                .section("خبز", Item.of("كعك", "1.50"));
    }

    /** The same shop, taking orders from its tables, so the pad is drawn in Arabic too. */
    private static ShopPageFixture withTables() {
        return stocked().takesTableOrders();
    }

    @Test
    @DisplayName("the order pad is Arabic too: its heading, its labels and its one figure")
    void theOrderPadIsArabic() throws Exception {
        ShopPageFixture shop = withTables();
        String html = render(shop, get("/s/" + shop.slug()).param("lang", "ar"));

        assertThat(html)
                .contains("طلبك")
                .contains("يحتاج الطلب من الطاولة إلى JavaScript")
                .contains("ما تطلبه فقط. تدفع للمطعم على الطاولة كالعادة.")
                .contains("أرسل إلى المطبخ")
                .contains("<button class=\"a\" type=\"button\" hidden>أضف</button>")
                .contains("data-l=\"طاولة\"")
                .contains("data-note=\"ملاحظة للمطبخ\"")
                .contains("data-eg=\"بدون بصل\"")
                // The quote is asked for in the language the page was drawn in, so an Arabic menu
                // is never handed an English total.
                .contains("/quote?lang=ar\"");
    }

    private static String render(ShopPageFixture shop, MockHttpServletRequestBuilder request)
            throws Exception {
        MvcResult result = shop.mvc().perform(request).andReturn();
        result.getResponse().setCharacterEncoding(StandardCharsets.UTF_8.name());
        return result.getResponse().getContentAsString();
    }

    @Test
    @DisplayName("?lang=ar draws the page right to left, in Arabic digits")
    void arabicRendersRightToLeft() throws Exception {
        ShopPageFixture shop = stocked();
        String html = render(shop, get("/s/" + shop.slug()).param("lang", "ar"));

        assertThat(html)
                .startsWith("<!doctype html><html lang=\"ar\" dir=\"rtl\">")
                .contains("<meta property=\"og:locale\" content=\"ar_LB\">")
                .contains("أوقات العمل")
                .contains("الاثنين").contains("الأحد")
                .contains("التوصيل")
                .contains("المناطق التي يوصّل إليها")
                .contains("كيف تطلب")
                .contains("حمّل التطبيق")
                // The call to action carries its own second line in Arabic: a reader who switched
                // language should not meet an English button.
                .contains("أندرويد · تحميل مباشر")
                .contains("قريبًا على App Store و Google Play.")
                // This shop has not turned ordering at the table on, so where the pad would have
                // been there is a sentence — in Arabic, like everything else a diner reads here.
                .contains("طلبك")
                .contains("هذا المتجر لا يستقبل الطلبات من الطاولة عبر الإنترنت. اطلب من الموظفين.");

        // The hours, the prices and the rating, in the digits the Arabic app uses.
        assertThat(html)
                .contains("مفتوح حتى ٢٣:٠٠")
                .contains("٠٨:٠٠–٢٣:٠٠")
                // 1.50 dollars, and its 135,000 lira, with the Arabic group and decimal marks.
                .contains("١٫٥٠ $")
                .contains("١٣٥٬٠٠٠ ل.ل.")
                .contains("٤٫٦ من ١٢٨ تقييم")
                .contains("٢٫٥ كم");
    }

    @Test
    @DisplayName("every number the page itself writes is in Arabic digits")
    void arabicUsesNoLatinDigitsInItsNumbers() throws Exception {
        ShopPageFixture shop = stocked();
        String html = render(shop, get("/s/" + shop.slug()).param("lang", "ar"));

        // The three regions the page composes itself. What a merchant typed — a shop's name, its
        // "open since 1974" — is reproduced exactly as they typed it and is deliberately not
        // transliterated, so it is not part of this assertion.
        for (String region : new String[] {
                between(html, "<ul class=\"badges\">", "</ul>"),
                between(html, "<section class=\"block delivery\">", "</section>"),
                between(html, "<section class=\"block hours\">", "</section>")}) {
            String prose = region.replaceAll("<[^>]*>", "");
            assertThat(prose).doesNotContainPattern("[0-9]");
            assertThat(prose).containsPattern("[" + ARABIC_DIGITS + "]");
        }
    }

    private static String between(String html, String open, String close) {
        int from = html.indexOf(open);
        assertThat(from).as("looked for " + open).isGreaterThanOrEqualTo(0);
        int to = html.indexOf(close, from);
        return html.substring(from + open.length(), to);
    }

    @Test
    @DisplayName("English is the default, and it keeps Latin digits")
    void englishKeepsLatinDigits() throws Exception {
        ShopPageFixture shop = stocked();
        String html = render(shop, get("/s/" + shop.slug()));

        assertThat(html)
                .startsWith("<!doctype html><html lang=\"en\" dir=\"ltr\">")
                .contains("Open until 23:00")
                // The dollar figure and the lira it converts to, as the menu's price column draws
                // them: one element each, the lira under the dollars rather than beside them.
                .contains("<span class=\"p\">$1.50<span class=\"l\">135,000 LBP</span></span>");
        assertThat(html.substring(html.indexOf("<body>")).replaceAll("<[^>]*>", ""))
                .doesNotContainPattern("[" + ARABIC_DIGITS + "]");
    }

    @Test
    @DisplayName("Accept-Language picks the language when nobody asked for one")
    void acceptLanguageDecides() throws Exception {
        ShopPageFixture arabicPhone = stocked();
        assertThat(render(arabicPhone, get("/s/" + arabicPhone.slug())
                .header("Accept-Language", "ar-LB,ar;q=0.9,en;q=0.6")))
                .contains("dir=\"rtl\"");

        ShopPageFixture englishPhone = stocked();
        assertThat(render(englishPhone, get("/s/" + englishPhone.slug())
                .header("Accept-Language", "en-GB,en;q=0.9,ar;q=0.5")))
                .contains("dir=\"ltr\"");
    }

    @Test
    @DisplayName("?lang wins over the phone's own setting: it is the one a person chose")
    void theQueryParameterWins() throws Exception {
        ShopPageFixture shop = stocked();
        assertThat(render(shop, get("/s/" + shop.slug())
                .param("lang", "ar")
                .header("Accept-Language", "en-GB,en;q=0.9")))
                .contains("dir=\"rtl\"");

        ShopPageFixture other = stocked();
        assertThat(render(other, get("/s/" + other.slug())
                .param("lang", "en")
                .header("Accept-Language", "ar-LB,ar;q=0.9")))
                .contains("dir=\"ltr\"");
    }

    @Test
    @DisplayName("an opening window keeps its own direction inside an Arabic paragraph")
    void hoursAreNotReorderedByTheParagraph() throws Exception {
        ShopPageFixture shop = stocked();
        // Without dir="ltr" round the pair, a browser lays "08:00-23:00" out as "23:00-08:00" in an
        // RTL paragraph, which is a different pair of hours rather than a cosmetic problem.
        assertThat(render(shop, get("/s/" + shop.slug()).param("lang", "ar")))
                .contains("<span dir=\"ltr\">٠٨:٠٠–٢٣:٠٠</span>");
    }

    /**
     * The other language used to be reachable only by knowing to add {@code ?lang=ar} to the
     * address, or by scrolling a hundred and twenty items to find it in the footer. On the one
     * page a shopkeeper hands to anybody, in a country where the two languages are used
     * interchangeably, that is a control that may as well not exist.
     */
    @Test
    @DisplayName("the language switch is in the header, and carries the direction it switches to")
    void theLanguageSwitchIsVisible() throws Exception {
        ShopPageFixture shop = stocked();

        // Written in the language it switches TO, so it needs that language's own lang and dir:
        // without them a browser reads "العربية" out in an English voice and lays it out with the
        // surrounding paragraph's direction rather than its own.
        assertThat(render(shop, get("/s/" + shop.slug())))
                .contains("<div class=\"head\"><p class=\"lang\"><a rel=\"alternate\" "
                        + "hreflang=\"ar\" lang=\"ar\" dir=\"rtl\" href=\"" + shop.url()
                        + "?lang=ar\">العربية</a></p>");
        assertThat(render(shop, get("/s/" + shop.slug()).param("lang", "ar")))
                .contains("<div class=\"head\"><p class=\"lang\"><a rel=\"alternate\" "
                        + "hreflang=\"en\" lang=\"en\" dir=\"ltr\" href=\"" + shop.url()
                        + "?lang=en\">English</a></p>");
        // And it is in the header now rather than at the foot of the page: one switch, not two.
        assertThat(render(shop, get("/s/" + shop.slug()))
                .split("\\?lang=ar\">العربية</a>", -1).length - 1).isEqualTo(1);
    }

    @Test
    @DisplayName("both languages answer on one URL, and say so")
    void bothRenderingsAreOnePage() throws Exception {
        ShopPageFixture shop = stocked();
        MvcResult arabic = shop.mvc()
                .perform(get("/s/" + shop.slug()).param("lang", "ar")).andReturn();

        assertThat(arabic.getResponse().getHeader("Content-Language")).isEqualTo("ar");
        assertThat(arabic.getResponse().getHeader("Vary")).isEqualTo("Accept-Language");
        arabic.getResponse().setCharacterEncoding(StandardCharsets.UTF_8.name());
        // One canonical, whichever rendering is being read.
        assertThat(arabic.getResponse().getContentAsString())
                .contains("<link rel=\"canonical\" href=\"" + shop.url() + "\">");
    }
}
