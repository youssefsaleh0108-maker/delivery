package com.delivery.product.api;

import java.util.List;

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

import com.delivery.product.domain.DeliveryZone;
import com.delivery.product.domain.GeoPoint;
import com.delivery.product.domain.Store;
import com.delivery.product.service.DeliveryZoneService;
import com.delivery.product.service.StoreService;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * GET /api/delivery-zones/around/{storeId} — who may ask which areas surround a shop.
 *
 * <p>This answer decides where Order Manager counts demand for the merchant Demand Radar, so it is
 * the door between a merchant and demand data about the rest of the platform. The controller is
 * wrapped in Spring Security's real {@code @PreAuthorize} interceptor, so the role rule is exercised
 * rather than read off the annotation, and ownership is checked the way a request would meet it.
 */
@DisplayName("asking for the areas around a shop")
class DeliveryZoneAroundAccessTest {

    private static final String OWNER = "merchant-owner-sub";

    private DeliveryZoneService zones;
    private StoreService stores;
    private DeliveryZoneController controller;
    private Store shop;
    private DeliveryZone hamra;

    @BeforeEach
    void setUp() {
        zones = mock(DeliveryZoneService.class);
        stores = mock(StoreService.class);

        shop = new Store(OWNER, "Hamra Sushi", Store.Vertical.RESTAURANT);
        hamra = new DeliveryZone("Hamra", "Beirut", 10);
        hamra.placeAt(GeoPoint.of(33.8959, 35.4787));

        when(stores.read(eq(shop.getId().toString()), any())).thenReturn(shop);
        when(zones.around(shop))
                .thenReturn(new DeliveryZoneService.Neighbourhood("Beirut", 5_000, List.of(hamra)));

        ProxyFactory secured = new ProxyFactory(new DeliveryZoneController(zones, stores));
        secured.setProxyTargetClass(true);
        secured.addAdvisor(AuthorizationManagerBeforeMethodInterceptor.preAuthorize());
        controller = (DeliveryZoneController) secured.getProxy();
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

    @Test
    void the_owner_gets_their_neighbourhood_with_its_centres_and_their_own_name_on_it() {
        signedInAs(OWNER, "MERCHANT");

        DeliveryZoneController.NeighbourhoodResponse around = controller.around(shop.getId());

        assertThat(around.storeId()).isEqualTo(shop.getId());
        assertThat(around.merchantId()).isEqualTo(OWNER);
        assertThat(around.region()).isEqualTo("Beirut");
        assertThat(around.radiusMetres()).isEqualTo(5_000);
        assertThat(around.zones()).singleElement().satisfies(z -> {
            assertThat(z.name()).isEqualTo("Hamra");
            assertThat(z.centerLat()).isEqualByComparingTo("33.8959");
            assertThat(z.centerLng()).isEqualByComparingTo("35.4787");
        });
    }

    @Test
    void another_merchant_is_told_the_shop_does_not_exist_and_nothing_is_worked_out() {
        signedInAs("a-competitor-sub", "MERCHANT");

        assertThatThrownBy(() -> controller.around(shop.getId()))
                .isInstanceOf(StoreService.StoreNotFoundException.class);
        verify(zones, never()).around(any());
    }

    @Test
    void the_back_office_may_look_around_any_shop() {
        signedInAs("ops-sub", "BACKOFFICE");

        assertThat(controller.around(shop.getId()).zones()).hasSize(1);
    }

    @Test
    void customers_riders_carriers_and_shop_staff_are_refused_before_the_shop_is_read() {
        for (String role : List.of("CUSTOMER", "DELIVERY", "CARRIER", "MERCHANT_STAFF")) {
            signedInAs("someone-" + role, role);

            assertThatThrownBy(() -> controller.around(shop.getId()))
                    .as(role)
                    .isInstanceOf(AccessDeniedException.class);
        }
        verify(stores, never()).read(anyString(), any());
    }

    @Test
    void an_unpublished_shop_is_read_as_its_owner_sees_it() {
        // read() hides a shop that is not live from every viewer but its owner; a merchant
        // deciding where to open is exactly who asks before publishing.
        signedInAs(OWNER, "MERCHANT");

        controller.around(shop.getId());

        verify(stores).read(shop.getId().toString(), OWNER);
    }
}
