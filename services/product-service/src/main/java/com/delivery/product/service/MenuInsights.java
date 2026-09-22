package com.delivery.product.service;

import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.EnumMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.product.domain.DeliveredOrderLineRepository;
import com.delivery.product.domain.MenuViewDay;
import com.delivery.product.domain.MenuViewDayRepository;
import com.delivery.product.domain.Product;
import com.delivery.product.domain.ProductRepository;
import com.delivery.product.domain.Store;

/**
 * What a shop's menu has been doing: how often it was opened, when in the day, and what came back
 * out of it as an order.
 *
 * <p>The screen behind this (Figma 139:255) asked for six numbers. Three of them the platform can
 * produce honestly, one it can produce only once it is told what it actually means, and two it
 * cannot produce at all. This class is where that line is drawn, so it is worth writing down.
 *
 * <h2>What is answered, and what each number is not</h2>
 *
 * <p><strong>Menu opens.</strong> Counted in {@code menu_view_day} (V44) from the moment that
 * migration is deployed, and not before — there is no backfill because there was nothing to back
 * fill from. It counts REQUESTS THIS SERVICE ANSWERED, which is not the same as people and is not
 * called people anywhere: one reader opening the menu three times is three, and a reader served by
 * their own browser or by a CDN inside the page's five-minute cache window is zero. A link preview
 * and a crawler are one each. It is a trend, and the response says so rather than leaving the
 * screen to infer it.
 *
 * <p><strong>Opens from a table code.</strong> The subset whose address carried {@code ?t=N}. This
 * is the design's "QR scans" and it is deliberately not called that: the shop's own counter QR
 * encodes the page's plain address, so a scan of it is the identical request to a tapped link and
 * no honest arithmetic separates them. Only table cards carry a marker. A shop with no table codes
 * sees zero here and that zero is true.
 *
 * <p><strong>When in the day.</strong> Four parts, never hours — see {@link MenuViewDay.Part} for
 * why the coarseness is doing real work rather than being tidy.
 *
 * <p><strong>Best sellers.</strong> From {@code delivered_order_lines} (V22): real delivered
 * baskets, only DELIVERED ones, with no customer in them. This replaces the design's "most viewed
 * items", which the platform cannot produce and should not pretend to: {@code /s/{slug}} is one
 * server-rendered document containing the whole menu, so every item on it is "viewed" exactly as
 * often as every other, and a per-item view count would mean adding per-item interaction tracking
 * — the finest-grained and most re-identifying thing on the whole screen — in order to fill in a
 * rail. What a shop wanted from that rail is which items earn their place on the menu, and
 * delivered baskets answer that better than views would have.
 *
 * <h2>Why some numbers are rounded and others are exact</h2>
 *
 * <p>The line is whose record it is.
 *
 * <p>Opens are strangers reading a public page. They are nobody's record, so they get the
 * treatment the search log's terms get: nothing is published under a floor, and what is published
 * is rounded DOWN to a band ({@link UnmetDemand#band}) so that the platform never says more than
 * happened and a merchant watching week by week cannot read a change small enough to be one person.
 *
 * <p>Delivered sales are the shop's own trade. The shop took the order, made the thing and handed
 * it over; it already has every one of these numbers on its own receipts, and {@code
 * delivered_order_lines} holds no customer at all. Rounding a shop's own sales would protect
 * nobody and would make the figure useless for the one thing it is for, so best sellers are exact.
 *
 * @see MenuViewRecorder for how opens are counted without writing down an open
 */
@Service
public class MenuInsights {

    /**
     * The fewest opens a window must have before any opens figure is shown at all, and the fewest
     * a part of the day must have before that part shows a number.
     *
     * <p>A constant, not a setting, for the reason {@link UnmetDemand#MIN_PEOPLE} is one.
     *
     * <p>Four times the search log's floor, and higher for a reason rather than out of caution.
     * That floor counts distinct PEOPLE, which it can do because a search carries an account it can
     * key a marker from. An anonymous page open carries nothing, so this floor can only count
     * opens — and five opens can be one person refreshing, where five people cannot be. A floor
     * that one reader can clear alone is not a floor, so it is set where one reader plausibly
     * cannot.
     */
    public static final int MIN_OPENS = 20;

    /** The longest window the screen may ask for, and the default when it asks for nonsense. */
    public static final int MAX_DAYS = 30;
    public static final int DEFAULT_DAYS = 7;

    /** The most items the best-seller list names. The design shows three; the screen may show more. */
    private static final int TOP_ITEMS = 5;

    private final MenuViewDayRepository views;
    private final DeliveredOrderLineRepository lines;
    private final ProductRepository products;
    private final Clock clock;

    public MenuInsights(MenuViewDayRepository views, DeliveredOrderLineRepository lines,
                        ProductRepository products, Clock clock) {
        this.views = views;
        this.lines = lines;
        this.products = products;
        this.clock = clock;
    }

    /**
     * A count as the screen may show it.
     *
     * @param about  the count rounded DOWN to a band, or zero when {@code enough} is false. Never
     *               the count itself
     * @param enough whether the floor was cleared. False is not "no opens" — it is "too few to say
     *               anything about", and the screen must word it that way
     */
    public record Opens(int about, boolean enough) {

        static Opens of(int counted) {
            return counted < MIN_OPENS ? new Opens(0, false)
                    : new Opens(UnmetDemand.band(counted), true);
        }
    }

    /** One quarter of the shop's day, as a bar on the chart. */
    public record PartOfDay(MenuViewDay.Part part, Opens opens) {
    }

    /**
     * One item the shop actually sold in the window.
     *
     * @param baskets how many delivered orders contained it — the ranking figure, because a
     *                customer who bought six in one order is one piece of evidence that the item
     *                sells, not six
     * @param units   how many of it went out in total
     */
    public record Item(UUID productId, String name, long baskets, long units) {
    }

    /**
     * @param opens          every open of the menu in the window
     * @param fromTableCodes the subset that arrived through a table card's code. Not QR scans
     * @param shape          the four parts of the day, in the order a day runs
     * @param bestSellers    what was actually delivered, exact, best first
     * @param countingSince  the first day this shop has any counter for, or null when it has none.
     *                       Lets the screen say "counting started on the 3rd" rather than implying
     *                       a quiet month
     * @param minimumOpens   the floor, so the screen can explain an empty panel instead of drawing
     *                       a zero that looks like a fact
     */
    public record Report(UUID storeId, LocalDate from, LocalDate to, int days,
                         Opens opens, Opens fromTableCodes, List<PartOfDay> shape,
                         List<Item> bestSellers, LocalDate countingSince, int minimumOpens) {
    }

    /**
     * One shop's menu over the last {@code days} of its own calendar.
     *
     * <p>The caller has already decided this shop may be looked at; this reads.
     */
    @Transactional(readOnly = true)
    public Report forStore(Store store, int days) {
        int window = days < 1 ? DEFAULT_DAYS : Math.min(days, MAX_DAYS);
        ZoneId zone = store.zone();
        // The shop's today, not the server's: a merchant in Beirut asking at one in the morning
        // means the day they are still working, and UTC would hand them tomorrow.
        LocalDate today = LocalDate.ofInstant(clock.instant(), zone);
        LocalDate from = today.minusDays(window - 1L);

        List<MenuViewDay> counters = views
                .findByStoreIdAndViewedOnBetweenOrderByViewedOnAsc(store.getId(), from, today);

        int total = 0;
        int table = 0;
        Map<MenuViewDay.Part, Integer> byPart = new EnumMap<>(MenuViewDay.Part.class);
        LocalDate since = null;
        for (MenuViewDay counter : counters) {
            total += counter.getViews();
            if (counter.getSource() == MenuViewDay.Source.TABLE) {
                table += counter.getViews();
            }
            byPart.merge(counter.getDayPart(), counter.getViews(), Integer::sum);
            if (since == null || counter.getViewedOn().isBefore(since)) {
                since = counter.getViewedOn();
            }
        }

        List<PartOfDay> shape = new ArrayList<>();
        for (MenuViewDay.Part part : MenuViewDay.Part.values()) {
            // Each part carries its own floor. Gating only the window total would publish "one
            // open, late on Tuesday" inside a busy month, which is the sentence this whole design
            // is arranged to avoid.
            shape.add(new PartOfDay(part, Opens.of(byPart.getOrDefault(part, 0))));
        }

        return new Report(store.getId(), from, today, window,
                Opens.of(total), Opens.of(table), List.copyOf(shape),
                bestSellers(store.getId(), from, today, zone), since, MIN_OPENS);
    }

    /**
     * What the shop delivered in the window, best first.
     *
     * <p>Exact, and unrounded, because this is the shop's own trade — see the class comment. Empty
     * is the ordinary answer for a shop whose orders all predate V22, since that projection could
     * never be backfilled across the schema boundary.
     */
    private List<Item> bestSellers(UUID storeId, LocalDate from, LocalDate to, ZoneId zone) {
        Instant start = from.atStartOfDay(zone).toInstant();
        Instant until = to.plusDays(1).atStartOfDay(zone).toInstant();
        List<Object[]> rows = lines.topSellersIn(storeId, start, until,
                org.springframework.data.domain.PageRequest.of(0, TOP_ITEMS));
        if (rows.isEmpty()) {
            return List.of();
        }

        Map<UUID, Object[]> byId = new LinkedHashMap<>();
        for (Object[] row : rows) {
            byId.put((UUID) row[0], row);
        }
        Map<UUID, String> names = new LinkedHashMap<>();
        for (Product product : products.findAllById(byId.keySet())) {
            names.put(product.getId(), product.getName());
        }

        List<Item> items = new ArrayList<>();
        byId.forEach((productId, row) -> {
            String name = names.get(productId);
            if (name == null) {
                // Archived or deleted since it was sold. Its sales happened, but a line with no
                // name is not something a merchant can act on, so it is left out rather than shown
                // as a blank row.
                return;
            }
            items.add(new Item(productId, name, ((Number) row[1]).longValue(),
                    ((Number) row[2]).longValue()));
        });
        return List.copyOf(items);
    }
}
