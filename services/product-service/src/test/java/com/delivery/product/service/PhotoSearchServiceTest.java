package com.delivery.product.service;

import java.math.BigDecimal;
import java.time.DayOfWeek;
import java.time.Instant;
import java.time.LocalTime;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Optional;
import java.util.concurrent.atomic.AtomicInteger;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.PageRequest;
import org.springframework.mock.env.MockEnvironment;

import com.delivery.product.domain.GeoPoint;
import com.delivery.product.domain.PhotoSearchUse.Kind;
import com.delivery.product.domain.Product;
import com.delivery.product.domain.ProductRepository;
import com.delivery.product.domain.Store;
import com.delivery.product.domain.StoreHours;
import com.delivery.product.service.ItemSearchService.ItemQuery;
import com.delivery.product.service.ItemSearchService.ItemSearchResult;
import com.delivery.product.service.ItemSearchService.ShopMatch;
import com.delivery.product.service.PhotoSearchException.Refusal;
import com.delivery.product.service.PhotoSearchService.PhotoSearchResult;
import com.delivery.product.service.StoreService.StoreView;
import com.delivery.product.vision.VisionProvider;
import com.delivery.product.vision.VisionProviders;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.argThat;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

/**
 * A customer's search by photo: never a sample reader, the item search on what the photo was read as,
 * and its keywords when that finds nothing.
 */
@DisplayName("searching the shops by photo")
class PhotoSearchServiceTest {

    private static final GeoPoint HAMRA = GeoPoint.of(33.897700d, 35.482900d);

    private VisionProviders providers;
    private PhotoQuota quota;
    private ItemSearchService itemSearch;
    private ProductRepository products;
    private MockEnvironment environment;
    private PhotoSearchService service;

    private final AtomicInteger described = new AtomicInteger();
    private VisionProvider.ProductDescription answer;

    private final VisionProvider claude = new VisionProvider() {
        @Override
        public String name() {
            return "CLAUDE";
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
        itemSearch = mock(ItemSearchService.class);
        products = mock(ProductRepository.class);
        environment = new MockEnvironment();
        // The database's fold, near enough for these words: lower case, anything else a space.
        when(products.foldForSearch(anyString(), anyString(), anyString())).thenAnswer(call -> {
            List<String> folded = new ArrayList<>();
            for (int i = 0; i < 3; i++) {
                String term = call.getArgument(i);
                folded.add(term.toLowerCase(Locale.ROOT).replaceAll("[^\\p{L}\\p{Nd}]+", " ").strip());
            }
            return folded;
        });
        when(quota.take(anyString(), any())).thenReturn(7);
        when(itemSearch.nothing(any(), anyInt())).thenAnswer(call -> result(0));
        when(providers.real()).thenReturn(Optional.of(claude));
        answer = new VisionProvider.ProductDescription(true, "Pepsi 1L", "بيبسي", "Pepsi", "1 L",
                List.of("cola", "soft drink", "كولا", "مشروب غازي"), "5449000000996", 0.9);

        service = new PhotoSearchService(providers,
                new PhotoReader(new Thumbnailer(40_000_000L), 4, 1568, 16_000_000L), quota, itemSearch,
                products, environment);
    }

    /** A page of {@code shops} shops, or none. */
    private static ItemSearchResult result(int shops) {
        List<ShopMatch> matches = new ArrayList<>();
        for (int i = 0; i < shops; i++) {
            Store store = new Store("merchant-" + i, "Shop " + i, Store.Vertical.GROCERY);
            store.replaceHours(List.of(new StoreHours(DayOfWeek.MONDAY, LocalTime.of(8, 0), LocalTime.of(22, 0))));
            store.publish(Instant.parse("2026-01-01T00:00:00Z"));
            Product product = new Product(store.getMerchantId(), store.getId(), "Pepsi 1L", null,
                    new BigDecimal("1.25"), null);
            matches.add(new ShopMatch(new StoreView(store, Store.Availability.OPEN, null, false), 300d,
                    List.of(product), 1));
        }
        return new ItemSearchResult(new PageImpl<>(matches, PageRequest.of(0, 10), matches.size()), false, 300,
                true);
    }

    private static byte[] photo() {
        return PhotoReaderTest.jpeg(64, 64);
    }

    @Test
    @DisplayName("with only the sample reader configured, it is unavailable and nobody is asked anything")
    void the_fake_alone_is_unavailable() {
        when(providers.real()).thenReturn(Optional.empty());

        assertThat(service.available()).isFalse();
        assertThatThrownBy(() -> service.search("customer-1", photo(), HAMRA, 10))
                .isInstanceOfSatisfying(PhotoSearchException.class, e -> {
                    assertThat(e.refusal()).isEqualTo(Refusal.UNAVAILABLE);
                    assertThat(e.refusal().status()).isEqualTo(503);
                });
        assertThat(described).hasValue(0);
        verifyNoInteractions(quota, itemSearch);
    }

    @Test
    @DisplayName("switched off for customers, it is unavailable even with a real reader")
    void switched_off_is_unavailable() {
        environment.setProperty(PhotoSearchService.CUSTOMER_ENABLED, "false");

        assertThat(service.available()).isFalse();
        assertThatThrownBy(() -> service.search("customer-1", photo(), HAMRA, 10))
                .isInstanceOfSatisfying(PhotoSearchException.class,
                        e -> assertThat(e.refusal()).isEqualTo(Refusal.UNAVAILABLE));
        assertThat(described).hasValue(0);
    }

    @Test
    @DisplayName("a product is searched by its name, Arabic name and brand with its barcode, counted once")
    void a_product_is_searched_by_its_words_and_barcode() {
        when(itemSearch.search(any(), any(), anyInt(), anyInt())).thenReturn(result(2));

        PhotoSearchResult found = service.search("customer-1", photo(), HAMRA, 10);

        assertThat(found.similar()).isFalse();
        assertThat(found.left()).isEqualTo(7);
        assertThat(found.understood().name()).isEqualTo("Pepsi 1L");
        assertThat(found.result().page().getContent()).hasSize(2);
        assertThat(found.nextQuery().terms()).containsExactly("pepsi 1l", "بيبسي", "pepsi");
        assertThat(found.nextQuery().barcode()).isEqualTo("5449000000996");
        verify(itemSearch).search(eq(found.nextQuery()), eq(HAMRA), eq(0), eq(10));
        verify(quota).take("customer-1", Kind.CUSTOMER_SEARCH);
        assertThat(described).hasValue(1);
    }

    @Test
    @DisplayName("when nothing sells the product, its keywords are searched and the answer is similar")
    void nothing_exact_falls_back_to_keywords() {
        when(itemSearch.search(argThat(q -> q != null && q.barcode() != null), any(), anyInt(), anyInt()))
                .thenReturn(result(0));
        when(itemSearch.search(argThat(q -> q != null && q.barcode() == null), any(), anyInt(), anyInt()))
                .thenReturn(result(3));

        PhotoSearchResult found = service.search("customer-1", photo(), HAMRA, 10);

        assertThat(found.similar()).isTrue();
        assertThat(found.result().page().getContent()).hasSize(3);
        // Three slots: the first three keywords, in both languages, and never the barcode.
        assertThat(found.nextQuery().terms()).containsExactly("cola", "soft drink", "كولا");
        assertThat(found.nextQuery().barcode()).isNull();
    }

    @Test
    @DisplayName("when neither finds anything, the answer is the product's own empty search, not similar")
    void nothing_at_all_is_the_exact_empty_answer() {
        when(itemSearch.search(any(), any(), anyInt(), anyInt())).thenReturn(result(0));

        PhotoSearchResult found = service.search("customer-1", photo(), HAMRA, 10);

        assertThat(found.similar()).isFalse();
        assertThat(found.result().page().getContent()).isEmpty();
        assertThat(found.nextQuery().barcode()).isEqualTo("5449000000996");
    }

    @Test
    @DisplayName("a photo of no product is an empty answer, still counted, and nothing is searched")
    void not_a_product_searches_nothing() {
        answer = new VisionProvider.ProductDescription(false, "", "", "", "", List.of(), "", 0.1);

        PhotoSearchResult found = service.search("customer-1", photo(), null, 10);

        assertThat(found.understood().isProduct()).isFalse();
        assertThat(found.result().page().getContent()).isEmpty();
        assertThat(found.nextQuery()).isNull();
        assertThat(found.left()).isEqualTo(7);
        verify(itemSearch, never()).search(any(), any(), anyInt(), anyInt());
        verify(quota).take("customer-1", Kind.CUSTOMER_SEARCH);
    }

    @Test
    @DisplayName("a reader's long name is cut to the five words the search takes, not refused")
    void long_names_are_cut_to_five_words() {
        answer = new VisionProvider.ProductDescription(true, "Nido Fortified Full Cream Milk Powder 900g",
                null, "Nido", null, List.of(), null, 0.9);
        when(itemSearch.search(any(), any(), anyInt(), anyInt())).thenReturn(result(1));

        PhotoSearchResult found = service.search("customer-1", photo(), HAMRA, 10);

        assertThat(found.nextQuery().terms()).containsExactly("nido fortified full cream milk", "nido");
        // Page two goes to the text search with these very terms, which it accepts as they are.
        ItemQuery again = ItemQuery.of(null, found.nextQuery().terms(), found.nextQuery().barcode());
        assertThat(again).isEqualTo(found.nextQuery());
    }

    @Test
    @DisplayName("a term is spelled as the search spells it, and one with no word of two letters is dropped")
    void searchable_terms() {
        assertThat(PhotoSearchService.searchable("pepsi 1 l")).isEqualTo("pepsi 1 l");
        assertThat(PhotoSearchService.searchable("1 l")).isNull();
        assertThat(PhotoSearchService.searchable("a")).isNull();
        assertThat(PhotoSearchService.searchable("")).isNull();
        assertThat(PhotoSearchService.searchable("a b c dd ee ff gg hh ii")).isEqualTo("a b c dd ee ff gg hh");
        String longest = PhotoSearchService.searchable("abcdefghij ".repeat(4).strip() + " " + "x".repeat(95));
        assertThat(longest).isEqualTo("abcdefghij abcdefghij abcdefghij abcdefghij");
    }

    @Test
    @DisplayName("the account's photos left today come from the quota, without counting one")
    void photos_left_today() {
        when(quota.left("customer-1", Kind.CUSTOMER_SEARCH)).thenReturn(4);

        assertThat(service.left("customer-1")).isEqualTo(4);
        verify(quota, never()).take(anyString(), any());
    }
}
