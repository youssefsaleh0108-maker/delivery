package com.delivery.product.api;

import java.util.List;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.aop.framework.ProxyFactory;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.Pageable;
import org.springframework.data.web.PageableHandlerMethodArgumentResolver;
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
import com.delivery.product.service.StoreService.NearbyFilters;
import com.delivery.product.service.StoreService.NearbyResult;
import com.delivery.product.service.StoreService.StoreView;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyDouble;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * The storefront API's half of storefront isolation: what the query string turns into, what a card
 * says, and who may read the open service categories.
 *
 * <p>Which shops each read may return is pinned where it is decided, in
 * {@code ServicesStorefrontIsolationTest} and {@code NearbyStoreSearchTest}. This pins the binding in
 * front of it: that a read naming nothing reaches the service naming nothing, which is what every
 * installed app sends. Built like {@code StoreVerifiedLocalAccessTest}, with the real method-security
 * interceptor, so the one new endpoint's refusal is the 401 a client would see.
 */
@DisplayName("asking the storefront API for service shops")
class ServicesStoreApiTest {

    private static final String NEAR_HAMRA = "/api/stores/nearby?latitude=33.8977&longitude=35.4829";

    private StoreService storeService;
    private MockMvc mvc;

    @BeforeEach
    void setUp() {
        storeService = mock(StoreService.class);
        when(storeService.storefront(any(), any(), any(), any(), any(), any(), any(),
                any(Pageable.class))).thenReturn(Page.empty());
        when(storeService.nearby(any(GeoPoint.class), anyDouble(), anyInt(),
                any(NearbyFilters.class), any(Pageable.class)))
                .thenReturn(new NearbyResult(new PageImpl<>(List.of()), false));

        ProxyFactory factory = new ProxyFactory(new StoreController(storeService,
                mock(CatalogService.class), mock(ProductImageService.class),
                mock(StoreImageService.class), mock(ReviewService.class)));
        factory.setProxyTargetClass(true);
        factory.addAdvisor(AuthorizationManagerBeforeMethodInterceptor.preAuthorize());

        ExceptionTranslationFilter refusals =
                new ExceptionTranslationFilter(new BearerTokenAuthenticationEntryPoint());
        refusals.setAccessDeniedHandler(new BearerTokenAccessDeniedHandler());

        mvc = MockMvcBuilders.standaloneSetup(factory.getProxy())
                .setCustomArgumentResolvers(new PageableHandlerMethodArgumentResolver())
                .addFilters(refusals)
                .build();
    }

    @AfterEach
    void tearDown() {
        SecurityContextHolder.clearContext();
    }

    private static void signedInAs(String... roles) {
        Jwt jwt = Jwt.withTokenValue("token").header("alg", "none").subject("shopper").build();
        List<GrantedAuthority> authorities = java.util.Arrays.stream(roles)
                .<GrantedAuthority>map(role -> new SimpleGrantedAuthority("ROLE_" + role))
                .toList();
        SecurityContextHolder.getContext().setAuthentication(
                new JwtAuthenticationToken(jwt, authorities));
    }

    private NearbyFilters nearbyFiltersFor(String path) throws Exception {
        mvc.perform(get(path)).andExpect(status().isOk());
        ArgumentCaptor<NearbyFilters> filters = ArgumentCaptor.forClass(NearbyFilters.class);
        verify(storeService).nearby(any(GeoPoint.class), anyDouble(), anyInt(), filters.capture(),
                any(Pageable.class));
        return filters.getValue();
    }

    @Test
    @DisplayName("Home's browse names neither a vertical nor a category, and reaches the service so")
    void home_browse_names_neither() throws Exception {
        signedInAs("CUSTOMER");

        mvc.perform(get("/api/stores")).andExpect(status().isOk());

        verify(storeService).storefront(isNull(), isNull(), any(), any(), any(), any(), any(),
                any(Pageable.class));
    }

    @Test
    @DisplayName("the Services tab names its vertical and category")
    void services_tab_names_its_vertical_and_category() throws Exception {
        signedInAs("CUSTOMER");

        mvc.perform(get("/api/stores")
                        .param("vertical", "SERVICES")
                        .param("serviceCategory", "PRINTING"))
                .andExpect(status().isOk());

        verify(storeService).storefront(eq(Store.Vertical.SERVICES),
                eq(Store.ServiceCategory.PRINTING), any(), any(), any(), any(), any(),
                any(Pageable.class));
    }

    @Test
    @DisplayName("a category the platform does not have is a 400, not a guess")
    void an_unknown_category_is_refused() throws Exception {
        signedInAs("CUSTOMER");

        mvc.perform(get("/api/stores").param("serviceCategory", "KNITTING"))
                .andExpect(status().isBadRequest());

        verify(storeService, never()).storefront(any(), any(), any(), any(), any(), any(), any(),
                any(Pageable.class));
    }

    @Test
    @DisplayName("a service shop's card says what it does")
    void a_service_card_says_what_the_shop_does() throws Exception {
        signedInAs("CUSTOMER");
        Store press = new Store("merchant-press", "Al Fakhry Press", Store.Vertical.SERVICES,
                Store.ServiceCategory.PRINTING);
        when(storeService.storefront(any(), any(), any(), any(), any(), any(), any(),
                any(Pageable.class)))
                .thenReturn(new PageImpl<>(List.of(
                        new StoreView(press, Store.Availability.OPEN, null, false))));

        mvc.perform(get("/api/stores").param("vertical", "SERVICES"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.content[0].vertical").value("SERVICES"))
                .andExpect(jsonPath("$.content[0].serviceCategory").value("PRINTING"));
    }

    @Test
    @DisplayName("near me passes the vertical and category on as filters")
    void nearby_passes_vertical_and_category_on() throws Exception {
        signedInAs("CUSTOMER");

        NearbyFilters filters =
                nearbyFiltersFor(NEAR_HAMRA + "&vertical=SERVICES&serviceCategory=TAILORING");

        assertThat(filters.vertical()).isEqualTo(Store.Vertical.SERVICES);
        assertThat(filters.serviceCategory()).isEqualTo(Store.ServiceCategory.TAILORING);
    }

    @Test
    @DisplayName("near me without them is the goods search every installed app makes")
    void nearby_without_them_is_the_goods_search() throws Exception {
        signedInAs("CUSTOMER");

        assertThat(nearbyFiltersFor(NEAR_HAMRA)).isEqualTo(NearbyFilters.NONE);
    }

    @Test
    @DisplayName("the open service categories: without a token it is a 401")
    void service_categories_refuse_a_caller_with_no_token() throws Exception {
        mvc.perform(get("/api/stores/service-categories")).andExpect(status().isUnauthorized());

        verify(storeService, never()).openServiceCategories();
    }

    /** Any signed-in caller, even one with no role yet: the storefront it describes is theirs too. */
    @Test
    @DisplayName("the open service categories: any signed-in caller reads them, in order")
    void any_signed_in_caller_reads_the_open_categories() throws Exception {
        when(storeService.openServiceCategories())
                .thenReturn(List.of(Store.ServiceCategory.PRINTING, Store.ServiceCategory.TAILORING));
        signedInAs();

        mvc.perform(get("/api/stores/service-categories"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(2))
                .andExpect(jsonPath("$[0]").value("PRINTING"))
                .andExpect(jsonPath("$[1]").value("TAILORING"));
    }
}
