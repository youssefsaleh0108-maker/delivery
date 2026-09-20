package com.delivery.product.shoppage;

import java.nio.charset.StandardCharsets;
import java.time.DayOfWeek;
import java.time.LocalTime;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.test.web.servlet.MvcResult;

import com.delivery.product.domain.StoreHours;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;

/**
 * Open or closed <em>now</em>, in the shop's own calendar.
 *
 * <p>The bug this guards against is the one {@code delivery.platform.zone} was introduced for: every
 * shop on dev inherited UTC from a field initialiser, so a Lebanese shop that entered 08:00-23:00
 * was read as open 11:00-02:00 Beirut, and every "is it open" answer on the platform inherited the
 * same three-hour lie. This page is the one a stranger reads with no app to correct it, so each
 * assertion below fixes a single instant and shows the answer changing with the shop's zone and
 * with nothing else.
 */
@DisplayName("a shop page's clock")
class PublicShopPageOpeningTest {

    private static String pageAt(ShopPageFixture shop) throws Exception {
        MvcResult result = shop.mvc().perform(get("/s/" + shop.slug())).andReturn();
        result.getResponse().setCharacterEncoding(StandardCharsets.UTF_8.name());
        return result.getResponse().getContentAsString();
    }

    @Test
    @DisplayName("08:00 in Beirut is open; the same instant read as UTC is not")
    void theShopsOwnZoneDecides() throws Exception {
        // 05:00Z is 08:00 in Beirut (UTC+3 in September) and 05:00 in UTC.
        String beirut = pageAt(new ShopPageFixture()
                .timezone("Asia/Beirut").at("2026-09-20T05:00:00Z"));
        String utc = pageAt(new ShopPageFixture()
                .timezone("UTC").at("2026-09-20T05:00:00Z"));

        assertThat(beirut).contains("Open until 23:00").doesNotContain("Closed now");
        assertThat(utc).contains("Closed now").contains("Opens today at 08:00");
    }

    @Test
    @DisplayName("a shop that trades past midnight is open at half past midnight")
    void openPastMidnight() throws Exception {
        // Friday evening into Saturday morning, stored as the two windows the domain requires: a
        // single window that wrapped midnight would put a special case in every comparison.
        ShopPageFixture lateNight = new ShopPageFixture()
                .timezone("Asia/Beirut")
                .hours(new StoreHours(DayOfWeek.FRIDAY, LocalTime.of(20, 0), LocalTime.of(23, 59)),
                        new StoreHours(DayOfWeek.SATURDAY, LocalTime.of(0, 0), LocalTime.of(2, 0)),
                        new StoreHours(DayOfWeek.SATURDAY, LocalTime.of(20, 0), LocalTime.of(23, 59)))
                // 2026-09-19 is a Saturday; 21:30Z is 00:30 Beirut on Saturday the 19th.
                .at("2026-09-18T21:30:00Z");

        assertThat(pageAt(lateNight))
                .contains("Open until 02:00")
                .contains("00:00–02:00");
    }

    @Test
    @DisplayName("after the late window closes it says when the shop opens again, not just that it is shut")
    void namesTheNextOpening() throws Exception {
        ShopPageFixture lateNight = new ShopPageFixture()
                .timezone("Asia/Beirut")
                .hours(new StoreHours(DayOfWeek.FRIDAY, LocalTime.of(20, 0), LocalTime.of(23, 59)),
                        new StoreHours(DayOfWeek.SATURDAY, LocalTime.of(0, 0), LocalTime.of(2, 0)),
                        new StoreHours(DayOfWeek.SATURDAY, LocalTime.of(20, 0), LocalTime.of(23, 59)))
                // 00:30Z on the 19th is 03:30 Beirut, Saturday: the small window has shut and the
                // evening one has not opened.
                .at("2026-09-19T00:30:00Z");

        assertThat(pageAt(lateNight))
                .contains("Closed now")
                .contains("Opens today at 20:00");
    }

    @Test
    @DisplayName("a shop shut for the rest of the day says tomorrow, not the name of a weekday")
    void opensTomorrow() throws Exception {
        // 20:30Z is 23:30 in Beirut, half an hour after the shop shut and long after its last
        // window could still open. The next one is tomorrow morning.
        ShopPageFixture shop = new ShopPageFixture()
                .timezone("Asia/Beirut").at("2026-09-20T20:30:00Z");

        assertThat(pageAt(shop)).contains("Closed now").contains("Opens tomorrow at 08:00");
    }

    @Test
    @DisplayName("the week is printed in the shop's own calendar, with today marked")
    void printsTheWholeWeek() throws Exception {
        String html = pageAt(new ShopPageFixture()
                .timezone("Asia/Beirut").at("2026-09-20T15:00:00Z"));

        assertThat(html)
                .contains("Monday").contains("Sunday")
                .contains("08:00–23:00")
                .contains("Shop’s own time (Asia/Beirut)")
                // 2026-09-20 is a Sunday, and 18:00 Beirut is still Sunday.
                .contains("<tr class=\"today\"><th scope=\"row\">Sunday");
    }

    @Test
    @DisplayName("a day the shop never opens says so rather than being left blank")
    void namesTheDaysItIsShut() throws Exception {
        ShopPageFixture weekdaysOnly = new ShopPageFixture()
                .timezone("Asia/Beirut")
                .hours(new StoreHours(DayOfWeek.MONDAY, LocalTime.of(9, 0), LocalTime.of(17, 0)))
                .at("2026-09-20T15:00:00Z");

        assertThat(pageAt(weekdaysOnly))
                .contains("09:00–17:00")
                .contains("Closed");
    }

    @Test
    @DisplayName("an unreadable zone degrades one shop's clock instead of failing the page")
    void survivesAZoneNobodyCanParse() throws Exception {
        ShopPageFixture broken = new ShopPageFixture()
                .timezone("Mars/Olympus").at("2026-09-20T05:00:00Z");

        // Falls back to UTC (Store.zone), which at 05:00 is before the 08:00 opening.
        assertThat(pageAt(broken)).contains("Closed now").contains("UTC");
    }
}
