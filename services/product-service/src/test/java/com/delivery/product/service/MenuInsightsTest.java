package com.delivery.product.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import java.math.BigDecimal;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.data.domain.Pageable;

import com.delivery.product.domain.DeliveredOrderLineRepository;
import com.delivery.product.domain.MenuViewDay;
import com.delivery.product.domain.MenuViewDayRepository;
import com.delivery.product.domain.Product;
import com.delivery.product.domain.ProductRepository;
import com.delivery.product.domain.Store;

/**
 * What the Menu Insights screen is allowed to be told.
 *
 * <p>Two rules run through all of it, and they point in opposite directions on purpose.
 *
 * <p>Opens are strangers reading a public page: nothing under {@link MenuInsights#MIN_OPENS} is
 * published at all, and what is published is rounded DOWN, so the platform never says more than
 * happened and a merchant watching week to week cannot read a change small enough to be one person.
 *
 * <p>Delivered sales are the shop's own receipts, with no customer anywhere in them: exact, because
 * rounding them would protect nobody and would spoil the only figure on the screen a shop can act
 * on.
 */
class MenuInsightsTest {

    private static final ZoneId BEIRUT = ZoneId.of("Asia/Beirut");

    private final MenuViewDayRepository views = mock(MenuViewDayRepository.class);
    private final DeliveredOrderLineRepository lines = mock(DeliveredOrderLineRepository.class);
    private final ProductRepository products = mock(ProductRepository.class);

    private MenuInsights insights;
    private Store shop;

    @BeforeEach
    void setUp() {
        Clock clock = Clock.fixed(Instant.parse("2026-09-22T09:00:00Z"), BEIRUT);
        insights = new MenuInsights(views, lines, products, clock);
        // A real shop, not a mock: it assigns its own id and answers its own zone, and the window
        // this class computes is built out of both.
        shop = new Store("merchant-sub", "Boulangerie Antoine", Store.Vertical.GROCERY);
        shop.updateProfile("Boulangerie Antoine", null, null, Store.Vertical.GROCERY, null,
                BEIRUT.getId(), null);
        when(views.findByStoreIdAndViewedOnBetweenOrderByViewedOnAsc(any(), any(), any()))
                .thenReturn(List.of());
        when(lines.topSellersIn(any(), any(), any(), any())).thenReturn(List.of());
    }

    private void counters(MenuViewDay... rows) {
        when(views.findByStoreIdAndViewedOnBetweenOrderByViewedOnAsc(eq(shop.getId()), any(), any()))
                .thenReturn(Arrays.asList(rows));
    }

    private MenuViewDay counter(String day, MenuViewDay.Part part, MenuViewDay.Source source,
                                int count) {
        return new MenuViewDay(shop.getId(), LocalDate.parse(day), part, source, count);
    }

    @Test
    @DisplayName("under the floor nothing is published, and the silence is labelled as a silence")
    void under_the_floor_nothing_is_said() {
        counters(counter("2026-09-21", MenuViewDay.Part.MIDDAY, MenuViewDay.Source.LINK, 19));

        MenuInsights.Report report = insights.forStore(shop, 7);

        // Not "19", and not "0 opens" either: too few to say anything about. A screen that drew
        // this as a zero would be telling the merchant something the platform did not say.
        assertThat(report.opens().enough()).isFalse();
        assertThat(report.opens().about()).isZero();
        assertThat(report.minimumOpens()).isEqualTo(MenuInsights.MIN_OPENS);
    }

    @Test
    @DisplayName("over the floor the figure is a band, rounded down, never the count")
    void over_the_floor_the_figure_is_a_band() {
        counters(counter("2026-09-21", MenuViewDay.Part.MIDDAY, MenuViewDay.Source.LINK, 47));

        MenuInsights.Report report = insights.forStore(shop, 7);

        assertThat(report.opens().enough()).isTrue();
        // 47 said out loud is "about 40": rounded down, so the platform never overstates.
        assertThat(report.opens().about()).isEqualTo(40);
        assertThat(report.opens().about()).isLessThan(47);
    }

    @Test
    @DisplayName("each part of the day carries the floor of its own, not the window's")
    void every_part_carries_its_own_floor() {
        counters(
                counter("2026-09-21", MenuViewDay.Part.MIDDAY, MenuViewDay.Source.LINK, 60),
                // One open, late, inside an otherwise busy week. This is the sentence the whole
                // design is arranged to avoid, and gating only the window total would publish it.
                counter("2026-09-21", MenuViewDay.Part.NIGHT, MenuViewDay.Source.LINK, 1));

        MenuInsights.Report report = insights.forStore(shop, 7);

        assertThat(report.opens().enough()).isTrue();
        MenuInsights.PartOfDay night = report.shape().stream()
                .filter(p -> p.part() == MenuViewDay.Part.NIGHT).findFirst().orElseThrow();
        assertThat(night.opens().enough()).isFalse();
        assertThat(night.opens().about()).isZero();

        MenuInsights.PartOfDay midday = report.shape().stream()
                .filter(p -> p.part() == MenuViewDay.Part.MIDDAY).findFirst().orElseThrow();
        assertThat(midday.opens().enough()).isTrue();
        assertThat(midday.opens().about()).isEqualTo(60);
    }

    @Test
    @DisplayName("the shape is always four parts, in the order a day runs")
    void the_shape_is_the_whole_day() {
        MenuInsights.Report report = insights.forStore(shop, 7);

        assertThat(report.shape()).extracting(MenuInsights.PartOfDay::part)
                .containsExactly(MenuViewDay.Part.MORNING, MenuViewDay.Part.MIDDAY,
                        MenuViewDay.Part.EVENING, MenuViewDay.Part.NIGHT);
    }

    @Test
    @DisplayName("table codes are counted apart, and are a subset of every open")
    void table_codes_are_a_subset() {
        counters(
                counter("2026-09-21", MenuViewDay.Part.MIDDAY, MenuViewDay.Source.TABLE, 30),
                counter("2026-09-21", MenuViewDay.Part.MIDDAY, MenuViewDay.Source.LINK, 40));

        MenuInsights.Report report = insights.forStore(shop, 7);

        assertThat(report.opens().about()).isEqualTo(70);
        assertThat(report.fromTableCodes().about()).isEqualTo(30);
        assertThat(report.fromTableCodes().about()).isLessThan(report.opens().about());
    }

    @Test
    @DisplayName("a shop with no table codes is told zero, and that zero is true")
    void no_table_codes_is_an_honest_zero() {
        counters(counter("2026-09-21", MenuViewDay.Part.MIDDAY, MenuViewDay.Source.LINK, 60));

        MenuInsights.Report report = insights.forStore(shop, 7);

        assertThat(report.fromTableCodes().enough()).isFalse();
        assertThat(report.fromTableCodes().about()).isZero();
    }

    @Test
    @DisplayName("what the shop sold is exact, because it is the shop's own record")
    void best_sellers_are_exact() {
        Product croissant = new Product("merchant-sub", shop.getId(), "Croissant", null,
                new BigDecimal("2.50"), null);
        when(lines.topSellersIn(eq(shop.getId()), any(), any(), any(Pageable.class)))
                .thenReturn(rows(new Object[] {croissant.getId(), 7L, 23L}));
        when(products.findAllById(any())).thenReturn(List.of(croissant));

        MenuInsights.Report report = insights.forStore(shop, 7);

        assertThat(report.bestSellers()).hasSize(1);
        MenuInsights.Item item = report.bestSellers().get(0);
        assertThat(item.name()).isEqualTo("Croissant");
        // Seven baskets, not "about five". A shop has these on its own receipts already, and the
        // table they come from holds no customer at all.
        assertThat(item.baskets()).isEqualTo(7);
        assertThat(item.units()).isEqualTo(23);
    }

    @Test
    @DisplayName("an item sold and since archived is left out, not shown as a blank row")
    void a_nameless_item_is_left_out() {
        UUID gone = UUID.randomUUID();
        when(lines.topSellersIn(eq(shop.getId()), any(), any(), any(Pageable.class)))
                .thenReturn(rows(new Object[] {gone, 4L, 9L}));
        when(products.findAllById(any())).thenReturn(List.of());

        MenuInsights.Report report = insights.forStore(shop, 7);

        assertThat(report.bestSellers()).isEmpty();
    }

    @Test
    @DisplayName("a window longer than the cap is shortened, not refused")
    void the_window_is_clamped() {
        assertThat(insights.forStore(shop, 365).days()).isEqualTo(MenuInsights.MAX_DAYS);
        assertThat(insights.forStore(shop, 0).days()).isEqualTo(MenuInsights.DEFAULT_DAYS);
        assertThat(insights.forStore(shop, -3).days()).isEqualTo(MenuInsights.DEFAULT_DAYS);
    }

    @Test
    @DisplayName("the window is the shop's own days, ending on the shop's today")
    void the_window_is_the_shops_own() {
        // 09:00 UTC on the 22nd is midday in Beirut, so the shop's today is the 22nd and a week
        // reaches back to the 16th.
        MenuInsights.Report report = insights.forStore(shop, 7);

        assertThat(report.to()).isEqualTo(LocalDate.of(2026, 9, 22));
        assertThat(report.from()).isEqualTo(LocalDate.of(2026, 9, 16));
    }

    @Test
    @DisplayName("a shop with no counters yet is told so, rather than shown a quiet month")
    void counting_since_says_a_shop_is_new_to_this() {
        MenuInsights.Report report = insights.forStore(shop, 30);
        assertThat(report.countingSince()).isNull();

        counters(counter("2026-09-20", MenuViewDay.Part.MIDDAY, MenuViewDay.Source.LINK, 25));
        assertThat(insights.forStore(shop, 30).countingSince())
                .isEqualTo(LocalDate.of(2026, 9, 20));
    }

    private static List<Object[]> rows(Object[]... rows) {
        return new ArrayList<>(Arrays.asList(rows));
    }
}
