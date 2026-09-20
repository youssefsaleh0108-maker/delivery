package com.delivery.product.shoppage;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.Clock;
import java.time.DayOfWeek;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalTime;
import java.time.ZoneId;
import java.time.ZonedDateTime;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Sort;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.product.domain.Category;
import com.delivery.product.domain.CategoryRepository;
import com.delivery.product.domain.DeliveryZone;
import com.delivery.product.domain.Product;
import com.delivery.product.domain.ProductRepository;
import com.delivery.product.domain.Store;
import com.delivery.product.domain.StoreHours;
import com.delivery.product.domain.StoreRepository;
import com.delivery.product.service.DeliveryZoneService;
import com.delivery.product.service.ProductImageService;
import com.delivery.product.service.ProductImageService.ImageUrl;
import com.delivery.product.service.ServiceCategories;

/**
 * Builds the one thing a shopkeeper can paste into a WhatsApp status.
 *
 * <p>Reads the shop the way a stranger may see it and no further. It takes a <strong>slug</strong>,
 * never an id: the public URL is the slug the shop has carried since it was created, the slug does
 * not move when the shop is renamed ({@code Store.updateProfile}), and refusing an id here means an
 * id guessed out of an app's network log is not a second address for the same page.
 *
 * <p>The refusal is the careful part. A draft shop, a suspended shop, a shop with no pin, a service
 * shop whose category is closed and a slug that was never anybody's all raise the same exception
 * from the same place, so the response cannot differ — see {@link ShopPageNotFoundException}.
 */
@Service
public class PublicShopPageService {

    /**
     * The most items one page draws.
     *
     * <p>A bound on what a phone on a 3G connection downloads, not on what the shop sells. A large
     * grocer's catalogue is thousands of rows and nobody scrolls a shared link that far; the page
     * says how many there are in total and sends the reader to the app for the rest, which is what
     * the page is for.
     */
    static final int MAX_ITEMS = 120;

    /** Items with no section of their own. Named by the renderer, in the reader's language. */
    static final String UNSECTIONED = "";

    private final StoreRepository stores;
    private final ProductRepository products;
    private final CategoryRepository categories;
    private final DeliveryZoneService zones;
    private final ProductImageService images;
    private final ServiceCategories serviceCategories;
    private final Clock clock;

    /** How long a power declaration is still presented as what the lights are doing now. */
    private final Duration powerDeclarationFreshFor;

    /**
     * LBP per USD, the platform's one display rate — the same key and the same environment
     * variable {@code MarketController} serves to the apps and transfer-service locks a quote
     * from. Read here rather than converted in the browser because this page runs no JavaScript at
     * all: whatever a chat app's preview fetches is the whole page.
     *
     * <p>Zero means "do not show lira", exactly as it does everywhere else.
     */
    private final BigDecimal lbpPerUsd;

    public PublicShopPageService(StoreRepository stores,
                                 ProductRepository products,
                                 CategoryRepository categories,
                                 DeliveryZoneService zones,
                                 ProductImageService images,
                                 ServiceCategories serviceCategories,
                                 Clock clock,
                                 @Value("${delivery.product.power-declaration-fresh-for:4h}")
                                 Duration powerDeclarationFreshFor,
                                 @Value("${delivery.market.lbp-per-usd:90000}")
                                 BigDecimal lbpPerUsd) {
        this.stores = stores;
        this.products = products;
        this.categories = categories;
        this.zones = zones;
        this.images = images;
        this.serviceCategories = serviceCategories;
        this.clock = clock;
        this.powerDeclarationFreshFor = powerDeclarationFreshFor;
        this.lbpPerUsd = lbpPerUsd == null ? BigDecimal.ZERO : lbpPerUsd;
    }

    /**
     * The page for one slug.
     *
     * @throws ShopPageNotFoundException for every shop a stranger may not see, and for a slug that
     *         names nothing — one exception, so one response
     */
    @Transactional(readOnly = true)
    public PublicShopPage read(String slug) {
        Store store = stores.findBySlug(slug)
                .filter(this::publiclyVisible)
                .orElseThrow(ShopPageNotFoundException::new);

        Instant now = clock.instant();
        ImageUrl logo = images.resolveImage(store.getLogoRef());
        ImageUrl cover = images.resolveImage(store.getCoverRef());

        return new PublicShopPage(
                store.getSlug(),
                store.getName(),
                store.getTagline(),
                store.getDescription(),
                // The list-sized logo: it is drawn small, and a merchant's 4 MB original behind a
                // 64 px circle is most of this page's weight for none of its meaning.
                ImageUrl.thumbOf(logo),
                // The header takes the cover whole; the Open Graph tag takes the derivative. See
                // PublicShopPage.coverThumbUrl for why the two differ.
                ImageUrl.fullOf(cover),
                ImageUrl.thumbOf(cover),
                store.getNeighborhood(),
                store.getTags(),
                store.isVerifiedLocal(),
                store.getRating(),
                store.getRatingCount(),
                store.getVertical(),
                store.getServiceCategory(),
                openingOf(store, now),
                powerOf(store, now),
                deliveryOf(store),
                catalogueOf(store));
    }

    /**
     * Every shop that has a page, for the sitemap.
     *
     * <p>The same rule as {@link #read}, asked of the whole table: a shop that would 404 must not be
     * offered to a crawler, or the site publishes a list of addresses that answer 404 and asks
     * Google to keep checking them.
     */
    @Transactional(readOnly = true)
    public List<String> listedSlugs() {
        return stores.findAll().stream()
                .filter(this::publiclyVisible)
                .map(Store::getSlug)
                .sorted()
                .toList();
    }

    /**
     * Whether a stranger may see this shop at all.
     *
     * <p>One method, called by the page and by the sitemap, so the two can never disagree about
     * which shops exist.
     *
     * <ul>
     *   <li><strong>ACTIVE.</strong> A draft is a shop being set up and a suspended shop was
     *       delisted by an administrator; neither is open for business.
     *   <li><strong>Pinned.</strong> {@code Store.NotListable.NO_PIN} — a shop with no pin cannot be
     *       found by distance, has no delivery circle and is unreachable by every feature that asks
     *       where it is. Shops that went live before that rule existed are still ACTIVE without a
     *       pin ({@code Store.publish}), and this page is the one surface that must not draw one:
     *       it is the address a shopkeeper prints on a sign.
     *   <li><strong>An open category, for a service shop.</strong> A closed category is not shown to
     *       customers anywhere ({@code ServiceCategories}), and a public page that ignored that
     *       would be the one place a closed category was still advertised.
     * </ul>
     */
    private boolean publiclyVisible(Store store) {
        if (store.getStatus() != Store.Status.ACTIVE || store.location() == null) {
            return false;
        }
        if (!store.isServices()) {
            return true;
        }
        Set<Store.ServiceCategory> open = serviceCategories.enabled();
        return store.getServiceCategory() != null && open.contains(store.getServiceCategory());
    }

    // ---------------------------------------------------------------- opening hours

    /**
     * Open or closed <em>now</em>, in the shop's own calendar, with the week behind the answer.
     *
     * <p>"Open" is {@code Store.isOrderable}, which is the same question the storefront card asks —
     * a shop that is merely busy or closing soon is still open, and a page that called it closed
     * would turn a customer away from a shop that would have taken the order.
     */
    private PublicShopPage.Opening openingOf(Store store, Instant now) {
        ZoneId zone = store.zone();
        ZonedDateTime local = now.atZone(zone);
        int todayIso = local.getDayOfWeek().getValue();

        Map<Integer, List<PublicShopPage.Window>> byDay = new LinkedHashMap<>();
        for (int iso = 1; iso <= 7; iso++) {
            byDay.put(iso, new ArrayList<>());
        }
        for (StoreHours window : store.getHours()) {
            byDay.get(window.getDay().getValue())
                    .add(new PublicShopPage.Window(window.getOpensAt(), window.getClosesAt()));
        }
        List<PublicShopPage.Day> week = new ArrayList<>(7);
        for (int iso = 1; iso <= 7; iso++) {
            List<PublicShopPage.Window> windows = byDay.get(iso);
            windows.sort(Comparator.comparing(PublicShopPage.Window::opensAt)
                    .thenComparing(PublicShopPage.Window::closesAt));
            week.add(new PublicShopPage.Day(iso, List.copyOf(windows)));
        }

        boolean openNow = store.isOrderable(now);
        return new PublicShopPage.Opening(
                zone.getId(),
                openNow,
                openNow ? store.closingTimeAt(now) : null,
                openNow ? null : nextOpening(byDay, todayIso, local.toLocalTime()),
                List.copyOf(week),
                todayIso);
    }

    /**
     * When the shop opens next, looking a week ahead from now in its own calendar.
     *
     * <p>Today counts, and only from the current time: a shop shut between lunch and dinner opens
     * again this afternoon, and telling that reader "tomorrow" would be wrong in the way that loses
     * the order. Null when nothing in the week opens at all, which is a shop whose hours were
     * cleared — the page then says only that it is closed, because it has nothing honest to add.
     */
    private static PublicShopPage.Next nextOpening(Map<Integer, List<PublicShopPage.Window>> byDay,
                                                   int todayIso, LocalTime timeOfDay) {
        for (int ahead = 0; ahead < 7; ahead++) {
            int iso = ((todayIso - 1 + ahead) % 7) + 1;
            LocalTime earliest = null;
            for (PublicShopPage.Window window : byDay.get(iso)) {
                if (ahead == 0 && !window.opensAt().isAfter(timeOfDay)) {
                    continue;
                }
                if (earliest == null || window.opensAt().isBefore(earliest)) {
                    earliest = window.opensAt();
                }
            }
            if (earliest != null) {
                return new PublicShopPage.Next(iso, ahead, earliest);
            }
        }
        return null;
    }

    // ---------------------------------------------------------------- power, delivery, shelf

    /**
     * What the merchant last said about the power, if it is recent enough to mean now.
     *
     * <p>The same window the apps use ({@code Store.powerDeclaredSince}). An old declaration is
     * dropped rather than shown with a date: on this page it would be read as the present by
     * somebody who has never seen the app, and "on generator" three days ago is not news about
     * tonight.
     */
    private PublicShopPage.Power powerOf(Store store, Instant now) {
        if (!store.powerDeclaredSince(now.minus(powerDeclarationFreshFor))) {
            return null;
        }
        long minutes = Duration.between(store.getPowerUpdatedAt(), now).toMinutes();
        return new PublicShopPage.Power(store.getPowerStatus(), store.getPowerNote(),
                Math.max(0, minutes));
    }

    private PublicShopPage.Delivery deliveryOf(Store store) {
        List<String> areas = zones.servedAreasOf(store.getId()).stream()
                .map(DeliveryZone::getName)
                .toList();
        return new PublicShopPage.Delivery(
                store.getDeliveryRadiusMetres(),
                areas,
                store.getDeliveryFee(),
                lbpFaceOf(store.getDeliveryFee()),
                store.getMinOrder(),
                lbpFaceOf(store.getMinOrder()),
                store.getEtaMinMinutes(),
                store.getEtaMaxMinutes());
    }

    /**
     * The shelf, by section.
     *
     * <p>{@code findActiveInStore} is the storefront's own query, so archived, draft and paused
     * products are gone before anything here sees them — this page cannot accidentally publish a
     * product the merchant has not published. Out of stock is a different thing and is kept and
     * marked: it tells a reader the shop carries the thing, which is most of why they opened the
     * page.
     *
     * <p>Sections come out in the merchant's own order for the sections they created, then anything
     * filed under a platform category, then whatever has no section at all. Three queries in total,
     * whatever the shelf's size: the products, the sections, and one batch for the pictures.
     */
    private PublicShopPage.Catalogue catalogueOf(Store store) {
        Page<Product> page = products.findActiveInStore(
                store.getId(), null, "%",
                PageRequest.of(0, MAX_ITEMS, Sort.by(Sort.Direction.ASC, "name")));
        List<Product> shelf = page.getContent();
        if (shelf.isEmpty()) {
            return new PublicShopPage.Catalogue(List.of(), 0, (int) page.getTotalElements());
        }

        List<String> refs = shelf.stream()
                .map(p -> p.getImageRefs().isEmpty() ? null : p.getImageRefs().get(0))
                .filter(java.util.Objects::nonNull)
                .distinct()
                .toList();
        Map<String, ImageUrl> pictures = images.resolveByKey(refs);

        Map<UUID, String> sectionNames = sectionNames(store.getId());
        // A LinkedHashMap keyed in the order sectionNames was built, so the page's sections come
        // out in the merchant's order rather than in whatever order the products happened to sort.
        Map<String, List<PublicShopPage.Item>> bySection = new LinkedHashMap<>();
        sectionNames.values().forEach(name -> bySection.put(name, new ArrayList<>()));

        for (Product product : shelf) {
            String section = product.getCategoryId() == null
                    ? UNSECTIONED
                    : sectionNames.getOrDefault(product.getCategoryId(), UNSECTIONED);
            String key = product.getImageRefs().isEmpty() ? null : product.getImageRefs().get(0);
            ImageUrl picture = key == null ? null : pictures.get(key);
            bySection.computeIfAbsent(section, ignored -> new ArrayList<>())
                    .add(new PublicShopPage.Item(
                            product.getName(),
                            ImageUrl.thumbOf(picture),
                            product.getPrice(),
                            lbpFaceOf(product.getPrice()),
                            product.isInStock()));
        }

        List<PublicShopPage.Section> sections = bySection.entrySet().stream()
                .filter(entry -> !entry.getValue().isEmpty())
                .map(entry -> new PublicShopPage.Section(entry.getKey(), List.copyOf(entry.getValue())))
                .toList();
        return new PublicShopPage.Catalogue(sections, shelf.size(), (int) page.getTotalElements());
    }

    /**
     * The shop's section names, in the order they should be drawn: the merchant's own sections in
     * the order the merchant put them in, then the platform's categories by name.
     */
    private Map<UUID, String> sectionNames(UUID storeId) {
        Map<UUID, String> names = new LinkedHashMap<>();
        categories.findByStoreIdOrderByPositionAscNameAsc(storeId)
                .forEach(category -> names.put(category.getId(), category.getName()));
        categories.findByStoreIdIsNull().stream()
                .sorted(Comparator.comparing(Category::getName))
                .forEach(category -> names.putIfAbsent(category.getId(), category.getName()));
        return names;
    }

    /**
     * A dollar price as the lira note it is handed over in.
     *
     * <p>The platform's one rule, spelled exactly as {@code MoneyTransfer.lbpFaceOf} spells it —
     * multiply, then round HALF_UP to the nearest 1,000-lira note, in decimals rather than doubles.
     * The apps' own {@code lira.dart} says the same thing in integers for the same reason: this
     * figure is what somebody hands a rider at the door, and a page that rounded differently from
     * checkout would quote a note the shop then disagrees with.
     *
     * <p>Null at a rate of zero: that is an operator saying "do not show lira at all", and a
     * displayed 0 LBP would be a price rather than an absence.
     */
    private BigDecimal lbpFaceOf(BigDecimal usd) {
        if (lbpPerUsd.signum() <= 0 || usd == null) {
            return null;
        }
        return usd.multiply(lbpPerUsd)
                .divide(BigDecimal.valueOf(1000), 0, RoundingMode.HALF_UP)
                .multiply(BigDecimal.valueOf(1000));
    }

    /** The rate the page converted with, for the line that says so. */
    public BigDecimal lbpPerUsd() {
        return lbpPerUsd;
    }

    /** What every refusal on this page throws. One type, so one response. */
    public static class ShopPageNotFoundException extends RuntimeException {

        public ShopPageNotFoundException() {
            // No slug, and no reason. Both would end up in a log line that answers "does this shop
            // exist" for anybody who can read the log, and the message has nowhere else to go: the
            // response is a fixed page.
            super("No such shop page");
        }
    }
}
