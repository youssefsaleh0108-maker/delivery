package com.delivery.product.api;

import java.util.List;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.aop.framework.ProxyFactory;
import org.springframework.security.authorization.method.AuthorizationManagerBeforeMethodInterceptor;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import com.delivery.product.domain.DeliveryZone;
import com.delivery.product.domain.GeoPoint;
import com.delivery.product.domain.Store;
import com.delivery.product.service.CatalogService;
import com.delivery.product.service.DeliveryZoneService;
import com.delivery.product.service.PopularServiceShops;
import com.delivery.product.service.ProductImageService;
import com.delivery.product.service.ReviewService;
import com.delivery.product.service.StoreImageService;
import com.delivery.product.service.StoreService;
import com.delivery.product.service.StoreService.StoreView;

import static org.hamcrest.Matchers.hasSize;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * {@code GET /api/stores/{id}} carries where the shop delivers, for the shop page's "Delivery area"
 * map: the circle it already carried (the pin and {@code deliveryRadiusMetres}) and, beside it, the
 * areas it delivers to — the same list order placement serves ({@code servedAreasOf}).
 *
 * <p>What is pinned is the wire shape the app reads: each area's id, name and region, its centre
 * only as the back office placed it, and an empty list — never a missing or null one — for a shop
 * whose areas do not limit it.
 */
@DisplayName("a shop's delivery area on its store read")
class StoreDeliveryAreaApiTest {

    private StoreService storeService;
    private DeliveryZoneService zones;
    private MockMvc mvc;

    @BeforeEach
    void setUp() {
        storeService = mock(StoreService.class);
        zones = mock(DeliveryZoneService.class);

        ProxyFactory factory = new ProxyFactory(new StoreController(storeService,
                mock(CatalogService.class), mock(ProductImageService.class),
                mock(StoreImageService.class), mock(ReviewService.class),
                mock(PopularServiceShops.class), zones));
        factory.setProxyTargetClass(true);
        factory.addAdvisor(AuthorizationManagerBeforeMethodInterceptor.preAuthorize());
        mvc = MockMvcBuilders.standaloneSetup(factory.getProxy()).build();

        // A customer: the store read is theirs to make, and the areas ride on it.
        Jwt jwt = Jwt.withTokenValue("token").header("alg", "none").subject("shopper-sub").build();
        SecurityContextHolder.getContext().setAuthentication(new JwtAuthenticationToken(jwt,
                List.of(new SimpleGrantedAuthority("ROLE_CUSTOMER"))));
    }

    @AfterEach
    void tearDown() {
        SecurityContextHolder.clearContext();
    }

    private Store live(Store store) {
        when(storeService.readView(eq(store.getId().toString()), any()))
                .thenReturn(new StoreView(store, Store.Availability.OPEN, null, false));
        return store;
    }

    @Test
    @DisplayName("the pin, the circle and the areas, each area placed only where the back office placed it")
    void carries_the_circle_and_the_areas() throws Exception {
        Store grocer = live(new Store("merchant-1", "Hamra Corner Grocer", Store.Vertical.GROCERY));
        grocer.pinAt(GeoPoint.of(33.897700d, 35.482900d));
        grocer.setDeliveryRadiusMetres(3_000);

        DeliveryZone hamra = new DeliveryZone("Hamra", "Beirut", 10);
        hamra.placeAt(GeoPoint.of(33.896000d, 35.480000d));
        DeliveryZone verdun = new DeliveryZone("Verdun", "Beirut", 20);
        when(zones.servedAreasOf(grocer.getId())).thenReturn(List.of(hamra, verdun));

        mvc.perform(get("/api/stores/{id}", grocer.getId()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.latitude").value(33.8977))
                .andExpect(jsonPath("$.longitude").value(35.4829))
                .andExpect(jsonPath("$.deliveryRadiusMetres").value(3_000))
                .andExpect(jsonPath("$.deliveryZones", hasSize(2)))
                .andExpect(jsonPath("$.deliveryZones[0].id").value(hamra.getId().toString()))
                .andExpect(jsonPath("$.deliveryZones[0].name").value("Hamra"))
                .andExpect(jsonPath("$.deliveryZones[0].region").value("Beirut"))
                .andExpect(jsonPath("$.deliveryZones[0].centerLat").value(33.896))
                .andExpect(jsonPath("$.deliveryZones[0].centerLng").value(35.48))
                // Not placed yet: listed by name, with no invented position.
                .andExpect(jsonPath("$.deliveryZones[1].name").value("Verdun"))
                .andExpect(jsonPath("$.deliveryZones[1].centerLat").doesNotExist())
                .andExpect(jsonPath("$.deliveryZones[1].centerLng").doesNotExist());
    }

    @Test
    @DisplayName("a shop whose areas do not limit it reads an empty list, not a missing one")
    void no_areas_is_an_empty_list() throws Exception {
        Store kitchen = live(new Store("merchant-2", "Smoke Test Kitchen", Store.Vertical.RESTAURANT));
        when(zones.servedAreasOf(kitchen.getId())).thenReturn(List.of());

        mvc.perform(get("/api/stores/{id}", kitchen.getId()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.deliveryZones", hasSize(0)))
                .andExpect(jsonPath("$.deliveryRadiusMetres").doesNotExist());
    }
}
