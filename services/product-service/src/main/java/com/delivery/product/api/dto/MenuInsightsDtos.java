package com.delivery.product.api.dto;

import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

import com.delivery.product.service.MenuInsights;

/**
 * What a shop's menu has been doing, as the merchant's screen receives it.
 *
 * <p><strong>What is deliberately not in this response.</strong> No customer, no account, no
 * session, no device, no address, no referrer, and no timestamp — the finest time in it is one of
 * four parts of the shop's own day. Every opens figure is a band ({@code about}) over a floor,
 * never a count, for the reason the Demand Radar's response gives about its own: a number a
 * merchant can watch week by week is a number small changes can be read out of, and small changes
 * can be one person.
 *
 * <p><strong>What is exact, and why that is not an inconsistency.</strong> {@code bestSellers} are
 * the shop's own delivered orders — its receipts, with no customer attached to them anywhere in
 * this service. Rounding those would protect nobody and would make the only actionable figure on
 * the screen useless.
 *
 * <p><strong>What is not here at all.</strong> There is no "QR scans" and no "most viewed items".
 * Neither is a number the platform can produce honestly; see {@link MenuInsights} for what each one
 * would have required. Absent is the right shape for those: a zero would read as "nobody scanned".
 */
public final class MenuInsightsDtos {

    private MenuInsightsDtos() {
    }

    /**
     * A count as the screen may draw it.
     *
     * @param about  the figure rounded DOWN to a round number, or zero when {@code enough} is
     *               false. Never the count itself
     * @param enough whether the floor was cleared. FALSE IS NOT ZERO — it means "too few to say
     *               anything about", and a screen that draws it as a 0 is telling the merchant
     *               something the platform did not say
     */
    public record OpensResponse(int about, boolean enough) {

        static OpensResponse of(MenuInsights.Opens opens) {
            return new OpensResponse(opens.about(), opens.enough());
        }
    }

    /**
     * @param part one of {@code MORNING}, {@code MIDDAY}, {@code EVENING}, {@code NIGHT}, in the
     *             order a day runs. The hours each covers are the server's to decide and the
     *             client's to name, so no times are sent
     */
    public record DayPartResponse(String part, OpensResponse opens) {

        static DayPartResponse of(MenuInsights.PartOfDay part) {
            return new DayPartResponse(part.part().name(), OpensResponse.of(part.opens()));
        }
    }

    /**
     * One item the shop actually delivered in the window.
     *
     * @param baskets how many delivered orders contained it. This is the ranking figure
     * @param units   how many of it went out altogether
     */
    public record BestSellerResponse(UUID productId, String name, long baskets, long units) {

        static BestSellerResponse of(MenuInsights.Item item) {
            return new BestSellerResponse(item.productId(), item.name(), item.baskets(),
                    item.units());
        }
    }

    /**
     * @param fromTableCodes opens whose address carried a table card's parameter. NOT QR scans —
     *                       the shop's counter code carries no marker, so a scan of it and a tapped
     *                       link are the same request and the platform cannot tell them apart
     * @param countingSince  the first day this shop has any counter for, or null when it has none.
     *                       A shop whose page predates the counter must be told "counting started
     *                       here", not shown a quiet month it did not have
     * @param minimumOpens   the floor, so the screen can explain a panel it is not drawing instead
     *                       of drawing a zero that looks like a fact
     * @param bestSellers    exact, and empty for a shop whose delivered orders all predate V22 —
     *                       that projection could never be backfilled across the schema boundary
     */
    public record MenuInsightsResponse(UUID storeId, LocalDate from, LocalDate to, int days,
                                       OpensResponse opens, OpensResponse fromTableCodes,
                                       List<DayPartResponse> shape,
                                       List<BestSellerResponse> bestSellers,
                                       LocalDate countingSince, int minimumOpens) {

        public static MenuInsightsResponse of(MenuInsights.Report report) {
            return new MenuInsightsResponse(report.storeId(), report.from(), report.to(),
                    report.days(),
                    OpensResponse.of(report.opens()),
                    OpensResponse.of(report.fromTableCodes()),
                    report.shape().stream().map(DayPartResponse::of).toList(),
                    report.bestSellers().stream().map(BestSellerResponse::of).toList(),
                    report.countingSince(), report.minimumOpens());
        }
    }
}
