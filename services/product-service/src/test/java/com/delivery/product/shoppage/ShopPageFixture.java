package com.delivery.product.shoppage;

import java.math.BigDecimal;
import java.time.Clock;
import java.time.DayOfWeek;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalTime;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.function.LongSupplier;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.PageRequest;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import com.delivery.product.domain.Category;
import com.delivery.product.domain.CategoryRepository;
import com.delivery.product.domain.DeliveryZone;
import com.delivery.product.domain.GeoPoint;
import com.delivery.product.domain.Product;
import com.delivery.product.domain.ProductRepository;
import com.delivery.product.domain.Store;
import com.delivery.product.domain.StoreHours;
import com.delivery.product.domain.StoreRepository;
import com.delivery.product.service.DeliveryZoneService;
import com.delivery.product.service.ProductImageService;
import com.delivery.product.service.ProductImageService.ImageUrl;
import com.delivery.product.service.ServiceCategories;
import com.delivery.product.service.Thumbnailer;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyCollection;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

/**
 * One shop, its shelf and the wiring that renders them, for every test of the public page.
 *
 * <p>Built out of real {@link Store} and {@link Product} objects over mocked repositories rather
 * than a hand-written model: availability, the slug and the lira arithmetic are all domain rules,
 * and a fixture that stubbed the answers would prove the renderer agrees with the fixture rather
 * than with the platform. The tests then assert against the bytes the controller actually writes.
 */
final class ShopPageFixture {

    static final String BASE = "https://www.youdrop.shop";

    /** Where the object store serves public pictures on dev — {@code MINIO_PUBLIC_ENDPOINT}. */
    static final String IMAGE_ORIGIN = "https://api-dev.youdrop.shop";

    /**
     * The merchant's Keycloak {@code sub}. Deliberately unmistakable: every test that asks "what
     * can a competitor read" searches the rendered page for this exact string.
     */
    static final String MERCHANT = "kc-sub-9d41f0b2-merchant-only";

    /** The merchant's own item codes, which the merchant-only endpoints return and this must not. */
    static final String SKU = "SKU-MERCHANT-ONLY-4471";
    static final String BARCODE = "6291041500213";

    /**
     * The two file ids the shop's artwork was uploaded under.
     *
     * <p>Fixed rather than random so a test can assert the exact URL the page prints, and real
     * UUIDs because that is what {@code StorageService.buildObjectKey} mints for every upload.
     */
    private static final java.util.UUID LOGO_FILE =
            java.util.UUID.fromString("2f6a1c74-9b0e-4c2a-8f31-5d7c0a9e4b13");
    private static final java.util.UUID COVER_FILE =
            java.util.UUID.fromString("c41d8e52-7a36-4f9b-b0d2-1e83f6a05c97");

    private final StoreRepository stores = mock(StoreRepository.class);
    private final ProductRepository products = mock(ProductRepository.class);
    private final CategoryRepository categories = mock(CategoryRepository.class);
    private final DeliveryZoneService zones = mock(DeliveryZoneService.class);
    private final ProductImageService images = mock(ProductImageService.class);
    private final ServiceCategories serviceCategories = mock(ServiceCategories.class);

    private final Store shop;
    private final List<Product> shelf = new ArrayList<>();
    private final List<Category> ownSections = new ArrayList<>();
    private int shelfTotal;
    private List<DeliveryZone> areas = List.of();

    /** This shop's own service category, which the enabled set below must therefore contain. */
    private final Store.ServiceCategory category;

    private Clock clock = Clock.fixed(Instant.parse("2026-09-20T15:00:00Z"), ZoneId.of("UTC"));
    private BigDecimal rate = new BigDecimal("90000");

    // ---------------------------------------------------------------- building a shop

    /** A live, pinned Lebanese grocer, open 08:00-23:00 every day in its own calendar. */
    ShopPageFixture() {
        this(true);
    }

    /**
     * @param listed false leaves the shop where every shop starts — DRAFT, never published. The
     *               domain has no way back from ACTIVE, and inventing one in a test fixture would
     *               be a transition the platform does not have.
     */
    ShopPageFixture(boolean listed) {
        this(listed, Store.Vertical.GROCERY, null);
    }

    /**
     * The same shop in another line of business.
     *
     * <p>A constructor rather than a setter because that is what the domain allows: the vertical is
     * fixed when a shop is created, and {@code Store.updateProfile} refuses to move one across the
     * line between goods and services.
     */
    ShopPageFixture(Store.Vertical vertical) {
        this(true, vertical, null);
    }

    /** A service shop, in a category an operator has left open. */
    ShopPageFixture(Store.ServiceCategory category) {
        this(true, Store.Vertical.SERVICES, category);
    }

    private ShopPageFixture(boolean listed, Store.Vertical vertical,
                            Store.ServiceCategory category) {
        this.category = category;
        shop = category == null
                ? new Store(MERCHANT, "Dekkanet Al Rawche", vertical)
                : new Store(MERCHANT, "Dekkanet Al Rawche", vertical, category);
        shop.updateProfile("Dekkanet Al Rawche", "Everything the corner shop should have",
                "Open since 1974, two streets up from the rock.", vertical,
                List.of("grocery", "dekkane"), "Asia/Beirut", "Rawche, Beirut");
        shop.setNeighborhood("Ras Beirut");
        shop.updateCommercials(new BigDecimal("2.00"), new BigDecimal("5.00"), 20, 40);
        shop.applyRating(new BigDecimal("4.6"), 128);
        shop.setVerifiedLocal(true);
        // Keyed exactly as an upload keys it: StoreImageService.presign hands StorageService the
        // prefix "stores/<storeId>/<slot>" and StorageService.buildObjectKey appends the file's own
        // id and extension. So the store's id really is inside the page's image URLs, and a fixture
        // that wrote "stores/logo.png" would let the "no ids on the page" test pass on a shape
        // production never produces.
        shop.setImagery(
                "stores/" + shop.getId() + "/logo/" + LOGO_FILE + ".png",
                "stores/" + shop.getId() + "/cover/" + COVER_FILE + ".jpg");
        shop.setDeliveryRadiusMetres(2500);
        openEveryDay(LocalTime.of(8, 0), LocalTime.of(23, 0));
        shop.pinAt(GeoPoint.of(33.8905, 35.4788));
        if (listed) {
            shop.publish(Instant.parse("2026-01-05T09:00:00Z"));
        }
    }

    /**
     * Rewrites everything about the shop that a merchant types for themselves.
     *
     * <p>Applied after the shop is built, so the slug still comes from a sane name — which is what
     * production does too: the slug is minted once at creation and {@code updateProfile} never
     * touches it, so a merchant who renames the shop cannot rename its page.
     */
    ShopPageFixture profile(String name, String tagline, String description, List<String> tags,
                            String neighbourhood) {
        shop.updateProfile(name, tagline, description, Store.Vertical.GROCERY, tags,
                "Asia/Beirut", "Rawche, Beirut");
        shop.setNeighborhood(neighbourhood);
        return this;
    }

    ShopPageFixture openEveryDay(LocalTime from, LocalTime to) {
        List<StoreHours> week = new ArrayList<>();
        for (DayOfWeek day : DayOfWeek.values()) {
            week.add(new StoreHours(day, from, to));
        }
        shop.replaceHours(week);
        return this;
    }

    ShopPageFixture hours(StoreHours... windows) {
        shop.replaceHours(Arrays.asList(windows));
        return this;
    }

    ShopPageFixture timezone(String zone) {
        shop.useTimezone(zone);
        return this;
    }

    ShopPageFixture at(String instant) {
        this.clock = Clock.fixed(Instant.parse(instant), ZoneId.of("UTC"));
        return this;
    }

    ShopPageFixture lbpPerUsd(String value) {
        this.rate = new BigDecimal(value);
        return this;
    }

    ShopPageFixture suspended() {
        shop.suspend();
        return this;
    }

    ShopPageFixture withoutPin() {
        shop.clearPin();
        return this;
    }

    ShopPageFixture power(Store.PowerStatus status, String note, String declaredAt) {
        shop.declarePower(status, note, Instant.parse(declaredAt));
        return this;
    }

    ShopPageFixture noRating() {
        shop.applyRating(null, 0);
        return this;
    }

    ShopPageFixture areas(String... names) {
        List<DeliveryZone> built = new ArrayList<>();
        for (String name : names) {
            built.add(new DeliveryZone(name, "Beirut", 10));
        }
        this.areas = List.copyOf(built);
        return this;
    }

    /** A section of the shop's own, in the merchant's order, with the items filed under it. */
    ShopPageFixture section(String name, Item... items) {
        Category section = new Category(shop.getId(), name, null, (short) ownSections.size());
        ownSections.add(section);
        for (Item item : items) {
            shelf.add(item.build(shop, section.getId()));
        }
        return this;
    }

    /** How many items the shelf holds in total, when it is longer than one page draws. */
    ShopPageFixture shelfTotal(int total) {
        this.shelfTotal = total;
        return this;
    }

    Store shop() {
        return shop;
    }

    /**
     * The mocked repositories, for the tests that count what a request actually asked the database
     * — "the QR code does not read the shelf" and "a second reader inside the window reads nothing".
     */
    ProductRepository products() {
        return products;
    }

    StoreRepository stores() {
        return stores;
    }

    String slug() {
        return shop.getSlug();
    }

    /** The URL the page prints for the cover, full size, as the object store serves it. */
    String coverUrl() {
        return objectUrl(shop.getCoverRef());
    }

    /** The derivative the {@code og:image} tag carries. */
    String coverThumbUrl() {
        return objectUrl(Thumbnailer.thumbKeyFor(shop.getCoverRef()));
    }

    /** The derivative the page's small round logo is drawn from. */
    String logoThumbUrl() {
        return objectUrl(Thumbnailer.thumbKeyFor(shop.getLogoRef()));
    }

    /** The ids of everything on the shelf, which a picture URL may carry and the markup may not. */
    List<String> productIds() {
        return shelf.stream().map(product -> product.getId().toString()).toList();
    }

    /** The ids of the rows behind the section headings and the delivery areas. */
    List<String> sectionAndAreaIds() {
        List<String> ids = new ArrayList<>();
        ownSections.forEach(section -> ids.add(section.getId().toString()));
        areas.forEach(area -> ids.add(area.getId().toString()));
        return List.copyOf(ids);
    }

    String url() {
        return BASE + "/s/" + shop.getSlug();
    }

    BigDecimal rate() {
        return rate;
    }

    /**
     * One thing on the shelf, as a merchant would have set it up.
     *
     * @param about what the merchant wrote about it. Null by default, because most rows in most
     *              shops have nothing written about them and a fixture that gave every item a
     *              description would make the page's byte budget look easier than it is.
     */
    record Item(String name, String about, String price, boolean inStock, boolean pictured) {

        static Item of(String name, String price) {
            return new Item(name, null, price, true, true);
        }

        /** A merchant who said what the thing is. The row then expands to show it. */
        Item describedAs(String about) {
            return new Item(name, about, price, inStock, pictured);
        }

        Item outOfStock() {
            return new Item(name, about, price, false, pictured);
        }

        Item withoutPicture() {
            return new Item(name, about, price, inStock, false);
        }

        Product build(Store shop, java.util.UUID categoryId) {
            Product product = new Product(shop.getMerchantId(), shop.getId(), name,
                    about, new BigDecimal(price), categoryId);
            product.assignCodes(SKU, BARCODE);
            // products/<productId>/<fileId>.jpg — ProductImageService.presign's prefix and
            // StorageService's own file id, so a product's id is in its photo's URL here exactly as
            // it is in production. Derived from the product id rather than random, so the same
            // shelf renders the same bytes twice and an ETag test cannot pass on noise.
            String key = "products/" + product.getId() + "/"
                    + java.util.UUID.nameUUIDFromBytes(
                            product.getId().toString().getBytes(java.nio.charset.StandardCharsets.UTF_8))
                    + ".jpg";
            product.addImage(key);
            product.publish();
            if (!pictured) {
                // A merchant who deleted the photo after listing it: live, and nothing to draw.
                product.removeImage(key);
            }
            product.applyStockProjection(inStock);
            return product;
        }
    }

    // ---------------------------------------------------------------- wiring

    MockMvc mvc() {
        return MockMvcBuilders.standaloneSetup(controller()).build();
    }

    /**
     * One controller whose memos age on the given clock, for the tests that ask what a second
     * reader inside the window costs — and what happens once the window is over.
     */
    MockMvc mvc(LongSupplier nanoClock) {
        return MockMvcBuilders.standaloneSetup(
                new PublicShopPageController(service(), BASE, IMAGE_ORIGIN, nanoClock)).build();
    }

    PublicShopPageController controller() {
        return new PublicShopPageController(service(), BASE, IMAGE_ORIGIN);
    }

    PublicShopPageService service() {
        when(stores.findBySlug(anyString())).thenReturn(Optional.empty());
        when(stores.findBySlug(shop.getSlug())).thenReturn(Optional.of(shop));
        // The sitemap's filter is SQL now, and a mock cannot prove SQL: which shops have a page is
        // asserted against a real database in PublicShopPageDatabaseTest, over rows that really do
        // include a draft, a suspended, a pinless and a closed-category shop. All this reproduces
        // is enough for the renderer's own tests — this one shop, listed when it would render.
        when(stores.findPublicPageSlugs(anyCollection(), any())).thenReturn(sitemapSlugs());
        when(stores.findPublicGoodsPageSlugs(any())).thenReturn(sitemapSlugs());

        // Truncated here because the query is: the service asks findActiveInStore for one page of
        // MAX_ITEMS, and a mock that handed back every row whatever the Pageable said would let a
        // test "prove" a cap the page does not have.
        List<Product> drawn = shelf.size() > PublicShopPageService.MAX_ITEMS
                ? List.copyOf(shelf.subList(0, PublicShopPageService.MAX_ITEMS))
                : List.copyOf(shelf);
        Page<Product> page = new PageImpl<>(drawn,
                PageRequest.of(0, PublicShopPageService.MAX_ITEMS),
                Math.max(shelfTotal, shelf.size()));
        when(products.findActiveInStore(any(), any(), anyString(), any())).thenReturn(page);

        when(categories.findByStoreIdOrderByPositionAscNameAsc(shop.getId()))
                .thenReturn(List.copyOf(ownSections));
        when(categories.findByStoreIdIsNull()).thenReturn(List.of());

        when(zones.servedAreasOf(any())).thenReturn(areas);

        when(images.resolveImage(anyString())).thenAnswer(call -> picture(call.getArgument(0)));
        when(images.resolveByKey(anyList())).thenAnswer(call -> {
            Map<String, ImageUrl> resolved = new LinkedHashMap<>();
            for (String key : call.<List<String>>getArgument(0)) {
                resolved.put(key, picture(key));
            }
            return resolved;
        });

        // Four open and three closed, which is a state an operator can really configure — plus
        // this shop's own category when it has one, so a fixture built for a service shop is not
        // silently a 404 for a reason the test was not about.
        Set<Store.ServiceCategory> open = new java.util.LinkedHashSet<>(
                Set.of(Store.ServiceCategory.PRINTING, Store.ServiceCategory.TAILORING,
                        Store.ServiceCategory.REPAIRS, Store.ServiceCategory.PHOTOGRAPHY));
        if (category != null) {
            open.add(category);
        }
        when(serviceCategories.enabled()).thenReturn(Set.copyOf(open));

        return new PublicShopPageService(stores, products, categories, zones, images,
                serviceCategories, clock, Duration.ofHours(4), rate);
    }

    /** This shop's slug when it is live and pinned — what the sitemap's query would return. */
    private List<String> sitemapSlugs() {
        boolean listed = shop.getStatus() == Store.Status.ACTIVE && shop.location() != null;
        return listed ? List.of(shop.getSlug()) : List.of();
    }

    /**
     * What {@code StorageService.readUrl} builds for a public bucket, with the derivative named by
     * {@link Thumbnailer#thumbKeyFor} rather than by a rule invented here — the fixture must not be
     * the only place on the platform where a thumbnail is called something.
     */
    private static ImageUrl picture(String key) {
        if (key == null || key.isBlank()) {
            return null;
        }
        return new ImageUrl(objectUrl(key), objectUrl(Thumbnailer.thumbKeyFor(key)));
    }

    private static String objectUrl(String key) {
        return IMAGE_ORIGIN + "/product-images/" + key;
    }
}
