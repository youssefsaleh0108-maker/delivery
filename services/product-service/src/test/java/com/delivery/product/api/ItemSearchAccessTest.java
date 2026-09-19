package com.delivery.product.api;

import java.math.BigDecimal;
import java.time.DayOfWeek;
import java.time.Instant;
import java.time.LocalTime;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.aop.framework.ProxyFactory;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.PageRequest;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.http.ResponseEntity;
import org.springframework.security.authentication.AuthenticationCredentialsNotFoundException;
import org.springframework.security.authorization.method.AuthorizationManagerBeforeMethodInterceptor;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;

import com.delivery.product.api.dto.ItemSearchDtos.ItemSearchPageResponse;
import com.delivery.product.api.dto.ItemSearchDtos.ItemSearchRequest;
import com.delivery.product.api.dto.ItemSearchDtos.ShopItemsResponse;
import com.delivery.product.domain.GeoPoint;
import com.delivery.product.domain.Product;
import com.delivery.product.domain.Store;
import com.delivery.product.domain.StoreHours;
import com.delivery.product.service.CatalogService;
import com.delivery.product.service.CatalogService.ProductView;
import com.delivery.product.service.ItemSearchService;
import com.delivery.product.service.ItemSearchService.ItemQuery;
import com.delivery.product.service.ItemSearchService.ItemSearchResult;
import com.delivery.product.service.ItemSearchService.SearchRefusedException;
import com.delivery.product.service.ItemSearchService.SearchTimedOutException;
import com.delivery.product.service.ItemSearchService.ShopMatch;
import com.delivery.product.service.ItemSearchThrottle;
import com.delivery.product.service.ItemSearchThrottle.SearchThrottledException;
import com.delivery.product.service.ProductImageService;
import com.delivery.product.service.StoreService;
import com.delivery.product.service.StoreService.StoreView;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * {@code POST /api/products/search/items}: who may search, and what the answer says.
 *
 * <p>The controller is wrapped in Spring Security's real {@code @PreAuthorize} interceptor, as in
 * {@code DeliveryZoneAroundAccessTest}, so the rule is exercised rather than read off the annotation.
 * Any signed-in caller may search, whatever their role, and a caller who is not signed in is refused
 * before anything is read: a point is where somebody is standing. One account may search a person's
 * share, and past it is refused before anything is read too.
 */
@DisplayName("searching items, over the API")
class ItemSearchAccessTest {

    private ItemSearchService itemSearch;
    private StoreService storeService;
    private CatalogService catalog;
    private ItemSearchController controller;

    /** Three searches at once, then one a minute: a limit a test reaches in a few calls. */
    private static final int BURST = 3;

    private Store shop;
    private Product pepsi;

    @BeforeEach
    void setUp() {
        itemSearch = mock(ItemSearchService.class);
        storeService = mock(StoreService.class);
        catalog = mock(CatalogService.class);

        shop = new Store("merchant-sub", "Corner Grocer", Store.Vertical.GROCERY);
        shop.pinAt(GeoPoint.of(33.900800d, 35.482900d));
        shop.replaceHours(List.of(new StoreHours(DayOfWeek.MONDAY, LocalTime.of(8, 0),
                LocalTime.of(22, 0))));
        shop.publish(Instant.parse("2026-01-01T00:00:00Z"));
        pepsi = new Product("merchant-sub", shop.getId(), "Pepsi 1L", null, new BigDecimal("1.25"), null);

        when(storeService.favoriteIdsOf(any())).thenReturn(Set.of(shop.getId()));
        when(storeService.liveOffersByStore()).thenReturn(Map.of());
        when(catalog.views(anyList())).thenAnswer(call -> call.<List<Product>>getArgument(0).stream()
                .map(p -> new ProductView(p, null, null)).toList());
        answering(true, 345.4d);

        ProxyFactory secured = new ProxyFactory(new ItemSearchController(itemSearch, storeService,
                catalog, mock(ProductImageService.class), new ItemSearchThrottle(BURST, 1)));
        secured.setProxyTargetClass(true);
        secured.addAdvisor(AuthorizationManagerBeforeMethodInterceptor.preAuthorize());
        controller = (ItemSearchController) secured.getProxy();
    }

    @AfterEach
    void signOut() {
        SecurityContextHolder.clearContext();
    }

    /** The service answers one shop with Pepsi in it, 7 matches there in all. */
    private void answering(boolean nearby, Double metres) {
        StoreView view = new StoreView(shop, Store.Availability.BUSY, null, false);
        ShopMatch match = new ShopMatch(view, nearby ? metres : null, List.of(pepsi), 7);
        when(itemSearch.search(any(), any(), anyInt(), anyInt())).thenReturn(new ItemSearchResult(
                new PageImpl<>(List.of(match), PageRequest.of(0, 10), 1), false, 300, nearby));
    }

    private static void signedInAs(String subject, String... roles) {
        Jwt jwt = Jwt.withTokenValue("token").header("alg", "none").subject(subject).build();
        SecurityContextHolder.getContext().setAuthentication(new JwtAuthenticationToken(jwt,
                java.util.Arrays.stream(roles).map(r -> new SimpleGrantedAuthority("ROLE_" + r))
                        .toList()));
    }

    private static ItemSearchRequest pepsiNearHamra() {
        return new ItemSearchRequest("pepsi", null, null, new BigDecimal("33.8977"),
                new BigDecimal("35.4829"), 0, 10);
    }

    // ------------------------------------------------------------------------------------ who

    @ParameterizedTest
    @ValueSource(strings = {"CUSTOMER", "MERCHANT", "MERCHANT_STAFF", "RIDER", "BACKOFFICE"})
    @DisplayName("any signed-in role may search")
    void any_signed_in_role_may_search(String role) {
        signedInAs("someone-" + role, role);

        assertThat(controller.items(pepsiNearHamra()).content()).hasSize(1);
    }

    @Test
    @DisplayName("so may a signed-in account with no role yet")
    void a_signed_in_account_with_no_role_may_search() {
        signedInAs("new-customer");

        assertThat(controller.items(pepsiNearHamra()).content()).hasSize(1);
    }

    @Test
    @DisplayName("a caller who is not signed in is refused before anything is read")
    void a_caller_who_is_not_signed_in_is_refused() {
        assertThatThrownBy(() -> controller.items(pepsiNearHamra()))
                .isInstanceOf(AuthenticationCredentialsNotFoundException.class);
        verify(itemSearch, never()).search(any(), any(), anyInt(), anyInt());
    }

    // ------------------------------------------------------------------------------------ what

    @Test
    @DisplayName("the answer is the shop's card, its pin, the distance in whole metres, its items and a count")
    void the_answer_carries_the_card_the_items_and_the_count() {
        signedInAs("customer-sub", "CUSTOMER");

        ItemSearchPageResponse page = controller.items(pepsiNearHamra());

        ShopItemsResponse group = page.content().get(0);
        assertThat(group.store().name()).isEqualTo("Corner Grocer");
        assertThat(group.store().availability()).isEqualTo(Store.Availability.BUSY);
        assertThat(group.store().favorite()).isTrue();
        assertThat(group.latitude()).isEqualByComparingTo("33.900800");
        assertThat(group.distanceMetres()).isEqualTo(345L);
        assertThat(group.items()).extracting(p -> p.name()).containsExactly("Pepsi 1L");
        // The price is the product's own, as the shelf shows it.
        assertThat(group.items().get(0).price()).isEqualByComparingTo("1.25");
        assertThat(group.matchedInStore()).isEqualTo(7);
        assertThat(page.nearby()).isTrue();
        assertThat(page.truncated()).isFalse();
        assertThat(page.candidateLimit()).isEqualTo(300);
        assertThat(page.totalElements()).isEqualTo(1);
    }

    @Test
    @DisplayName("without a point the search is not near anything, and no shop has a distance")
    void without_a_point_no_distance() {
        signedInAs("customer-sub", "CUSTOMER");
        answering(false, null);

        ItemSearchPageResponse page = controller.items(
                new ItemSearchRequest("pepsi", null, null, null, null, null, null));

        assertThat(page.nearby()).isFalse();
        assertThat(page.content().get(0).distanceMetres()).isNull();
        verify(itemSearch).search(any(ItemQuery.class), isNull(), eq(0),
                eq(ItemSearchController.DEFAULT_PAGE_SIZE));
    }

    @Test
    @DisplayName("half a point is refused as an invalid location, before anything is searched")
    void half_a_point_is_refused() {
        signedInAs("customer-sub", "CUSTOMER");

        assertThatThrownBy(() -> controller.items(new ItemSearchRequest("pepsi", null, null,
                new BigDecimal("33.8977"), null, 0, 10)))
                .isInstanceOf(GeoPoint.InvalidCoordinateException.class);
        verify(itemSearch, never()).search(any(), any(), anyInt(), anyInt());
    }

    @Test
    @DisplayName("a search too short to run is a 400 with a code a client can branch on")
    void a_short_search_is_a_400_with_a_code() {
        signedInAs("customer-sub", "CUSTOMER");

        assertThatThrownBy(() -> controller.items(new ItemSearchRequest("p", null, null, null, null,
                0, 10)))
                .isInstanceOfSatisfying(SearchRefusedException.class, e -> {
                    ProblemDetail problem = new ApiExceptionHandler().onSearchRefused(e);
                    assertThat(problem.getStatus()).isEqualTo(HttpStatus.BAD_REQUEST.value());
                    assertThat(problem.getProperties()).containsEntry("code", "SEARCH_TOO_SHORT");
                });
        assertThatThrownBy(() -> controller.items(new ItemSearchRequest(null, null, "12AB", null, null,
                0, 10)))
                .isInstanceOfSatisfying(SearchRefusedException.class,
                        e -> assertThat(new ApiExceptionHandler().onSearchRefused(e).getProperties())
                                .containsEntry("code", "SEARCH_BAD_BARCODE"));
        verify(itemSearch, never()).search(any(), any(), anyInt(), anyInt());
    }

    // ------------------------------------------------------------------------------------ how often

    @Test
    @DisplayName("an account past its share of searches is refused with 429, a code and the wait, unsearched")
    void an_account_that_searches_too_often_is_refused_with_the_wait() {
        signedInAs("busy-customer", "CUSTOMER");
        for (int i = 0; i < BURST; i++) {
            controller.items(pepsiNearHamra());
        }

        assertThatThrownBy(() -> controller.items(pepsiNearHamra()))
                .isInstanceOfSatisfying(SearchThrottledException.class, e -> {
                    ResponseEntity<ProblemDetail> answer = new ApiExceptionHandler().onSearchThrottled(e);
                    assertThat(answer.getStatusCode().value()).isEqualTo(HttpStatus.TOO_MANY_REQUESTS.value());
                    assertThat(answer.getBody().getProperties())
                            .containsEntry("code", "SEARCH_RATE_LIMITED")
                            .containsEntry("retryAfterSeconds", 60L);
                    assertThat(answer.getHeaders().getFirst(HttpHeaders.RETRY_AFTER)).isEqualTo("60");
                });
        verify(itemSearch, times(BURST)).search(any(), any(), anyInt(), anyInt());

        // Counted per account: somebody else searching is not held up.
        signedInAs("another-customer", "CUSTOMER");
        assertThat(controller.items(pepsiNearHamra()).content()).hasSize(1);
    }

    /** A request refused as malformed never reached the database, so it costs the customer nothing. */
    @Test
    @DisplayName("a malformed search does not count against the account")
    void a_malformed_search_does_not_count() {
        signedInAs("clumsy-customer", "CUSTOMER");
        for (int i = 0; i < BURST + 2; i++) {
            assertThatThrownBy(() -> controller.items(new ItemSearchRequest("p", null, null, null, null,
                    0, 10))).isInstanceOf(SearchRefusedException.class);
        }

        for (int i = 0; i < BURST; i++) {
            assertThat(controller.items(pepsiNearHamra()).content()).hasSize(1);
        }
    }

    @Test
    @DisplayName("a search the database gave up on is a 503 with a code and a Retry-After, never the query")
    void a_search_the_database_gave_up_on_is_a_503() {
        signedInAs("customer-sub", "CUSTOMER");
        when(itemSearch.search(any(), any(), anyInt(), anyInt()))
                .thenThrow(new SearchTimedOutException(new RuntimeException("57014")));

        assertThatThrownBy(() -> controller.items(pepsiNearHamra()))
                .isInstanceOfSatisfying(SearchTimedOutException.class, e -> {
                    ResponseEntity<ProblemDetail> answer = new ApiExceptionHandler().onSearchTimedOut(e);
                    assertThat(answer.getStatusCode().value())
                            .isEqualTo(HttpStatus.SERVICE_UNAVAILABLE.value());
                    assertThat(answer.getBody().getProperties()).containsEntry("code", "SEARCH_TIMED_OUT");
                    assertThat(answer.getHeaders().getFirst(HttpHeaders.RETRY_AFTER)).isEqualTo("5");
                    assertThat(answer.getBody().getDetail()).doesNotContain("pepsi");
                });
    }
}
