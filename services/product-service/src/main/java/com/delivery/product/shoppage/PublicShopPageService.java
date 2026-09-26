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
import org.springframework.data.domain.Pageable;
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

    /**
     * The most addresses one sitemap offers.
     *
     * <p>50,000 is the protocol's own limit, and the reason to obey it is that a file past it is
     * rejected whole rather than trimmed: one shop too many would take every other shop's page out
     * of the index with it. At this platform's size the cap is theory, which is exactly when to
     * write it down — the day it is not, the file should still be a sitemap.
     */
    static final int MAX_SITEMAP_URLS = 50_000;

    /** Items with no section of their own. Named by the renderer, in the reader's language. */
    static final String UNSECTIONED = "";

    /**
     * How much of a merchant's own description one row may carry.
     *
     * <p>The column is {@code text}, and a merchant who pastes three paragraphs about one jar of
     * honey is pasting it onto the page a stranger opens on 3G — a hundred and twenty of those is
     * the page's whole byte budget spent on prose nobody scrolled to. 160 characters is a line or
     * two, which is what a row that expands is for: enough to say what the thing is, and a reason
     * to open the app for the rest.
     */
    static final int MAX_ITEM_DESCRIPTION = 160;

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
                catalogueOf(store),
                store.getTableCount(),
                store.isTableOrdering());
    }

    /**
     * The most lines one table's order may hold, and the most of any one dish.
     *
     * <p>Smaller than a delivery basket's fifty deliberately. This request arrives from a stranger
     * with no token and ends as paper in a kitchen, so the cap is what a table of people plausibly
     * orders in one round rather than what a database could hold: twenty lines and twenty of any
     * one dish is a large table ordering generously, and anything past it is somebody playing.
     */
    static final int MAX_BASKET_LINES = 20;

    static final int MAX_LINE_QTY = 20;

    /**
     * How much a diner may write on one line.
     *
     * <p>"No onions", "well done", "for the child". It is the only free text anywhere on this
     * surface, it is typed by somebody nobody has identified, and a waiter reads it off a ticket —
     * so it is short enough to be read at a glance and capped here rather than wherever it is
     * eventually drawn.
     */
    static final int MAX_LINE_NOTE = 60;

    /**
     * The table a request names, or null when it names none <em>this shop</em> has.
     *
     * <p>A table is a number, because that is what {@link ShopTableCodes} prints on the card and
     * what the shop calls it: a merchant whose card came off table 7 reprints table 7, and there
     * is nothing secret about a number written on a table.
     *
     * <p><strong>Checked against the shop's own room, not merely against a shape.</strong> A shop
     * that has said it seats twelve has no table 500 and no table 0, so a code naming one is not a
     * table here whatever it looks like — which is the difference between a rule about characters
     * and a rule about this restaurant. It costs nothing: the count is already on the store row
     * that was read to answer the request.
     *
     * <p>The rule lives here and not in {@code basket.js}: the script's copy of it decides what a
     * diner is shown, and this one decides what a kitchen would be sent. They agree, and only one
     * of them is trusted.
     */
    static Integer tableOf(Store store, String raw) {
        String trimmed = raw == null ? "" : raw.trim();
        if (trimmed.isEmpty() || trimmed.length() > 3) {
            return null;
        }
        // ASCII digits, checked here rather than left to Integer.parseInt — which accepts every
        // decimal digit Unicode has. "٧" parses to 7 under it, so a code carrying Arabic-Indic
        // digits would have been a table, and the kitchen would have been handed a number that
        // matched no card in the room. The cards are printed in Latin figures; this reads them.
        for (int i = 0; i < trimmed.length(); i++) {
            char c = trimmed.charAt(i);
            if (c < '0' || c > '9') {
                return null;
            }
        }
        int table = Integer.parseInt(trimmed);
        return table >= 1 && table <= store.getTableCount() ? table : null;
    }

    /**
     * What is on a table's order pad, and what the food comes to.
     *
     * <p><strong>This is the whole of the reason the page may show a total at all.</strong> The
     * figures are read here, from the rows the merchant owns, and handed to the renderer already
     * added up; the browser is given words. Nothing in {@code basket.js} multiplies, adds or
     * rounds, and nothing in it could, because it never sees a number to work with.
     *
     * <p><strong>The total is the food and nothing else.</strong> No delivery fee, no minimum, no
     * service charge, no tax. A diner is sitting in the restaurant and will pay the restaurant at
     * the table; the platform is lending it an order pad, not selling the meal. Every term in the
     * platform's delivery formula ({@code Order.recomputeTotal}) is absent here by construction
     * rather than by being set to zero — there is no fee to waive, no area to price, nobody to
     * carry it and no commission to take.
     *
     * <p>It is also read-only and books nothing: pricing a pad writes no row anywhere. What a
     * kitchen is sent is a separate act.
     *
     * @param version what the shelf was when the pad was built; a pad against any other shelf is
     *                refused rather than repriced against rows that have moved
     * @param at      the positions of the lines on that shelf, each with a count and maybe a note
     * @param table   the code on the table, as it arrived; anything that is not one
     *                ({@link #tableOf}) leaves the pad with nowhere to go, which is said rather
     *                than guessed at
     * @throws ShopPageNotFoundException for every shop a stranger may not see — the same refusal,
     *                                   from the same rule, as the page itself
     */
    @Transactional(readOnly = true)
    public ShopBasket price(String slug, String version, List<BasketLine> at, String table) {
        Store store = stores.findBySlug(slug)
                .filter(this::publiclyVisible)
                .orElseThrow(ShopPageNotFoundException::new);

        Set<ShopBasket.Problem> problems = ShopBasket.Problem.none();
        // Answered first, and without reading the shelf. A shop that has not turned this on has no
        // tables as far as this page is concerned, so there is nothing to price and nothing else
        // worth saying — and the cheapest refusal is also the one that gives a caller poking at
        // this endpoint the least to work with.
        if (!store.isTableOrdering()) {
            problems.add(ShopBasket.Problem.NOT_OFFERED);
            return new ShopBasket(List.of(), ZERO2, null, problems);
        }
        Integer seat = tableOf(store, table);
        if (seat == null) {
            // Priced all the same, because a diner whose code did not survive the trip should see
            // what they chose rather than an empty screen — it just cannot be sent anywhere.
            problems.add(ShopBasket.Problem.NO_TABLE);
        }

        Shelf shelf = shelfOf(store);
        if (!version.equals(shelf.version())) {
            // Nothing is priced against a shelf that has moved. The lines are not returned either:
            // their positions no longer name anything, and a list of names read off the wrong rows
            // is worse than an empty answer.
            problems.add(ShopBasket.Problem.STALE);
            return new ShopBasket(List.of(), ZERO2, seat, problems);
        }

        List<ShopBasket.Line> lines = new ArrayList<>(at.size());
        List<ShopBasket.Send.Item> ticket = new ArrayList<>(at.size());
        BigDecimal total = ZERO2;
        for (BasketLine line : at) {
            if (line.at() < 0 || line.at() >= shelf.ordered().size()) {
                // A position off the end of a shelf that otherwise matches: the pad is not the one
                // this shelf was drawn for, whatever the version said.
                problems.add(ShopBasket.Problem.STALE);
                return new ShopBasket(List.of(), ZERO2, seat, problems);
            }
            Product product = shelf.ordered().get(line.at());
            BigDecimal unit = money(product.getPrice());
            // The unit price times the count, and nothing else.
            BigDecimal lineTotal = money(unit.multiply(BigDecimal.valueOf(line.qty())));
            lines.add(new ShopBasket.Line(line.at(), product.getName(), note(line.note()),
                    line.qty(), unit, lineTotal, product.isInStock()));
            // The row a position actually names, which is the one thing a ticket cannot be written
            // without. Collected beside the line the diner reads rather than looked up a second
            // time afterwards, so the two can never name different rows.
            ticket.add(new ShopBasket.Send.Item(product.getId(), line.qty()));
            if (!product.isInStock()) {
                // Priced, said, and left out of the sum: a diner must see what it would have cost,
                // and must not be quoted a total that includes something the kitchen has run out of.
                problems.add(ShopBasket.Problem.GONE);
                continue;
            }
            total = total.add(lineTotal);
        }

        if (lines.isEmpty()) {
            problems.add(ShopBasket.Problem.EMPTY);
        }
        if (!store.isOrderable(clock.instant())) {
            problems.add(ShopBasket.Problem.CLOSED);
        }
        // Only a pad with nothing wrong with it carries the request that sends it. Every refusal
        // above has already been put into words for the diner, and a pad that has one has no
        // button either — which is the same rule said once, in the one place that knows.
        ShopBasket.Send send = problems.isEmpty() && seat != null
                ? new ShopBasket.Send(store.getId(), seat, ticket, total, ticketNotes(lines))
                : null;
        return new ShopBasket(lines, total, seat, problems, send);
    }

    /**
     * How much of a diner's notes a ticket can carry.
     *
     * <p>{@code PlaceTableOrderRequest.notes} is one field of 500 characters for the whole order,
     * because an order line in that service carries no note of its own — a delivery never needed
     * one. So the lines' notes are gathered into it, each one behind the dish it is about, and this
     * is where they stop. Twenty lines of sixty characters could not fit and would be refused by
     * that field's own bound, which would lose the order rather than a note.
     */
    static final int MAX_TICKET_NOTES = 500;

    /**
     * The diner's notes as one line a waiter reads: {@code Hummus: no onions · Fattoush: no mint}.
     *
     * <p>Whole entries only. A note cut in half on a kitchen ticket is worse than a note that is
     * not there: "no" and "nuts" are the same four characters as "no nuts" minus a space. What it
     * costs is that a diner who writes on the twentieth line of a very long order may not have it
     * read — their own pad still shows it, so they can say it to the waiter, and
     * {@code PublicShopBasketApiTest} pins the rule.
     */
    private static String ticketNotes(List<ShopBasket.Line> lines) {
        StringBuilder all = new StringBuilder();
        for (ShopBasket.Line line : lines) {
            if (line.note() == null) {
                continue;
            }
            String entry = (all.isEmpty() ? "" : " · ") + line.name() + ": " + line.note();
            if (all.length() + entry.length() > MAX_TICKET_NOTES) {
                break;
            }
            all.append(entry);
        }
        return all.isEmpty() ? null : all.toString();
    }

    /**
     * One line a pad asks about: where it sits on the shelf, how many, and what was asked for.
     *
     * @param note free text from somebody nobody has identified, so it is cut to
     *             {@value #MAX_LINE_NOTE} here and escaped wherever it is drawn
     */
    public record BasketLine(int at, int qty, String note) {
    }

    /** What a diner wrote on a line, cut to something a ticket can carry. Null for nothing. */
    private static String note(String raw) {
        if (raw == null) {
            return null;
        }
        String trimmed = raw.strip();
        if (trimmed.isEmpty()) {
            return null;
        }
        return trimmed.length() <= MAX_LINE_NOTE ? trimmed : trimmed.substring(0, MAX_LINE_NOTE);
    }

    private static final BigDecimal ZERO2 = BigDecimal.ZERO.setScale(2);

    /** Every figure this page quotes, at the scale the platform stores money in. */
    private static BigDecimal money(BigDecimal amount) {
        return amount == null ? ZERO2 : amount.setScale(2, RoundingMode.HALF_UP);
    }

    /**
     * Whether this slug has a page at all, without building one.
     *
     * <p>One indexed lookup and the same {@link #publiclyVisible} rule {@link #read} applies — not a
     * second copy of it, and not a read of the page either. It is what {@code /s/{slug}/qr.png}
     * asks: the QR code is a pure function of the slug, so the only thing the request needs from
     * the database is whether there is a shop behind it, and answering that with a whole page read
     * cost six queries and a hundred and twenty products to draw a square.
     */
    @Transactional(readOnly = true)
    public boolean exists(String slug) {
        return stores.findBySlug(slug).filter(this::publiclyVisible).isPresent();
    }

    /**
     * How many tables this shop has codes for, or zero for a shop nobody may see.
     *
     * <p>{@link #exists}'s one lookup with one more column read off the row it already had, rather
     * than a page read: printing a sheet of table cards needs the shop's name and its table count
     * and nothing else about the shelf. Zero for a hidden shop is the same refusal
     * {@link #exists} gives — a table code is a QR on a table pointing at the page, and a shop that
     * has no page must not be able to print one.
     */
    @Transactional(readOnly = true)
    public short tablesOf(String slug) {
        return stores.findBySlug(slug)
                .filter(this::publiclyVisible)
                .map(Store::getTableCount)
                .orElse((short) 0);
    }

    /**
     * Every shop that has a page, for the sitemap.
     *
     * <p>The same rule as {@link #read}, asked of the whole table: a shop that would 404 must not be
     * offered to a crawler, or the site publishes a list of addresses that answer 404 and asks
     * Google to keep checking them.
     *
     * <p><strong>Asked of the database, not of Java.</strong> This is the one read here that is
     * about every shop there is, and it used to load the whole {@code stores} table as entities to
     * throw most of them away. Now the rule is the {@code WHERE} clause and only slugs come back —
     * which does put the rule in two places, so {@code PublicShopPageDatabaseTest} asserts against
     * a real database that every slug this returns renders, and that the four kinds of hidden shop
     * are in neither answer.
     *
     * <p>Capped at {@link #MAX_SITEMAP_URLS}. A shop past the cap is not lost: it is reachable, it
     * is linked from the app, and it is one of 50,000 — whereas an oversized sitemap is one a
     * crawler rejects whole, taking the other 50,000 with it.
     */
    @Transactional(readOnly = true)
    public List<String> listedSlugs() {
        Pageable cap = PageRequest.of(0, MAX_SITEMAP_URLS);
        Set<Store.ServiceCategory> open = serviceCategories.enabled();
        // An empty IN list is the one thing this query cannot be given (StoreRepository
        // #findServicesStorefront says why), and "every category is closed" is a state an operator
        // can really configure.
        return open.isEmpty()
                ? stores.findPublicGoodsPageSlugs(cap)
                : stores.findPublicPageSlugs(open, cap);
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

    private PublicShopPage.Catalogue catalogueOf(Store store) {
        return shelfOf(store).catalogue();
    }

    /**
     * The shelf, by section — and the products behind it, in the order the page draws them.
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
     *
     * <p><strong>One method, because the basket depends on the two answers agreeing.</strong> A
     * basket names a line by where it sits on the shelf, and {@link #quote} resolves that position
     * against a shelf read here again — so the page's order and the quote's order have to be the
     * same order, and the only way to be sure of that is for there to be one place that decides it.
     */
    Shelf shelfOf(Store store) {
        // The merchant's own order inside each block (V41), name for the ties and for any block
        // whose positions have never been written. Sections are ordered separately, by
        // sectionNames(); this sort only has to settle what is inside one of them, which is why
        // position leads and the section is not in the sort at all.
        //
        // It also changes which items a shop past MAX_ITEMS loses, and for the better: the cut now
        // falls after the top of every section rather than somewhere in the alphabet, so a shop with
        // two hundred lines shows the start of each of its sections instead of everything from A to M.
        Page<Product> page = products.findActiveInStore(
                store.getId(), null, "%",
                PageRequest.of(0, MAX_ITEMS,
                        Sort.by(Sort.Direction.ASC, "position").and(Sort.by(Sort.Direction.ASC, "name"))));
        List<Product> shelf = page.getContent();
        int total = (int) page.getTotalElements();
        if (shelf.isEmpty()) {
            return new Shelf(List.of(), List.of(), 0, total, versionOf(List.of()));
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
        // Filed the same way and in step with the items above, so that flattening the sections and
        // flattening this map give the same sequence — which is what a basket's positions mean.
        Map<String, List<Product>> rowsBySection = new LinkedHashMap<>();
        sectionNames.values().forEach(name -> {
            bySection.put(name, new ArrayList<>());
            rowsBySection.put(name, new ArrayList<>());
        });

        for (Product product : shelf) {
            String section = product.getCategoryId() == null
                    ? UNSECTIONED
                    : sectionNames.getOrDefault(product.getCategoryId(), UNSECTIONED);
            String key = product.getImageRefs().isEmpty() ? null : product.getImageRefs().get(0);
            ImageUrl picture = key == null ? null : pictures.get(key);
            bySection.computeIfAbsent(section, ignored -> new ArrayList<>())
                    .add(new PublicShopPage.Item(
                            product.getName(),
                            shortened(product.getDescription()),
                            ImageUrl.thumbOf(picture),
                            product.getPrice(),
                            lbpFaceOf(product.getPrice()),
                            product.isInStock()));
            rowsBySection.computeIfAbsent(section, ignored -> new ArrayList<>()).add(product);
        }

        List<PublicShopPage.Section> sections = bySection.entrySet().stream()
                .filter(entry -> !entry.getValue().isEmpty())
                .map(entry -> new PublicShopPage.Section(entry.getKey(),
                        List.copyOf(entry.getValue())))
                .toList();
        List<Product> ordered = rowsBySection.values().stream()
                .filter(rows -> !rows.isEmpty())
                .flatMap(List::stream)
                .toList();
        return new Shelf(sections, ordered, shelf.size(), total, versionOf(ordered));
    }

    /**
     * The shelf a page drew and the rows it drew it from, kept together.
     *
     * @param ordered the products in drawing order — section by section, row by row. Position
     *                {@code n} here is the {@code n}th {@code <li>} in the rendered menu, which is
     *                the whole of what a basket line names.
     */
    record Shelf(List<PublicShopPage.Section> sections, List<Product> ordered, int shown, int total,
                 String version) {

        PublicShopPage.Catalogue catalogue() {
            return new PublicShopPage.Catalogue(sections, shown, total, version);
        }
    }

    /**
     * What this exact shelf is, in twelve characters.
     *
     * <p>A basket kept in a browser names its lines by where they sat on the shelf, which is the
     * one way to say "this row" without the page printing an id for every row it draws. Positions
     * are only meaningful against the shelf they were read off, so the page carries this and a
     * quote is refused unless it still matches: an item added, removed, paused or <em>renamed</em>
     * moves rows under a basket that is already in a browser, and pricing it anyway would charge a
     * customer for something they never tapped. A rename is in here because the query sorts by
     * name — the ids alone would not have moved, and the rows would have.
     *
     * <p>It is a digest of ids and not the ids: a reader can tell whether the shelf they were shown
     * is still the shelf, and nothing else. A price is deliberately not in it — a corrected price
     * should reprice the basket a customer is holding, not throw it away.
     */
    static String versionOf(List<Product> ordered) {
        StringBuilder joined = new StringBuilder(ordered.size() * 37);
        for (Product product : ordered) {
            joined.append(product.getId()).append('\n');
        }
        try {
            byte[] digest = java.security.MessageDigest.getInstance("SHA-256")
                    .digest(joined.toString().getBytes(java.nio.charset.StandardCharsets.UTF_8));
            return java.util.Base64.getUrlEncoder().withoutPadding()
                    .encodeToString(java.util.Arrays.copyOf(digest, 9));
        } catch (java.security.NoSuchAlgorithmException impossible) {
            // Every JVM ships SHA-256. A shelf that cannot be versioned must not be priced, and
            // this value matches nothing, so every quote against it is refused as stale.
            return "unversioned";
        }
    }

    /**
     * A merchant's description, cut to something a row can hold.
     *
     * <p>Null for anything blank, so the renderer has one question to ask rather than two. Cut at
     * the last space before the limit rather than mid-word, and marked with an ellipsis so a
     * reader can tell a sentence that was trimmed from one that simply ended — the whole of it is
     * in the app, which is where this page has been sending people all along.
     */
    private static String shortened(String description) {
        if (description == null || description.isBlank()) {
            return null;
        }
        String trimmed = description.strip();
        if (trimmed.length() <= MAX_ITEM_DESCRIPTION) {
            return trimmed;
        }
        String cut = trimmed.substring(0, MAX_ITEM_DESCRIPTION);
        int lastSpace = cut.lastIndexOf(' ');
        // A description with no space in the first 160 characters is one long token, and cutting it
        // at the limit is the only honest thing left.
        return (lastSpace > MAX_ITEM_DESCRIPTION / 2 ? cut.substring(0, lastSpace) : cut).strip()
                + "…";
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
        return lbpFaceOf(usd, lbpPerUsd);
    }

    /**
     * The same rule, for the basket, which is spelled by a different class.
     *
     * <p>Static and shared rather than written out twice: the item prices in the markup are
     * converted by this, and a basket that rounded to a different note would add up to a figure no
     * column of the page reaches.
     */
    static BigDecimal lbpFaceOf(BigDecimal usd, BigDecimal lbpPerUsd) {
        if (lbpPerUsd == null || lbpPerUsd.signum() <= 0 || usd == null) {
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
