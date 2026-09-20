package com.delivery.product.api;

import java.math.BigDecimal;
import java.util.Arrays;
import java.util.List;
import java.util.UUID;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.aop.framework.ProxyFactory;
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

import com.delivery.product.api.dto.PhotoFindDtos.PhotoFindResponse;
import com.delivery.product.domain.Product;
import com.delivery.product.domain.Store;
import com.delivery.product.service.CatalogService;
import com.delivery.product.service.CatalogService.ProductView;
import com.delivery.product.service.PhotoFindService;
import com.delivery.product.service.PhotoFindService.FindResult;
import com.delivery.product.service.PhotoFindService.Match;
import com.delivery.product.service.PhotoFindService.Suggestion;
import com.delivery.product.service.PhotoSearchException;
import com.delivery.product.service.ProductImageService;
import com.delivery.product.service.StoreService;
import com.delivery.product.vision.Descriptions;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * {@code POST /api/products/mine/find-by-photo}: who may look for their own products by photo, and
 * what comes back.
 *
 * <p>The controller is wrapped in Spring Security's real {@code @PreAuthorize} interceptor, as in
 * {@code CatalogScanAccessTest}: MERCHANT only, because every read is a paid call against the
 * merchant's own allowance and the answer is their private catalogue, in every status.
 */
@DisplayName("finding a product by photo, over the API")
class PhotoFindAccessTest {

    private static final byte[] JPEG = {(byte) 0xFF, (byte) 0xD8, (byte) 0xFF, (byte) 0xE0, 0, 16};

    private PhotoFindService find;
    private PhotoFindController controller;

    @BeforeEach
    void setUp() {
        find = mock(PhotoFindService.class);
        CatalogService catalog = mock(CatalogService.class);
        when(catalog.views(anyList())).thenAnswer(call -> call.<List<Product>>getArgument(0).stream()
                .map(p -> new ProductView(p, null, null)).toList());

        Store shop = new Store("merchant-sub", "Corner Grocer", Store.Vertical.GROCERY);
        Product paused = new Product("merchant-sub", shop.getId(), "Pepsi 1L", null,
                new BigDecimal("1.25"), null);
        Descriptions.Clean understood = new Descriptions.Clean(true, "Pepsi 1L", "بيبسي", "Pepsi", "1 L",
                List.of("cola"), "5449000000996", new BigDecimal("0.900"));
        when(find.find(anyString(), any(), any())).thenReturn(new FindResult("CLAUDE", false, understood,
                List.of(new Match(paused, PhotoFindService.BY_BARCODE)),
                new Suggestion("Pepsi 1L", "5449000000996", null), 29));

        ProxyFactory secured = new ProxyFactory(new PhotoFindController(find, catalog,
                mock(ProductImageService.class), DataSize.ofMegabytes(2)));
        secured.setProxyTargetClass(true);
        secured.addAdvisor(AuthorizationManagerBeforeMethodInterceptor.preAuthorize());
        controller = (PhotoFindController) secured.getProxy();
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

    private static MockMultipartFile photo() {
        return new MockMultipartFile("photo", "photo", "image/jpeg", JPEG);
    }

    @Test
    @DisplayName("a merchant sees their own product, how it matched, and what a new one would start from")
    void a_merchant_finds_their_own_product() {
        signedInAs("merchant-sub", "MERCHANT");

        PhotoFindResponse answer = controller.findByPhoto(photo(), null);

        assertThat(answer.provider()).isEqualTo("CLAUDE");
        assertThat(answer.sample()).isFalse();
        assertThat(answer.understood().name()).isEqualTo("Pepsi 1L");
        assertThat(answer.matches()).singleElement().satisfies(match -> {
            assertThat(match.product().name()).isEqualTo("Pepsi 1L");
            assertThat(match.product().status()).isEqualTo(Product.Status.DRAFT);
            assertThat(match.matchedBy()).isEqualTo("BARCODE");
        });
        assertThat(answer.suggestion().barcode()).isEqualTo("5449000000996");
        assertThat(answer.findsLeftToday()).isEqualTo(29);
    }

    @ParameterizedTest
    @ValueSource(strings = {"MERCHANT_STAFF", "CUSTOMER", "RIDER", "BACKOFFICE"})
    @DisplayName("nobody else may, and nothing is read for them")
    void other_roles_are_refused(String role) {
        signedInAs("someone-" + role, role);

        assertThatThrownBy(() -> controller.findByPhoto(photo(), null))
                .isInstanceOf(AccessDeniedException.class);
        verify(find, never()).find(anyString(), any(), any());
    }

    @Test
    @DisplayName("nor may a signed-in account with no role, nor a caller who is not signed in")
    void no_role_and_nobody_are_refused() {
        signedInAs("new-account");
        assertThatThrownBy(() -> controller.findByPhoto(photo(), null))
                .isInstanceOf(AccessDeniedException.class);

        SecurityContextHolder.clearContext();
        assertThatThrownBy(() -> controller.findByPhoto(photo(), null))
                .isInstanceOf(AuthenticationCredentialsNotFoundException.class);
        verify(find, never()).find(anyString(), any(), any());
    }

    @Test
    @DisplayName("the shop asked about is passed on as it was given")
    void the_store_is_passed_on() {
        signedInAs("merchant-sub", "MERCHANT");
        UUID storeId = UUID.randomUUID();

        controller.findByPhoto(photo(), storeId);

        verify(find).find("merchant-sub", JPEG, storeId);
    }

    @Test
    @DisplayName("a photo too large, of the wrong type, or missing is refused before anything is read")
    void bad_photos_are_refused() {
        signedInAs("merchant-sub", "MERCHANT");
        byte[] large = new byte[2 * 1024 * 1024 + 1];
        System.arraycopy(JPEG, 0, large, 0, JPEG.length);

        assertThatThrownBy(() -> controller.findByPhoto(
                new MockMultipartFile("photo", "photo", "image/jpeg", large), null))
                .isInstanceOfSatisfying(PhotoSearchException.class,
                        e -> assertThat(e.getCode()).isEqualTo("PHOTO_TOO_LARGE"));
        assertThatThrownBy(() -> controller.findByPhoto(
                new MockMultipartFile("photo", "photo", "image/jpeg", "GIF89a...".getBytes()), null))
                .isInstanceOfSatisfying(PhotoSearchException.class,
                        e -> assertThat(e.getCode()).isEqualTo("PHOTO_TYPE"));
        assertThatThrownBy(() -> controller.findByPhoto(null, null))
                .isInstanceOfSatisfying(PhotoSearchException.class,
                        e -> assertThat(e.getCode()).isEqualTo("PHOTO_MISSING"));
        verify(find, never()).find(anyString(), any(), any());
    }

    @Test
    @DisplayName("a merchant's own limit answers 429 PHOTO_FIND_LIMIT with the wait")
    void the_merchants_limit_is_its_own_code() {
        signedInAs("merchant-sub", "MERCHANT");
        when(find.find(anyString(), any(), any())).thenThrow(PhotoSearchException.limit(true, 30,
                PhotoSearchException.Scope.DAY, 1800));

        assertThatThrownBy(() -> controller.findByPhoto(photo(), null))
                .isInstanceOfSatisfying(PhotoSearchException.class, e -> {
                    ResponseEntity<ProblemDetail> answer = new ApiExceptionHandler().onPhotoSearchRefused(e);
                    assertThat(answer.getStatusCode().value()).isEqualTo(429);
                    assertThat(answer.getBody().getProperties())
                            .containsEntry("code", "PHOTO_FIND_LIMIT")
                            .containsEntry("limit", 30)
                            .containsEntry("retryAfterSeconds", 1800L);
                });
    }

    @Test
    @DisplayName("another merchant's shop is not found, and a service shop is a catalogue rule")
    void the_services_refusals_reach_the_client() {
        signedInAs("merchant-sub", "MERCHANT");
        doThrow(new StoreService.StoreNotFoundException("someone else's"))
                .when(find).find(anyString(), any(), any());
        assertThatThrownBy(() -> controller.findByPhoto(photo(), UUID.randomUUID()))
                .isInstanceOfSatisfying(StoreService.StoreNotFoundException.class, e ->
                        assertThat(new ApiExceptionHandler().onStoreNotFound(e).getStatus()).isEqualTo(404));

        doThrow(new CatalogService.CatalogRuleViolationException("service shop"))
                .when(find).find(anyString(), any(), any());
        assertThatThrownBy(() -> controller.findByPhoto(photo(), UUID.randomUUID()))
                .isInstanceOfSatisfying(CatalogService.CatalogRuleViolationException.class, e ->
                        assertThat(new ApiExceptionHandler().onRuleViolation(e).getStatus()).isEqualTo(422));
    }

    @Test
    @DisplayName("a sample answer says so, as a Blitz scan's does")
    void a_sample_answer_says_so() {
        signedInAs("merchant-sub", "MERCHANT");
        when(find.find(anyString(), any(), any())).thenReturn(new FindResult("FAKE", true,
                Descriptions.Clean.notAProduct(), List.of(), null, 29));

        PhotoFindResponse answer = controller.findByPhoto(photo(), null);

        assertThat(answer.sample()).isTrue();
        assertThat(answer.provider()).isEqualTo("FAKE");
        assertThat(answer.matches()).isEmpty();
        assertThat(answer.suggestion()).isNull();
        assertThat(answer.understood().isProduct()).isFalse();
    }
}
