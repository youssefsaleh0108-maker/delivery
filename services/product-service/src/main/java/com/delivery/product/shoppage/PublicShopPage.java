package com.delivery.product.shoppage;

import java.math.BigDecimal;
import java.time.LocalTime;
import java.util.List;

import com.delivery.product.domain.Store;

/**
 * Everything the public shop page draws, already resolved.
 *
 * <p>A value, not a {@link Store}. Two reasons, and both have bitten this service before. The
 * renderer runs after the transaction has closed, so anything lazy — the week's hours above all —
 * would throw {@code LazyInitializationException} the moment it were touched (see
 * {@code StoreService.StoreView}). And this page is read by strangers: making the whole model an
 * explicit list of fields means <em>adding</em> a field to it is a deliberate act, rather than
 * something that happens by accident the next time a column is added to {@code stores}. Nothing
 * here can carry a merchant id, a commission or a phone number, because there is nowhere to put
 * one.
 *
 * <p>Times are kept as {@link LocalTime} and money as {@link BigDecimal}: this is the shop's own
 * calendar and the shop's own prices, and how they are spelled is the renderer's business, which
 * is the only part that knows which language the reader asked for.
 */
public record PublicShopPage(
        String slug,
        String name,
        String tagline,
        String description,
        /** Absolute URL of the shop's logo, or null. Always the list-sized derivative. */
        String logoUrl,
        /** Absolute URL of the cover at full size, or null. The page's own header image. */
        String coverUrl,
        /**
         * The same cover at 320 px on the long edge, or null — what the {@code og:image} names.
         *
         * <p>Not the full-size one, and the difference matters on the surface this page exists for.
         * A chat app fetches and re-encodes the preview picture itself, under a hard size budget of
         * a few hundred kilobytes, and a merchant may upload a 4 MB photo from a phone: over the
         * budget the card comes back with no picture at all, which is the blank card this whole
         * design is meant to prevent. The page's own header keeps the full-size image, because a
         * browser streams it and it never blocks the text.
         *
         * <p>Falls back to the full-size URL when no derivative was ever generated
         * ({@code ProductImageService.resolveImages}), so an old cover still previews.
         */
        String coverThumbUrl,
        String neighbourhood,
        List<String> tags,
        boolean verifiedLocal,
        /** Null when nobody has rated the shop — which is not a rating of zero. */
        BigDecimal rating,
        int ratingCount,
        Store.Vertical vertical,
        /** What a SERVICES shop does; null for every goods shop. */
        Store.ServiceCategory serviceCategory,
        Opening opening,
        /** Null unless the merchant said what the lights are doing, recently enough to mean now. */
        Power power,
        Delivery delivery,
        Catalogue catalogue) {

    /**
     * Whether the shop is open <em>right now</em>, in its own calendar, and the week behind that
     * answer.
     *
     * @param timezone  the shop's zone id, shown to the reader so a visitor abroad knows whose
     *                  clock these times are on
     * @param openNow   {@code Store.availabilityAt} at the instant the page was built
     * @param closesAt  when the current window ends; null when the shop is closed
     * @param next      the next window that opens; null when the week names none at all
     * @param week      seven days, Monday first, each with the windows it has — empty for a day the
     *                  shop never opens
     * @param todayIso  ISO day number of today in the shop's zone (1 = Monday)
     */
    public record Opening(String timezone, boolean openNow, LocalTime closesAt, Next next,
                          List<Day> week, int todayIso) {
    }

    /** One day of the week and its windows, in opening order. */
    public record Day(int isoDay, List<Window> windows) {
    }

    /** One contiguous stretch of open time. A window over midnight is two, as the shop stored it. */
    public record Window(LocalTime opensAt, LocalTime closesAt) {
    }

    /**
     * The next time the shop opens.
     *
     * @param daysAhead 0 for later today, 1 for tomorrow, up to 6 — so the page can say "tomorrow"
     *                  instead of naming a weekday the reader has to count to
     */
    public record Next(int isoDay, int daysAhead, LocalTime opensAt) {
    }

    /**
     * What the merchant last said about the power, and how long ago.
     *
     * <p>It is Lebanon: whether a shop is on mains, on a generator or dark decides whether somebody
     * orders from it at all. Present only when the declaration is recent enough to be presented as
     * happening now ({@code delivery.product.power-declaration-fresh-for}) — an old one is history,
     * and a page that showed it as the present would be lying to a stranger.
     */
    public record Power(Store.PowerStatus status, String note, long minutesAgo) {
    }

    /**
     * Where the shop goes and on what terms.
     *
     * @param radiusMetres the merchant's own circle, or null when the areas alone decide
     * @param areas        the areas it delivers to, by name, in the picker's order; empty means the
     *                     areas do not limit it, never that it delivers nowhere
     *                     ({@code DeliveryZoneService#servedAreasOf})
     */
    public record Delivery(Integer radiusMetres, List<String> areas, BigDecimal fee,
                           BigDecimal feeLbp, BigDecimal minOrder, BigDecimal minOrderLbp,
                           int etaMinMinutes, int etaMaxMinutes) {
    }

    /**
     * The shelf.
     *
     * @param shown how many items the page actually drew
     * @param total how many it could have drawn, so the page can say honestly that there are more
     *              in the app rather than passing a truncated shelf off as the whole shop
     */
    public record Catalogue(List<Section> sections, int shown, int total) {
    }

    /** One aisle. Items with no section of their own fall into the last one, named by the page. */
    public record Section(String name, List<Item> items) {
    }

    /**
     * One thing on the shelf.
     *
     * @param priceUsd the stored price, which is the only price anybody set
     * @param priceLbp the same money at the platform's one rate — a conversion, not a second price
     *                 (see {@code MarketController}); null when the rate is zero, which is how an
     *                 operator says "do not show lira at all"
     */
    public record Item(String name, String imageUrl, BigDecimal priceUsd, BigDecimal priceLbp,
                       boolean inStock) {
    }
}
