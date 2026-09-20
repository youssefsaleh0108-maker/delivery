package com.delivery.product.api;

import java.math.BigDecimal;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.Executor;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.TimeUnit;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.PageRequest;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.util.unit.DataSize;

import com.delivery.product.api.dto.ItemSearchDtos.ItemSearchRequest;
import com.delivery.product.domain.GeoPoint;
import com.delivery.product.domain.Product;
import com.delivery.product.domain.Store;
import com.delivery.product.domain.TestPin;
import com.delivery.product.service.CatalogService;
import com.delivery.product.service.CatalogService.ProductView;
import com.delivery.product.service.ItemSearchService;
import com.delivery.product.service.ItemSearchService.ItemQuery;
import com.delivery.product.service.ItemSearchService.ItemSearchResult;
import com.delivery.product.service.ItemSearchService.Searched;
import com.delivery.product.service.ItemSearchService.SearchRefusedException;
import com.delivery.product.service.ItemSearchService.SearchTimedOutException;
import com.delivery.product.service.ItemSearchService.ShopMatch;
import com.delivery.product.service.ItemSearchThrottle;
import com.delivery.product.service.PhotoSearchService;
import com.delivery.product.service.PhotoSearchService.PhotoSearchResult;
import com.delivery.product.service.ProductImageService;
import com.delivery.product.service.SearchDemandRecorder;
import com.delivery.product.service.SearchDemandRecorder.Recording;
import com.delivery.product.service.StoreService;
import com.delivery.product.service.StoreService.StoreView;
import com.delivery.product.vision.Descriptions;

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
 * What reaches the demand log, and — more importantly — what a search pays for it.
 *
 * <p>Two promises are made about this feature and both are tested here rather than described:
 * <strong>a search that did not happen is not recorded</strong>, so a refusal, a timeout and a page
 * of scrolling write nothing; and <strong>recording cannot slow a search</strong>, so a writer that
 * takes a second does not add a second to the answer.
 *
 * <p>The row itself, and the fact that it carries no account, is proved against a real database in
 * {@code SearchDemandDatabaseTest}. This is about the seam between the search and the recorder.
 */
@DisplayName("recording a search for the demand digest")
class SearchDemandRecordingTest {

    private ItemSearchService itemSearch;
    private PhotoSearchService photoSearch;
    private SearchDemandRecorder demand;
    private StoreService storeService;
    private CatalogService catalog;
    private ItemSearchController items;
    private PhotoSearchController photos;
    private Store shop;

    @BeforeEach
    void setUp() {
        itemSearch = mock(ItemSearchService.class);
        photoSearch = mock(PhotoSearchService.class);
        demand = mock(SearchDemandRecorder.class);
        storeService = mock(StoreService.class);
        catalog = mock(CatalogService.class);
        when(storeService.favoriteIdsOf(any())).thenReturn(Set.of());
        when(storeService.liveOffersByStore()).thenReturn(Map.of());
        when(catalog.views(anyList())).thenAnswer(call -> call.<List<Product>>getArgument(0).stream()
                .map(p -> new ProductView(p, null, null)).toList());

        shop = new Store("merchant-sub", "Corner Grocer", Store.Vertical.GROCERY);
        shop.pinAt(GeoPoint.of(33.900800d, 35.482900d));
        shop.replaceHours(java.util.Arrays.stream(java.time.DayOfWeek.values())
                .map(day -> new com.delivery.product.domain.StoreHours(day,
                        java.time.LocalTime.MIDNIGHT, java.time.LocalTime.of(23, 59, 59)))
                .toList());
        TestPin.pinned(shop);
        shop.publish(Instant.parse("2026-01-01T00:00:00Z"));

        items = new ItemSearchController(itemSearch, storeService, catalog,
                mock(ProductImageService.class), new ItemSearchThrottle(100, 1000), demand);
        photos = new PhotoSearchController(photoSearch, storeService, catalog,
                mock(ProductImageService.class), demand, DataSize.ofMegabytes(2));
        signedInAs("customer-sub");
    }

    @AfterEach
    void signOut() {
        SecurityContextHolder.clearContext();
    }

    // ------------------------------------------------------------------- what is and is not recorded

    @Test
    @DisplayName("a search that answered is recorded once, by its folded words and what it reached")
    void a_search_is_recorded_once() {
        answering(new Searched("bebsi kola", 2, 1_840.5d,
                List.of(GeoPoint.of(33.9008d, 35.4829d), GeoPoint.of(33.8860d, 35.5160d))));

        items.items(pepsiNearHamra(0));

        Recording recorded = captured();
        assertThat(recorded.term()).isEqualTo("bebsi kola");
        assertThat(recorded.shops()).isEqualTo(2);
        assertThat(recorded.nearest()).isEqualTo(1_840.5d);
        assertThat(recorded.answering()).hasSize(2);
        // The pin is handed over to be turned into a neighbourhood, and the account only so the
        // recorder can collapse this person's own repeats. Neither is ever written down — see
        // SearchDemandDatabaseTest, which asserts the columns that exist.
        assertThat(recorded.pin()).isEqualTo(GeoPoint.of(33.8977d, 35.4829d));
        assertThat(recorded.accountId()).isEqualTo("customer-sub");
    }

    @Test
    @DisplayName("a refused search records nothing")
    void a_refused_search_records_nothing() {
        when(itemSearch.search(any(), any(), anyInt(), anyInt()))
                .thenThrow(new SearchRefusedException("SEARCH_TOO_SHORT", "too short"));

        assertThatThrownBy(() -> items.items(pepsiNearHamra(0)))
                .isInstanceOf(SearchRefusedException.class);

        verify(demand, never()).record(any());
    }

    @Test
    @DisplayName("a search the database gave up on records nothing")
    void a_timed_out_search_records_nothing() {
        when(itemSearch.search(any(), any(), anyInt(), anyInt()))
                .thenThrow(new SearchTimedOutException(new RuntimeException("cancelled")));

        assertThatThrownBy(() -> items.items(pepsiNearHamra(0)))
                .isInstanceOf(SearchTimedOutException.class);

        verify(demand, never()).record(any());
    }

    @Test
    @DisplayName("a malformed search is refused before it is recorded, and before it is searched")
    void a_malformed_search_records_nothing() {
        assertThatThrownBy(() -> items.items(
                new ItemSearchRequest("p", null, null, null, null, 0, 10)))
                .isInstanceOf(SearchRefusedException.class);

        verify(itemSearch, never()).search(any(), any(), anyInt(), anyInt());
        verify(demand, never()).record(any());
    }

    @Test
    @DisplayName("scrolling to the second page is the same search, and is not recorded again")
    void paging_is_not_a_second_search() {
        answering(new Searched("pepsi", 12, 300d, List.of()));

        items.items(pepsiNearHamra(0));
        items.items(pepsiNearHamra(1));
        items.items(pepsiNearHamra(2));

        verify(demand).record(any());
    }

    @Test
    @DisplayName("a photo search is recorded by the words the reader understood, once")
    void a_photo_search_is_recorded_by_its_words() {
        ItemSearchResult result = new ItemSearchResult(
                new PageImpl<>(List.of(new ShopMatch(
                        new StoreView(shop, Store.Availability.OPEN, null, false), 345.4d,
                        List.of(), 1)), PageRequest.of(0, 10), 1), false, 300, true,
                new Searched("pampers size 4", 1, 345.4d, List.of(GeoPoint.of(33.9008d, 35.4829d))));
        Descriptions.Clean understood = new Descriptions.Clean(true, "Pampers", "حفاضات", "Pampers",
                "size 4", List.of("nappies"), null, new BigDecimal("0.900"));
        when(photoSearch.available()).thenReturn(true);
        when(photoSearch.search(anyString(), any(), any(), anyInt())).thenReturn(
                new PhotoSearchResult(understood, result, false,
                        ItemQuery.of(null, List.of("pampers size 4"), null), 7));

        photos.photo(new org.springframework.mock.web.MockMultipartFile("photo", "p.jpg",
                        "image/jpeg", new byte[] {(byte) 0xFF, (byte) 0xD8, (byte) 0xFF, (byte) 0xE0, 0, 16}),
                new BigDecimal("33.8977"), new BigDecimal("35.4829"));

        Recording recorded = captured();
        assertThat(recorded.term()).isEqualTo("pampers size 4");
        assertThat(recorded.shops()).isEqualTo(1);
    }

    // ------------------------------------------------------------------------ what it costs a search

    @Test
    @DisplayName("a write that takes a second does not take a second off the customer's answer")
    void a_slow_write_never_delays_the_answer() throws Exception {
        CountDownLatch writing = new CountDownLatch(1);
        CountDownLatch release = new CountDownLatch(1);
        Executor slow = runnable -> {
            Thread thread = new Thread(() -> {
                writing.countDown();
                try {
                    release.await(5, TimeUnit.SECONDS);
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                }
                runnable.run();
            });
            thread.setDaemon(true);
            thread.start();
        };
        SearchDemandRecorder real = new SearchDemandRecorder(null, null, new com.delivery.product.service.SeenKeys(""), null,
                null, java.time.Clock.systemUTC(), null, slow, Duration.ZERO, 1, Duration.ZERO);
        ItemSearchController controller = new ItemSearchController(itemSearch, storeService, catalog,
                mock(ProductImageService.class), new ItemSearchThrottle(100, 1000), real);
        answering(new Searched("pepsi", 0, null, List.of()));

        long started = System.nanoTime();
        controller.items(pepsiNearHamra(0));
        Duration answered = Duration.ofNanos(System.nanoTime() - started);

        // The writer has started and is still blocked; the customer already has their answer.
        assertThat(writing.await(5, TimeUnit.SECONDS)).isTrue();
        assertThat(answered).isLessThan(Duration.ofMillis(500));
        release.countDown();
    }

    @Test
    @DisplayName("a recorder with nowhere to put the work drops it, and the search never hears about it")
    void a_full_queue_is_dropped_not_thrown() {
        Executor full = runnable -> {
            throw new RejectedExecutionException("queue full");
        };
        SearchDemandRecorder real = new SearchDemandRecorder(null, null, new com.delivery.product.service.SeenKeys(""), null,
                null, java.time.Clock.systemUTC(), null, full, Duration.ZERO, 1, Duration.ZERO);

        real.record(new Recording("a", "rice", null, 0, null, List.of(), null));

        assertThat(real.counts().refused()).isEqualTo(1);
        assertThat(real.counts().written()).isZero();
    }

    @Test
    @DisplayName("a write that fails is swallowed: the search it describes answered long ago")
    void a_failed_write_is_swallowed() {
        // No repository and no transaction manager: every write fails as hard as it can.
        SearchDemandRecorder real = new SearchDemandRecorder(null, null, new com.delivery.product.service.SeenKeys(""), null,
                null, java.time.Clock.systemUTC(), null, Runnable::run, Duration.ZERO, 1, Duration.ZERO);

        real.record(new Recording("a", "rice", null, 0, null, List.of(), null));

        assertThat(real.counts().failed()).isEqualTo(1);
    }

    @Test
    @DisplayName("a search with no words — a barcode on its own — has nothing to record")
    void a_wordless_search_is_not_recorded() {
        SearchDemandRecorder real = new SearchDemandRecorder(null, null, new com.delivery.product.service.SeenKeys(""), null,
                null, java.time.Clock.systemUTC(), null, Runnable::run, Duration.ZERO, 1, Duration.ZERO);

        real.record(new Recording("a", "", null, 0, null, List.of(), null));

        assertThat(real.counts()).isEqualTo(new SearchDemandRecorder.Counts(0, 0, 0, 0, 0));
    }

    // ------------------------------------------------------------------------------------ helpers

    private void answering(Searched searched) {
        ShopMatch match = new ShopMatch(new StoreView(shop, Store.Availability.OPEN, null, false),
                searched.nearest(), List.of(), 1);
        when(itemSearch.search(any(), any(), anyInt(), anyInt())).thenReturn(new ItemSearchResult(
                new PageImpl<>(searched.shops() == 0 ? List.of() : List.of(match),
                        PageRequest.of(0, 10), searched.shops()), false, 300, true, searched));
    }

    private Recording captured() {
        org.mockito.ArgumentCaptor<Recording> captor =
                org.mockito.ArgumentCaptor.forClass(Recording.class);
        verify(demand).record(captor.capture());
        return captor.getValue();
    }

    private static ItemSearchRequest pepsiNearHamra(int page) {
        return new ItemSearchRequest("pepsi", null, null, new BigDecimal("33.8977"),
                new BigDecimal("35.4829"), page, 10);
    }

    private static void signedInAs(String subject) {
        Jwt jwt = Jwt.withTokenValue("token").header("alg", "none").subject(subject).build();
        SecurityContextHolder.getContext().setAuthentication(new JwtAuthenticationToken(jwt,
                List.of(new SimpleGrantedAuthority("ROLE_CUSTOMER"))));
    }
}
