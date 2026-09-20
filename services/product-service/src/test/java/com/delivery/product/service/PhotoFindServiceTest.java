package com.delivery.product.service;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicInteger;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import com.delivery.product.domain.Category;
import com.delivery.product.domain.CategoryRepository;
import com.delivery.product.domain.PhotoSearchUse.Kind;
import com.delivery.product.domain.Product;
import com.delivery.product.domain.ProductFindRepository;
import com.delivery.product.domain.ProductFindRepository.Found;
import com.delivery.product.domain.ProductRepository;
import com.delivery.product.domain.Store;
import com.delivery.product.service.CatalogService.CatalogRuleViolationException;
import com.delivery.product.service.PhotoFindService.FindResult;
import com.delivery.product.service.PhotoFindService.Match;
import com.delivery.product.vision.FakeVisionProvider;
import com.delivery.product.vision.VisionProvider;
import com.delivery.product.vision.VisionProviders;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * A merchant finding a product in their own catalogue by photo: whose shops are searched, what a match
 * is, and what a new product would start from.
 */
@DisplayName("finding a product by photo")
class PhotoFindServiceTest {

    private static final String MERCHANT = "merchant-sub";
    private static final String EAN = "5449000000996";

    private VisionProviders providers;
    private PhotoQuota quota;
    private StoreService stores;
    private ProductFindRepository finder;
    private ProductRepository products;
    private CategoryRepository categories;
    private PhotoFindService service;

    private Store grocer;
    private Store kiosk;
    private Store press;
    private final List<Product> catalogue = new ArrayList<>();
    private final AtomicInteger described = new AtomicInteger();
    private VisionProvider.ProductDescription answer;
    private String providerName = "CLAUDE";

    private final VisionProvider reader = new VisionProvider() {
        @Override
        public String name() {
            return providerName;
        }

        @Override
        public List<Detection> detect(List<ShelfPhoto> photos, List<String> categoryNames) {
            throw new AssertionError();
        }

        @Override
        public ProductDescription describe(ProductPhoto photo) {
            described.incrementAndGet();
            return answer;
        }
    };

    @BeforeEach
    void setUp() {
        providers = mock(VisionProviders.class);
        quota = mock(PhotoQuota.class);
        stores = mock(StoreService.class);
        finder = mock(ProductFindRepository.class);
        products = mock(ProductRepository.class);
        categories = mock(CategoryRepository.class);

        grocer = new Store(MERCHANT, "Corner Grocer", Store.Vertical.GROCERY);
        kiosk = new Store(MERCHANT, "Kiosk", Store.Vertical.GROCERY);
        press = new Store(MERCHANT, "Al Fakhry Press", Store.Vertical.SERVICES,
                Store.ServiceCategory.PRINTING);

        when(providers.active()).thenReturn(reader);
        when(stores.ownedBy(MERCHANT)).thenReturn(List.of(grocer, kiosk, press));
        when(quota.take(anyString(), any())).thenReturn(29);
        when(categories.findByStoreIdOrderByPositionAscNameAsc(any())).thenReturn(List.of());
        when(categories.findByStoreIdIsNull()).thenReturn(List.of());
        when(products.foldForSearch(anyString(), anyString(), anyString())).thenAnswer(call -> {
            List<String> folded = new ArrayList<>();
            for (int i = 0; i < 3; i++) {
                String term = call.getArgument(i);
                folded.add(term.toLowerCase(Locale.ROOT).replaceAll("[^\\p{L}\\p{Nd}]+", " ").strip());
            }
            return folded;
        });
        when(products.findAllById(anyList())).thenAnswer(call -> {
            List<UUID> ids = call.getArgument(0);
            return catalogue.stream().filter(p -> ids.contains(p.getId())).toList();
        });
        when(finder.findInStores(anyList(), anyString(), anyString(), anyString(), anyString(),
                anyString(), anyString(), anyString(), anyInt())).thenReturn(List.of());
        when(finder.barcodeTaken(anyList(), anyString())).thenReturn(false);
        answer = new VisionProvider.ProductDescription(true, "Pepsi 1L", "بيبسي", "Pepsi", "1 L",
                List.of("cola", "soft drink"), EAN, 0.9);

        service = new PhotoFindService(providers,
                new PhotoReader(new Thumbnailer(40_000_000L), 4, 1568, 16_000_000L), quota, stores,
                finder, products, categories);
    }

    private Product product(Store store, String name, Product.Status status) {
        Product product = new Product(MERCHANT, store.getId(), name, null, new BigDecimal("1.25"), null);
        if (status == Product.Status.ACTIVE) {
            // A product needs a photo before it may go on sale, as the catalogue insists.
            product.addImage("products/" + product.getId() + "/front.jpg");
            product.publish();
        } else if (status == Product.Status.ARCHIVED) {
            product.archive();
        }
        catalogue.add(product);
        return product;
    }

    private void answering(List<Found> rows) {
        when(finder.findInStores(anyList(), anyString(), anyString(), anyString(), anyString(),
                anyString(), anyString(), anyString(), anyInt())).thenReturn(rows);
    }

    private static byte[] photo() {
        return PhotoReaderTest.jpeg(64, 64);
    }

    // ---------------------------------------------------------------------------- whose shops

    @Test
    @DisplayName("a shop that is not the caller's is not found, and nothing is read")
    void another_merchants_shop_is_not_found() {
        assertThatThrownBy(() -> service.find(MERCHANT, photo(), UUID.randomUUID()))
                .isInstanceOf(StoreService.StoreNotFoundException.class);

        assertThat(described).hasValue(0);
        verify(quota, never()).take(anyString(), any());
    }

    @Test
    @DisplayName("a service shop is refused, as a Blitz scan of one is, before anything is read")
    void a_service_shop_is_refused() {
        assertThatThrownBy(() -> service.find(MERCHANT, photo(), press.getId()))
                .isInstanceOfSatisfying(CatalogRuleViolationException.class,
                        e -> assertThat(e.getMessage()).contains("service shop"));

        assertThat(described).hasValue(0);
    }

    @Test
    @DisplayName("a merchant with no goods shop is told to open one rather than charged for a read")
    void no_goods_shop_is_refused() {
        when(stores.ownedBy(MERCHANT)).thenReturn(List.of(press));

        assertThatThrownBy(() -> service.find(MERCHANT, photo(), null))
                .isInstanceOf(CatalogRuleViolationException.class);
        assertThat(described).hasValue(0);
    }

    @Test
    @DisplayName("with no shop named, every goods shop of the caller is searched and no service shop")
    void every_goods_shop_is_searched() {
        service.find(MERCHANT, photo(), null);

        verify(finder).findInStores(
                org.mockito.ArgumentMatchers.argThat(ids -> ids.containsAll(List.of(grocer.getId(),
                        kiosk.getId())) && !ids.contains(press.getId()) && ids.size() == 2),
                anyString(), anyString(), anyString(), anyString(), anyString(), anyString(),
                anyString(), anyInt());
        verify(quota).take(MERCHANT, Kind.MERCHANT_FIND);
    }

    // ---------------------------------------------------------------------------- what matches

    @Test
    @DisplayName("an equal barcode is the first match and says so; a name match says its own")
    void the_barcode_match_comes_first() {
        Product byCode = product(grocer, "Pepsi 1 litre", Product.Status.ACTIVE);
        Product byName = product(grocer, "Pepsi 1L bottle", Product.Status.ACTIVE);
        answering(List.of(new Found(byCode.getId(), grocer.getId(), 0, 1),
                new Found(byName.getId(), grocer.getId(), 1, 1)));

        FindResult found = service.find(MERCHANT, photo(), grocer.getId());

        assertThat(found.matches()).extracting(Match::matchedBy)
                .containsExactly(PhotoFindService.BY_BARCODE, PhotoFindService.BY_NAME);
        assertThat(found.matches().get(0).product().getName()).isEqualTo("Pepsi 1 litre");
        assertThat(found.left()).isEqualTo(29);
        assertThat(found.sample()).isFalse();
        assertThat(found.provider()).isEqualTo("CLAUDE");
    }

    @Test
    @DisplayName("a match the merchant archived comes back, with its status, rather than being hidden")
    void an_archived_match_is_still_a_match() {
        Product archived = product(grocer, "Pepsi 1L", Product.Status.ARCHIVED);
        answering(List.of(new Found(archived.getId(), grocer.getId(), 1, 1)));

        FindResult found = service.find(MERCHANT, photo(), grocer.getId());

        assertThat(found.matches()).singleElement().satisfies(match ->
                assertThat(match.product().getStatus()).isEqualTo(Product.Status.ARCHIVED));
    }

    @Test
    @DisplayName("a product that has moved to another shop since the query is not a match")
    void a_product_from_another_shop_is_dropped() {
        Product elsewhere = product(kiosk, "Pepsi 1L", Product.Status.ACTIVE);
        answering(List.of(new Found(elsewhere.getId(), grocer.getId(), 1, 1)));

        FindResult found = service.find(MERCHANT, photo(), grocer.getId());

        assertThat(found.matches()).isEmpty();
    }

    @Test
    @DisplayName("a photo of no product matches nothing and suggests nothing, and is still counted")
    void not_a_product_matches_nothing() {
        answer = new VisionProvider.ProductDescription(false, "", "", "", "", List.of(), "", 0.1);

        FindResult found = service.find(MERCHANT, photo(), grocer.getId());

        assertThat(found.understood().isProduct()).isFalse();
        assertThat(found.matches()).isEmpty();
        assertThat(found.suggestion()).isNull();
        verify(quota).take(MERCHANT, Kind.MERCHANT_FIND);
        verify(finder, never()).findInStores(anyList(), anyString(), anyString(), anyString(),
                anyString(), anyString(), anyString(), anyString(), anyInt());
    }

    // ---------------------------------------------------------------------------- what to add

    @Test
    @DisplayName("the suggestion carries the reader's name and its barcode, when nobody here has it")
    void the_suggestion_carries_the_name_and_a_free_barcode() {
        FindResult found = service.find(MERCHANT, photo(), grocer.getId());

        assertThat(found.suggestion().name()).isEqualTo("Pepsi 1L");
        assertThat(found.suggestion().barcode()).isEqualTo(EAN);
    }

    @Test
    @DisplayName("a barcode one of the shop's products already carries is left out of the suggestion")
    void a_taken_barcode_is_not_suggested() {
        when(finder.barcodeTaken(anyList(), anyString())).thenReturn(true);

        FindResult found = service.find(MERCHANT, photo(), grocer.getId());

        assertThat(found.suggestion().barcode()).isNull();
        assertThat(found.suggestion().name()).isEqualTo("Pepsi 1L");
    }

    @Test
    @DisplayName("a section is suggested only when the shop has one named exactly as a keyword")
    void the_section_comes_from_an_exact_name() {
        UUID drinks = UUID.randomUUID();
        Category section = mock(Category.class);
        when(section.getId()).thenReturn(drinks);
        when(section.getName()).thenReturn("Soft Drink");
        when(categories.findByStoreIdOrderByPositionAscNameAsc(grocer.getId()))
                .thenReturn(List.of(section));

        assertThat(service.find(MERCHANT, photo(), grocer.getId()).suggestion().categoryId())
                .isEqualTo(drinks);

        // A shelf called something else gets no guess at all.
        when(section.getName()).thenReturn("Fizzy things");
        assertThat(service.find(MERCHANT, photo(), grocer.getId()).suggestion().categoryId()).isNull();
    }

    @Test
    @DisplayName("across several shops no section is suggested, since it would belong to only one")
    void no_section_across_several_shops() {
        UUID drinks = UUID.randomUUID();
        Category section = mock(Category.class);
        when(section.getId()).thenReturn(drinks);
        when(section.getName()).thenReturn("cola");
        when(categories.findByStoreIdOrderByPositionAscNameAsc(any())).thenReturn(List.of(section));

        assertThat(service.find(MERCHANT, photo(), null).suggestion().categoryId()).isNull();
    }

    // ---------------------------------------------------------------------------- samples

    @Test
    @DisplayName("the fake reader's answer is marked as a sample, as a Blitz scan's is")
    void the_fake_is_a_sample() {
        providerName = FakeVisionProvider.NAME;

        FindResult found = service.find(MERCHANT, photo(), grocer.getId());

        assertThat(found.sample()).isTrue();
        assertThat(found.provider()).isEqualTo("FAKE");
    }
}
