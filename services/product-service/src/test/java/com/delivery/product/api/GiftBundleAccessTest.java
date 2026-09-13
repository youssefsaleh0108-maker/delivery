package com.delivery.product.api;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;
import java.util.UUID;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.aop.framework.ProxyFactory;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.authorization.method.AuthorizationManagerBeforeMethodInterceptor;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;

import com.delivery.product.api.dto.GiftDtos.GiftBundleResponse;
import com.delivery.product.api.dto.GiftDtos.GiftFeaturedRequest;
import com.delivery.product.api.dto.GiftDtos.GiftFeaturedResponse;
import com.delivery.product.domain.Product;
import com.delivery.product.domain.Store;
import com.delivery.product.service.GiftBundleService;
import com.delivery.product.service.ProductImageService;
import com.delivery.product.service.ProductImageService.ImageUrl;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyBoolean;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Who may read the gift hub's bundles and who may choose them.
 *
 * <p>The controller is wrapped in Spring Security's real {@code @PreAuthorize} interceptor, so the
 * role rule is exercised rather than read off an annotation. Which products qualify is pinned in
 * {@code GiftBundleServiceTest}.
 */
@DisplayName("the gift hub's bundles")
class GiftBundleAccessTest {

    private GiftBundleService gifts;
    private GiftBundleController secured;

    @BeforeEach
    void setUp() {
        gifts = mock(GiftBundleService.class);
        ProductImageService images = mock(ProductImageService.class);
        when(images.resolveImages(anyList())).thenReturn(
                List.of(new ImageUrl("https://img.example/full.jpg", "https://img.example/thumb.jpg")));

        ProxyFactory factory = new ProxyFactory(new GiftBundleController(gifts, images));
        factory.setProxyTargetClass(true);
        factory.addAdvisor(AuthorizationManagerBeforeMethodInterceptor.preAuthorize());
        secured = (GiftBundleController) factory.getProxy();
    }

    @AfterEach
    void signOut() {
        SecurityContextHolder.clearContext();
    }

    private static void signedInAs(String subject, String... roles) {
        Jwt jwt = Jwt.withTokenValue("token").header("alg", "none").subject(subject).build();
        SecurityContextHolder.getContext().setAuthentication(new JwtAuthenticationToken(jwt,
                java.util.Arrays.stream(roles).map(r -> new SimpleGrantedAuthority("ROLE_" + r))
                        .toList()));
    }

    private static Product liveProductOf(Store shop) {
        Product product = new Product("merchant-sub", shop.getId(), "Family Essentials",
                "Oil, rice, lentils, tea & tinned foods.", new BigDecimal("45.00"), null);
        product.addImage("products/family-essentials.jpg");
        product.publish();
        return product;
    }

    @Test
    @DisplayName("the back office may put a product on the hub, and is named as the one who did")
    void theBackOfficeMayChoose() {
        signedInAs("ops-sub", "BACKOFFICE");
        Store shop = new Store("merchant-sub", "Dekkane Abou Selim", Store.Vertical.GROCERY);
        Product product = liveProductOf(shop);
        Instant picked = Instant.parse("2026-09-13T08:00:00Z");
        product.featureAsGift(picked);
        when(gifts.setFeatured(eq(product.getId()), eq(true), eq("ops-sub"), any()))
                .thenReturn(product);

        GiftFeaturedResponse response =
                secured.setFeatured(product.getId(), new GiftFeaturedRequest(true));

        assertThat(response.giftFeatured()).isTrue();
        assertThat(response.giftFeaturedAt()).isEqualTo(picked);
    }

    @Test
    @DisplayName("a merchant, a customer, a rider or a carrier is refused before the service is asked")
    void nobodyElseMayChoose() {
        for (String role : List.of("MERCHANT", "CUSTOMER", "DELIVERY", "CARRIER")) {
            signedInAs("someone-" + role, role);
            assertThatThrownBy(() ->
                    secured.setFeatured(UUID.randomUUID(), new GiftFeaturedRequest(true)))
                    .as(role)
                    .isInstanceOf(AccessDeniedException.class);
        }
        verify(gifts, never()).setFeatured(any(), anyBoolean(), anyString(), any());
    }

    @Test
    @DisplayName("any signed-in caller reads the bundles, with the shop and whether it arrives today")
    void anyoneSignedInMayRead() {
        // No role at all: a customer who has not finished signing up still browses.
        signedInAs("customer-sub");
        Store shop = new Store("merchant-sub", "Dekkane Abou Selim", Store.Vertical.GROCERY);
        Product product = liveProductOf(shop);
        when(gifts.featured(any())).thenReturn(List.of(
                new GiftBundleService.GiftBundle(product, shop, Store.Availability.OPEN, true)));

        List<GiftBundleResponse> bundles = secured.featured();

        assertThat(bundles).singleElement().satisfies(bundle -> {
            assertThat(bundle.productId()).isEqualTo(product.getId());
            assertThat(bundle.merchantId()).isEqualTo("merchant-sub");
            assertThat(bundle.storeId()).isEqualTo(shop.getId());
            assertThat(bundle.storeName()).isEqualTo("Dekkane Abou Selim");
            assertThat(bundle.price()).isEqualByComparingTo("45.00");
            assertThat(bundle.availability()).isEqualTo(Store.Availability.OPEN);
            assertThat(bundle.sameDayDeliverable()).isTrue();
            assertThat(bundle.imageThumbUrls()).containsExactly("https://img.example/thumb.jpg");
        });
    }
}
