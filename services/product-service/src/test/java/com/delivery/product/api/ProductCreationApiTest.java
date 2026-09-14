package com.delivery.product.api;

import java.math.BigDecimal;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.InOrder;
import org.springframework.security.core.authority.AuthorityUtils;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;

import com.delivery.product.api.dto.CatalogDtos.ProductRequest;
import com.delivery.product.service.CatalogService;
import com.delivery.product.service.CrossSellService;
import com.delivery.product.service.ProductImageService;
import com.delivery.product.service.ProductOptionService;
import com.delivery.product.service.StoreService;
import com.delivery.product.service.StoreService.FirstShop;

import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.inOrder;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

/**
 * Adding a product, in the order the controller does it.
 *
 * <p>What a merchant's first product may open is asked before the catalogue's transaction begins, and
 * the answer is handed in. The question can take Onboarding seconds; asked inside the transaction it
 * held one of ten pooled connections and the merchant's lock for as long as that took — on every
 * refused "add product" from a services applicant who is still waiting.
 */
@DisplayName("adding a product")
class ProductCreationApiTest {

    private CatalogService catalog;
    private StoreService stores;
    private ProductController controller;

    @BeforeEach
    void setUp() {
        catalog = mock(CatalogService.class);
        stores = mock(StoreService.class);
        controller = new ProductController(catalog, mock(ProductImageService.class),
                mock(ProductOptionService.class), mock(CrossSellService.class), stores);
        Jwt token = Jwt.withTokenValue("token").header("alg", "none").subject("merchant-sub").build();
        SecurityContextHolder.getContext().setAuthentication(new JwtAuthenticationToken(token,
                AuthorityUtils.createAuthorityList("ROLE_MERCHANT")));
    }

    @AfterEach
    void signOut() {
        SecurityContextHolder.clearContext();
    }

    @Test
    @DisplayName("asks what a first product may open before the catalogue is entered, and hands the answer in")
    void asks_before_the_catalogue() {
        ProductRequest businessCards = new ProductRequest("Business cards", null,
                new BigDecimal("12.00"), null, null, null, null);
        when(stores.firstShopFor("merchant-sub", null))
                .thenReturn(FirstShop.NOT_FOR_A_SERVICES_APPLICANT);
        when(catalog.create("merchant-sub", businessCards, FirstShop.NOT_FOR_A_SERVICES_APPLICANT))
                .thenThrow(new StoreService.ServicesShopNotOpenedException());

        assertThatThrownBy(() -> controller.create(businessCards))
                .isInstanceOf(StoreService.ServicesShopNotOpenedException.class);

        InOrder order = inOrder(stores, catalog);
        order.verify(stores).firstShopFor("merchant-sub", null);
        order.verify(catalog).create("merchant-sub", businessCards,
                FirstShop.NOT_FOR_A_SERVICES_APPLICANT);
    }
}
