package com.delivery.product.api;


import java.util.Arrays;
import java.util.List;
import java.util.UUID;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.aop.framework.ProxyFactory;
import org.springframework.http.MediaType;
import org.springframework.security.authorization.method.AuthorizationManagerBeforeMethodInterceptor;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.security.oauth2.server.resource.web.BearerTokenAuthenticationEntryPoint;
import org.springframework.security.oauth2.server.resource.web.access.BearerTokenAccessDeniedHandler;
import org.springframework.security.web.access.ExceptionTranslationFilter;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import com.delivery.product.domain.GeoPoint;
import com.delivery.product.domain.Store;
import com.delivery.product.service.CatalogService;
import com.delivery.product.service.ProductImageService;
import com.delivery.product.service.ReviewService;
import com.delivery.product.service.StoreImageService;
import com.delivery.product.service.StoreService;
import com.delivery.product.service.StoreService.StoreView;

import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Who may put a shop on the map.
 *
 * <p>The merchant, on their own shop, as before — and now Back Office, on any shop. Back Office is
 * here for the shops that were already ACTIVE when the pin became a condition of listing: their own
 * merchant is otherwise the only person on the platform who can place them, and support cannot
 * repair a trading shop that no "near you" can find. It is a different service call
 * ({@code pinAsBackoffice}) rather than the same one with a looser check, because moving somebody
 * else's shop is a change the merchant did not make and it is recorded against whoever made it.
 *
 * <p>Built like {@code StoreVerifiedLocalAccessTest}: the guard under test is the
 * {@code @PreAuthorize} annotation, which a plain standalone MockMvc never evaluates, so the
 * controller is wrapped in the real method-security interceptor and the real
 * {@link ExceptionTranslationFilter}.
 */
@DisplayName("putting a shop on the map")
class StorePinAccessTest {

    private static final String BACKOFFICE = "keycloak-sub-backoffice";
    private static final String OWNER = "keycloak-sub-owner";
    private static final String OTHER_MERCHANT = "keycloak-sub-rival";

    /** Hamra. Anywhere real; the point of the test is who wrote it, not where. */
    private static final String BODY = "{\"latitude\": 33.8959, \"longitude\": 35.4820}";

    private StoreService storeService;
    private Store store;
    private String path;
    private MockMvc mvc;

    @BeforeEach
    void setUp() {
        storeService = mock(StoreService.class);
        store = new Store(OWNER, "Abu Hassan Mini Market", Store.Vertical.GROCERY);
        path = "/api/stores/" + store.getId() + "/location";

        when(storeService.pin(any(UUID.class), anyString(), any(GeoPoint.class)))
                .thenAnswer(call -> pinned(call.getArgument(2)));
        when(storeService.pinAsBackoffice(any(UUID.class), anyString(), any(GeoPoint.class)))
                .thenAnswer(call -> pinned(call.getArgument(2)));

        mvc = secured(new StoreController(storeService, mock(CatalogService.class),
                mock(ProductImageService.class), mock(StoreImageService.class),
                mock(ReviewService.class), mock(com.delivery.product.service.PopularServiceShops.class),
                mock(com.delivery.product.service.DeliveryZoneService.class)));
    }

    private StoreView pinned(GeoPoint point) {
        store.pinAt(point);
        return new StoreView(store, Store.Availability.OPEN, null, false);
    }

    @AfterEach
    void tearDown() {
        SecurityContextHolder.clearContext();
    }

    private static MockMvc secured(Object controller) {
        ProxyFactory factory = new ProxyFactory(controller);
        factory.setProxyTargetClass(true);
        factory.addAdvisor(AuthorizationManagerBeforeMethodInterceptor.preAuthorize());

        ExceptionTranslationFilter refusals =
                new ExceptionTranslationFilter(new BearerTokenAuthenticationEntryPoint());
        refusals.setAccessDeniedHandler(new BearerTokenAccessDeniedHandler());

        return MockMvcBuilders.standaloneSetup(factory.getProxy())
                .addFilters(refusals)
                .build();
    }

    private static void signedInAs(String subject, String... roles) {
        Jwt jwt = Jwt.withTokenValue("token").header("alg", "none").subject(subject).build();
        List<GrantedAuthority> authorities = Arrays.stream(roles)
                .<GrantedAuthority>map(role -> new SimpleGrantedAuthority("ROLE_" + role))
                .toList();
        SecurityContextHolder.getContext()
                .setAuthentication(new JwtAuthenticationToken(jwt, authorities));
    }

    @Test
    @DisplayName("without a token it is a 401 and nothing is written")
    void no_token_is_refused() throws Exception {
        mvc.perform(put(path).contentType(MediaType.APPLICATION_JSON).content(BODY))
                .andExpect(status().isUnauthorized());

        verify(storeService, never()).pin(any(UUID.class), anyString(), any(GeoPoint.class));
        verify(storeService, never())
                .pinAsBackoffice(any(UUID.class), anyString(), any(GeoPoint.class));
    }

    @Test
    @DisplayName("a CUSTOMER or a RIDER is refused with a 403")
    void other_roles_are_refused() throws Exception {
        signedInAs("keycloak-sub-shopper", "CUSTOMER");
        mvc.perform(put(path).contentType(MediaType.APPLICATION_JSON).content(BODY))
                .andExpect(status().isForbidden());

        signedInAs("keycloak-sub-rider", "RIDER");
        mvc.perform(put(path).contentType(MediaType.APPLICATION_JSON).content(BODY))
                .andExpect(status().isForbidden());

        verify(storeService, never()).pin(any(UUID.class), anyString(), any(GeoPoint.class));
        verify(storeService, never())
                .pinAsBackoffice(any(UUID.class), anyString(), any(GeoPoint.class));
    }

    /**
     * The merchant path is unchanged, and it still goes through the owning check in the service —
     * the role alone would let any merchant move any shop on the map, which is why the id comes from
     * the token and never from the body.
     */
    @Test
    @DisplayName("a MERCHANT pins through the owning check, with their own token's subject")
    void a_merchant_pins_their_own_shop() throws Exception {
        signedInAs(OWNER, "MERCHANT");

        mvc.perform(put(path).contentType(MediaType.APPLICATION_JSON).content(BODY))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.latitude").value(33.8959))
                .andExpect(jsonPath("$.longitude").value(35.482));

        verify(storeService).pin(eq(store.getId()), eq(OWNER), any(GeoPoint.class));
        verify(storeService, never())
                .pinAsBackoffice(any(UUID.class), anyString(), any(GeoPoint.class));
    }

    /** Another merchant's token reaches the ownership check and is refused there, not here. */
    @Test
    @DisplayName("another merchant reaches the owning check rather than the backoffice road")
    void a_rival_merchant_is_not_treated_as_backoffice() throws Exception {
        signedInAs(OTHER_MERCHANT, "MERCHANT");

        mvc.perform(put(path).contentType(MediaType.APPLICATION_JSON).content(BODY))
                .andExpect(status().isOk());

        verify(storeService).pin(eq(store.getId()), eq(OTHER_MERCHANT), any(GeoPoint.class));
        verify(storeService, never())
                .pinAsBackoffice(any(UUID.class), anyString(), any(GeoPoint.class));
    }

    @Test
    @DisplayName("BACKOFFICE pins a shop it does not own, recorded against its own subject")
    void backoffice_pins_any_shop() throws Exception {
        signedInAs(BACKOFFICE, "BACKOFFICE");

        mvc.perform(put(path).contentType(MediaType.APPLICATION_JSON).content(BODY))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.latitude").value(33.8959));

        verify(storeService).pinAsBackoffice(eq(store.getId()), eq(BACKOFFICE), any(GeoPoint.class));
        verify(storeService, never()).pin(any(UUID.class), anyString(), any(GeoPoint.class));
    }

    /**
     * An account that is both is treated as the more privileged one. Checked in that order on
     * purpose: a support engineer who also has a merchant token would otherwise be refused every
     * shop but their own.
     */
    @Test
    @DisplayName("an account holding both roles takes the backoffice road")
    void both_roles_take_the_backoffice_road() throws Exception {
        signedInAs(BACKOFFICE, "MERCHANT", "BACKOFFICE");

        mvc.perform(put(path).contentType(MediaType.APPLICATION_JSON).content(BODY))
                .andExpect(status().isOk());

        verify(storeService).pinAsBackoffice(eq(store.getId()), eq(BACKOFFICE), any(GeoPoint.class));
        verify(storeService, never()).pin(any(UUID.class), anyString(), any(GeoPoint.class));
    }

    /**
     * Null Island. Whichever road the caller takes, the coordinate goes through {@link GeoPoint}'s
     * rules first, so (0, 0) — a dropped form field, an uninitialised float, a failed parse — is
     * refused rather than written as a shop 600 km off the coast of Ghana.
     */
    @Test
    @DisplayName("(0, 0) is refused for back office exactly as it is for a merchant")
    void null_island_is_refused_on_both_roads() {
        String nullIsland = "{\"latitude\": 0, \"longitude\": 0}";

        for (String[] caller : new String[][] {{BACKOFFICE, "BACKOFFICE"}, {OWNER, "MERCHANT"}}) {
            signedInAs(caller[0], caller[1]);
            assertThatThrownBy(() -> mvc.perform(put(path)
                    .contentType(MediaType.APPLICATION_JSON).content(nullIsland)))
                    .hasCauseInstanceOf(GeoPoint.InvalidCoordinateException.class);
        }

        verify(storeService, never()).pin(any(UUID.class), anyString(), any(GeoPoint.class));
        verify(storeService, never())
                .pinAsBackoffice(any(UUID.class), anyString(), any(GeoPoint.class));
    }
}
