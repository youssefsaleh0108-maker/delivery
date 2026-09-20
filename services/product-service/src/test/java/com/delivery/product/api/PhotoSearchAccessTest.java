package com.delivery.product.api;

import java.lang.reflect.Constructor;
import java.lang.reflect.Field;
import java.math.BigDecimal;
import java.time.DayOfWeek;
import java.time.Instant;
import java.time.LocalTime;
import java.util.Arrays;
import java.util.List;
import java.util.Map;
import java.util.Set;

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
import org.springframework.http.ProblemDetail;
import org.springframework.http.ResponseEntity;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.authentication.AuthenticationCredentialsNotFoundException;
import org.springframework.security.authorization.method.AuthorizationManagerBeforeMethodInterceptor;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.util.unit.DataSize;
import org.springframework.web.multipart.MaxUploadSizeExceededException;

import com.delivery.platform.storage.StorageService;
import com.delivery.product.api.dto.PhotoSearchDtos.PhotoCapabilitiesResponse;
import com.delivery.product.api.dto.PhotoSearchDtos.PhotoSearchResponse;
import com.delivery.product.domain.GeoPoint;
import com.delivery.product.domain.Product;
import com.delivery.product.domain.Store;
import com.delivery.product.domain.StoreHours;
import com.delivery.product.service.CatalogService;
import com.delivery.product.service.CatalogService.ProductView;
import com.delivery.product.service.ImageObjectStore;
import com.delivery.product.service.ItemSearchService.ItemQuery;
import com.delivery.product.service.ItemSearchService.ItemSearchResult;
import com.delivery.product.service.ItemSearchService.ShopMatch;
import com.delivery.product.service.PhotoQuota;
import com.delivery.product.service.PhotoReader;
import com.delivery.product.service.PhotoSearchException;
import com.delivery.product.service.PhotoSearchService;
import com.delivery.product.service.PhotoSearchService.PhotoSearchResult;
import com.delivery.product.service.ProductImageService;
import com.delivery.product.service.SearchDemandRecorder;
import com.delivery.product.service.StoreService;
import com.delivery.product.service.StoreService.StoreView;
import com.delivery.product.vision.Descriptions;
import com.fasterxml.jackson.databind.ObjectMapper;

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
 * {@code POST /api/products/search/photo} and {@code GET /api/products/search/capabilities}: who may
 * search by photo, what the answer says, and how each refusal reaches the app.
 *
 * <p>The controller is wrapped in Spring Security's real {@code @PreAuthorize} interceptor, as in
 * {@code ItemSearchAccessTest}, so the rule is exercised rather than read off the annotation. Only a
 * customer may search by photo: each photo is a paid read against the customer's own allowance.
 */
@DisplayName("searching by photo, over the API")
class PhotoSearchAccessTest {

    private static final byte[] JPEG_START = {(byte) 0xFF, (byte) 0xD8, (byte) 0xFF, (byte) 0xE0, 0, 16};

    private PhotoSearchService photoSearch;
    private PhotoSearchController controller;
    private Store shop;

    @BeforeEach
    void setUp() {
        photoSearch = mock(PhotoSearchService.class);
        StoreService storeService = mock(StoreService.class);
        CatalogService catalog = mock(CatalogService.class);
        when(storeService.favoriteIdsOf(any())).thenReturn(Set.of());
        when(storeService.liveOffersByStore()).thenReturn(Map.of());
        when(catalog.views(anyList())).thenAnswer(call -> call.<List<Product>>getArgument(0).stream()
                .map(p -> new ProductView(p, null, null)).toList());

        shop = new Store("merchant-sub", "Corner Grocer", Store.Vertical.GROCERY);
        shop.pinAt(GeoPoint.of(33.900800d, 35.482900d));
        shop.replaceHours(List.of(new StoreHours(DayOfWeek.MONDAY, LocalTime.of(8, 0), LocalTime.of(22, 0))));
        shop.publish(Instant.parse("2026-01-01T00:00:00Z"));
        Product pepsi = new Product("merchant-sub", shop.getId(), "Pepsi 1L", null, new BigDecimal("1.25"), null);
        ItemSearchResult result = new ItemSearchResult(new PageImpl<>(List.of(new ShopMatch(
                new StoreView(shop, Store.Availability.OPEN, null, false), 345.4d, List.of(pepsi), 2)),
                PageRequest.of(0, 10), 1), false, 300, true);
        Descriptions.Clean understood = new Descriptions.Clean(true, "Pepsi 1L", "بيبسي", "Pepsi", "1 L",
                List.of("cola"), null, new BigDecimal("0.900"));

        when(photoSearch.available()).thenReturn(true);
        when(photoSearch.left(anyString())).thenReturn(8);
        when(photoSearch.search(anyString(), any(), any(), anyInt())).thenReturn(new PhotoSearchResult(
                understood, result, false, ItemQuery.of(null, List.of("pepsi 1l", "بيبسي", "pepsi"), null), 7));

        ProxyFactory secured = new ProxyFactory(new PhotoSearchController(photoSearch, storeService, catalog,
                mock(ProductImageService.class), mock(SearchDemandRecorder.class),
                DataSize.ofMegabytes(2)));
        secured.setProxyTargetClass(true);
        secured.addAdvisor(AuthorizationManagerBeforeMethodInterceptor.preAuthorize());
        controller = (PhotoSearchController) secured.getProxy();
    }

    @AfterEach
    void signOut() {
        SecurityContextHolder.clearContext();
    }

    private static void signedInAs(String subject, String... roles) {
        Jwt jwt = Jwt.withTokenValue("token").header("alg", "none").subject(subject).build();
        SecurityContextHolder.getContext().setAuthentication(new JwtAuthenticationToken(jwt,
                Arrays.stream(roles).map(r -> new SimpleGrantedAuthority("ROLE_" + r)).toList()));
    }

    private static MockMultipartFile photo(byte[] bytes, String type) {
        return new MockMultipartFile("photo", "photo", type, bytes);
    }

    private static MockMultipartFile aJpeg() {
        return photo(JPEG_START, "image/jpeg");
    }

    // ------------------------------------------------------------------------------------ who

    @Test
    @DisplayName("a customer searches by photo, and hears what it was read as and what is left today")
    void a_customer_searches_by_photo() throws Exception {
        signedInAs("customer-sub", "CUSTOMER");

        PhotoSearchResponse answer = controller.photo(aJpeg(), new BigDecimal("33.8977"),
                new BigDecimal("35.4829"));

        assertThat(answer.content()).singleElement().satisfies(group -> {
            assertThat(group.store().name()).isEqualTo("Corner Grocer");
            assertThat(group.distanceMetres()).isEqualTo(345L);
            assertThat(group.items()).extracting(p -> p.name()).containsExactly("Pepsi 1L");
        });
        assertThat(answer.understood().name()).isEqualTo("Pepsi 1L");
        assertThat(answer.understood().isProduct()).isTrue();
        assertThat(answer.similar()).isFalse();
        assertThat(answer.nextQuery().terms()).containsExactly("pepsi 1l", "بيبسي", "pepsi");
        assertThat(answer.photosLeftToday()).isEqualTo(7);
        assertThat(answer.nearby()).isTrue();
        verify(photoSearch).search(any(), any(), any(GeoPoint.class), anyInt());

        // The app reads isProduct by that name.
        String json = new ObjectMapper().writeValueAsString(answer.understood());
        assertThat(json).contains("\"isProduct\":true");
    }

    @ParameterizedTest
    @ValueSource(strings = {"MERCHANT", "MERCHANT_STAFF", "RIDER", "BACKOFFICE"})
    @DisplayName("every other role is refused before the photo is read")
    void other_roles_are_refused(String role) {
        signedInAs("someone-" + role, role);

        assertThatThrownBy(() -> controller.photo(aJpeg(), null, null))
                .isInstanceOf(AccessDeniedException.class);
        verify(photoSearch, never()).search(any(), any(), any(), anyInt());
    }

    @Test
    @DisplayName("so is a signed-in account with no role, and a caller who is not signed in")
    void no_role_and_nobody_are_refused() {
        signedInAs("new-account");
        assertThatThrownBy(() -> controller.photo(aJpeg(), null, null))
                .isInstanceOf(AccessDeniedException.class);

        SecurityContextHolder.clearContext();
        assertThatThrownBy(() -> controller.photo(aJpeg(), null, null))
                .isInstanceOf(AuthenticationCredentialsNotFoundException.class);
        verify(photoSearch, never()).search(any(), any(), any(), anyInt());
    }

    // ------------------------------------------------------------------------------------ refusals

    @Test
    @DisplayName("with no real reader it is 503 PHOTO_SEARCH_UNAVAILABLE, and the photo is not read")
    void unavailable_is_a_503_before_anything_is_read() {
        signedInAs("customer-sub", "CUSTOMER");
        when(photoSearch.available()).thenReturn(false);

        assertThatThrownBy(() -> controller.photo(aJpeg(), null, null))
                .isInstanceOfSatisfying(PhotoSearchException.class, e -> {
                    ResponseEntity<ProblemDetail> answer = new ApiExceptionHandler().onPhotoSearchRefused(e);
                    assertThat(answer.getStatusCode().value()).isEqualTo(503);
                    assertThat(answer.getBody().getProperties()).containsEntry("code", "PHOTO_SEARCH_UNAVAILABLE");
                });
        verify(photoSearch, never()).search(any(), any(), any(), anyInt());
    }

    @Test
    @DisplayName("a photo over 2 MB is 413 PHOTO_TOO_LARGE, from the controller and from the container")
    void too_large_is_a_413() {
        signedInAs("customer-sub", "CUSTOMER");
        byte[] large = new byte[2 * 1024 * 1024 + 1];
        System.arraycopy(JPEG_START, 0, large, 0, JPEG_START.length);

        assertThatThrownBy(() -> controller.photo(photo(large, "image/jpeg"), null, null))
                .isInstanceOfSatisfying(PhotoSearchException.class, e -> {
                    ResponseEntity<ProblemDetail> answer = new ApiExceptionHandler().onPhotoSearchRefused(e);
                    assertThat(answer.getStatusCode().value()).isEqualTo(413);
                    assertThat(answer.getBody().getProperties()).containsEntry("code", "PHOTO_TOO_LARGE");
                });
        ProblemDetail container = new ApiExceptionHandler().onUploadTooLarge(
                new MaxUploadSizeExceededException(2 * 1024 * 1024));
        assertThat(container.getStatus()).isEqualTo(413);
        assertThat(container.getProperties()).containsEntry("code", "PHOTO_TOO_LARGE");
        verify(photoSearch, never()).search(any(), any(), any(), anyInt());
    }

    @Test
    @DisplayName("a photo of exactly 2 MB is accepted")
    void exactly_two_megabytes_is_accepted() {
        signedInAs("customer-sub", "CUSTOMER");
        byte[] exact = new byte[2 * 1024 * 1024];
        System.arraycopy(JPEG_START, 0, exact, 0, JPEG_START.length);

        assertThat(controller.photo(photo(exact, "image/jpeg"), null, null).content()).hasSize(1);
    }

    @Test
    @DisplayName("anything but a JPEG or a PNG is 415 PHOTO_TYPE, whatever it claims to be")
    void another_type_is_a_415() {
        signedInAs("customer-sub", "CUSTOMER");
        byte[] gif = "GIF89a....".getBytes();

        assertThatThrownBy(() -> controller.photo(photo(gif, "image/jpeg"), null, null))
                .isInstanceOfSatisfying(PhotoSearchException.class, e -> {
                    ResponseEntity<ProblemDetail> answer = new ApiExceptionHandler().onPhotoSearchRefused(e);
                    assertThat(answer.getStatusCode().value()).isEqualTo(415);
                    assertThat(answer.getBody().getProperties()).containsEntry("code", "PHOTO_TYPE");
                });
        // A PNG, sent without a type, is a PNG.
        byte[] png = {(byte) 0x89, 'P', 'N', 'G', '\r', '\n', 0x1A, '\n', 0, 0};
        assertThat(controller.photo(photo(png, null), null, null).content()).hasSize(1);
        // And no photo at all is the caller's mistake.
        assertThatThrownBy(() -> controller.photo(null, null, null))
                .isInstanceOfSatisfying(PhotoSearchException.class,
                        e -> assertThat(e.refusal().status()).isEqualTo(400));
    }

    @Test
    @DisplayName("half a point is refused as an invalid location, before the photo is read")
    void half_a_point_is_refused() {
        signedInAs("customer-sub", "CUSTOMER");

        assertThatThrownBy(() -> controller.photo(aJpeg(), new BigDecimal("33.8977"), null))
                .isInstanceOf(GeoPoint.InvalidCoordinateException.class);
        verify(photoSearch, never()).search(any(), any(), any(), anyInt());
    }

    @Test
    @DisplayName("a limit is 429 with the limit, which one, and the wait, in the body and as Retry-After")
    void a_limit_is_a_429_with_the_wait() {
        ResponseEntity<ProblemDetail> day = new ApiExceptionHandler().onPhotoSearchRefused(
                PhotoSearchException.limit(false, 10, PhotoSearchException.Scope.DAY, 3600));
        assertThat(day.getStatusCode().value()).isEqualTo(429);
        assertThat(day.getBody().getProperties())
                .containsEntry("code", "PHOTO_SEARCH_LIMIT")
                .containsEntry("limit", 10)
                .containsEntry("scope", "DAY")
                .containsEntry("retryAfterSeconds", 3600L);
        assertThat(day.getHeaders().getFirst(HttpHeaders.RETRY_AFTER)).isEqualTo("3600");

        ResponseEntity<ProblemDetail> platform = new ApiExceptionHandler().onPhotoSearchRefused(
                PhotoSearchException.limit(false, 1000, PhotoSearchException.Scope.PLATFORM, 120));
        assertThat(platform.getBody().getProperties()).containsEntry("scope", "PLATFORM");

        ResponseEntity<ProblemDetail> merchant = new ApiExceptionHandler().onPhotoSearchRefused(
                PhotoSearchException.limit(true, 3, PhotoSearchException.Scope.MINUTE, 20));
        assertThat(merchant.getBody().getProperties()).containsEntry("code", "PHOTO_FIND_LIMIT");

        // The merchants' own platform day: their code, and a scope that tells the app the number is
        // the platform's rather than this shop's, so it does not say "you have used 500 today".
        ResponseEntity<ProblemDetail> merchantPlatform = new ApiExceptionHandler().onPhotoSearchRefused(
                PhotoSearchException.limit(true, 500, PhotoSearchException.Scope.PLATFORM, 300));
        assertThat(merchantPlatform.getStatusCode().value()).isEqualTo(429);
        assertThat(merchantPlatform.getBody().getProperties())
                .containsEntry("code", "PHOTO_FIND_LIMIT")
                .containsEntry("limit", 500)
                .containsEntry("scope", "PLATFORM");
    }

    @Test
    @DisplayName("a busy reader is 503 PHOTO_READER_BUSY with Retry-After; a failed one 502, a refusal 422")
    void the_reader_outcomes_reach_the_app() {
        ResponseEntity<ProblemDetail> busy = new ApiExceptionHandler().onPhotoSearchRefused(
                PhotoSearchException.busy(5));
        assertThat(busy.getStatusCode().value()).isEqualTo(503);
        assertThat(busy.getBody().getProperties()).containsEntry("code", "PHOTO_READER_BUSY");
        assertThat(busy.getHeaders().getFirst(HttpHeaders.RETRY_AFTER)).isEqualTo("5");

        assertThat(new ApiExceptionHandler().onPhotoSearchRefused(PhotoSearchException.failed())
                .getStatusCode().value()).isEqualTo(502);
        assertThat(new ApiExceptionHandler().onPhotoSearchRefused(PhotoSearchException.refused())
                .getBody().getProperties()).containsEntry("code", "PHOTO_REFUSED");
        assertThat(new ApiExceptionHandler().onPhotoSearchRefused(PhotoSearchException.unreadable())
                .getStatusCode().value()).isEqualTo(422);
    }

    // ------------------------------------------------------------------------------------ what the app may offer

    @Test
    @DisplayName("a customer is offered photo search, with what is left today and the largest photo")
    void a_customer_may_search_by_photo() {
        signedInAs("customer-sub", "CUSTOMER");

        PhotoCapabilitiesResponse answer = controller.capabilities();

        assertThat(answer.photoSearch()).isTrue();
        assertThat(answer.photosLeftToday()).isEqualTo(8);
        assertThat(answer.maxPhotoBytes()).isEqualTo(2L * 1024 * 1024);
    }

    @ParameterizedTest
    @ValueSource(strings = {"MERCHANT", "MERCHANT_STAFF", "RIDER", "BACKOFFICE"})
    @DisplayName("nobody else is offered photo search")
    void nobody_else_is_offered_photo_search(String role) {
        signedInAs("someone-" + role, role);

        PhotoCapabilitiesResponse answer = controller.capabilities();

        assertThat(answer.photoSearch()).isFalse();
        assertThat(answer.photosLeftToday()).isZero();
        verify(photoSearch, never()).left(anyString());
    }

    @Test
    @DisplayName("nor is a customer while there is no real reader")
    void no_real_reader_no_photo_search() {
        signedInAs("customer-sub", "CUSTOMER");
        when(photoSearch.available()).thenReturn(false);

        assertThat(controller.capabilities().photoSearch()).isFalse();
    }

    @Test
    @DisplayName("capabilities are for signed-in callers only")
    void capabilities_need_a_signed_in_caller() {
        assertThatThrownBy(() -> controller.capabilities())
                .isInstanceOf(AuthenticationCredentialsNotFoundException.class);
    }

    // ------------------------------------------------------------------------------------ where the photo goes

    /**
     * The photo never touches storage: nothing on its path could hand it there. No class the photo
     * passes through holds MinIO's storage service or the object store, in a constructor or a field.
     */
    @Test
    @DisplayName("nothing the photo passes through can reach storage")
    void the_photo_path_has_no_way_to_storage() {
        for (Class<?> type : List.of(PhotoSearchController.class, PhotoUploads.class, PhotoSearchService.class,
                PhotoReader.class, PhotoQuota.class)) {
            for (Constructor<?> constructor : type.getDeclaredConstructors()) {
                assertThat(constructor.getParameterTypes())
                        .as(type.getSimpleName() + " constructor")
                        .noneMatch(StorageService.class::isAssignableFrom)
                        .noneMatch(ImageObjectStore.class::isAssignableFrom);
            }
            for (Field field : type.getDeclaredFields()) {
                assertThat(field.getType())
                        .as(type.getSimpleName() + "." + field.getName())
                        .isNotEqualTo(StorageService.class)
                        .isNotEqualTo(ImageObjectStore.class);
            }
        }
    }
}
