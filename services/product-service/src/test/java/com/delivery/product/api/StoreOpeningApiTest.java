package com.delivery.product.api;

import java.util.Arrays;
import java.util.List;

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

import com.delivery.product.domain.Store;
import com.delivery.product.service.CatalogService;
import com.delivery.product.service.ProductImageService;
import com.delivery.product.service.ReviewService;
import com.delivery.product.service.StoreImageService;
import com.delivery.product.service.StoreService;
import com.delivery.product.service.StoreService.StoreView;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * {@code POST /api/stores}: who may open a shop, whose shop it is, and what the provider app's
 * bootstrap is told when it asks twice.
 *
 * <p>The app opens a services provider's shop on its first entry after approval, and it will ask
 * again — after a dropped connection, from a second phone. The second answer is a 200 with the same
 * shop rather than an error, so the app's retry is not a failure it has to explain. Built like
 * {@code ServicesStoreApiTest}, with the real method-security interceptor, so the refusals are the
 * 401 and 403 a client would see.
 */
@DisplayName("opening a shop through the API")
class StoreOpeningApiTest {

    private static final String PROVIDER = "provider-sub";

    private static final String PRINT_SHOP = """
            {"name":"Al Fakhry Press","vertical":"SERVICES","serviceCategory":"PRINTING",
             "neighborhood":"Mar Mikhael","tags":[],"merchantId":"somebody-else"}""";

    private StoreService storeService;
    private MockMvc mvc;

    @BeforeEach
    void setUp() {
        storeService = mock(StoreService.class);

        ProxyFactory factory = new ProxyFactory(new StoreController(storeService,
                mock(CatalogService.class), mock(ProductImageService.class),
                mock(StoreImageService.class), mock(ReviewService.class)));
        factory.setProxyTargetClass(true);
        factory.addAdvisor(AuthorizationManagerBeforeMethodInterceptor.preAuthorize());

        ExceptionTranslationFilter refusals =
                new ExceptionTranslationFilter(new BearerTokenAuthenticationEntryPoint());
        refusals.setAccessDeniedHandler(new BearerTokenAccessDeniedHandler());

        mvc = MockMvcBuilders.standaloneSetup(factory.getProxy())
                .addFilters(refusals)
                .build();
    }

    @AfterEach
    void tearDown() {
        SecurityContextHolder.clearContext();
    }

    private static void signedInAs(String subject, String... roles) {
        Jwt jwt = Jwt.withTokenValue("token").header("alg", "none").subject(subject).build();
        List<GrantedAuthority> authorities = Arrays.stream(roles)
                .<GrantedAuthority>map(role -> new SimpleGrantedAuthority("ROLE_" + role))
                .toList();
        SecurityContextHolder.getContext().setAuthentication(
                new JwtAuthenticationToken(jwt, authorities));
    }

    private static StoreView press() {
        Store press = new Store(PROVIDER, "Al Fakhry Press", Store.Vertical.SERVICES,
                Store.ServiceCategory.PRINTING);
        return new StoreView(press, Store.Availability.CLOSED, null, false);
    }

    @Test
    @DisplayName("a merchant's first services shop is a 201 with the shop, opened for the token's subject")
    void first_open_is_201() throws Exception {
        signedInAs(PROVIDER, "MERCHANT");
        when(storeService.open(eq(PROVIDER), any()))
                .thenReturn(new StoreService.Opened(press(), true));

        mvc.perform(post("/api/stores").contentType(MediaType.APPLICATION_JSON).content(PRINT_SHOP))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.name").value("Al Fakhry Press"))
                .andExpect(jsonPath("$.vertical").value("SERVICES"));

        // The body's merchantId is not a field of the request; the shop is the caller's.
        verify(storeService).open(eq(PROVIDER), any());
    }

    @Test
    @DisplayName("asked again, a 200 with the same shop: the app's retry is not an error")
    void asking_again_is_200() throws Exception {
        signedInAs(PROVIDER, "MERCHANT");
        when(storeService.open(eq(PROVIDER), any()))
                .thenReturn(new StoreService.Opened(press(), false));

        mvc.perform(post("/api/stores").contentType(MediaType.APPLICATION_JSON).content(PRINT_SHOP))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.name").value("Al Fakhry Press"));
    }

    @Test
    @DisplayName("a customer cannot open a shop")
    void a_customer_is_refused() throws Exception {
        signedInAs("shopper-sub", "CUSTOMER");

        mvc.perform(post("/api/stores").contentType(MediaType.APPLICATION_JSON).content(PRINT_SHOP))
                .andExpect(status().isForbidden());
        verify(storeService, never()).open(any(), any());
    }

    @Test
    @DisplayName("nobody signed in cannot open a shop")
    void anonymous_is_refused() throws Exception {
        mvc.perform(post("/api/stores").contentType(MediaType.APPLICATION_JSON).content(PRINT_SHOP))
                .andExpect(status().isUnauthorized());
        verify(storeService, never()).open(any(), any());
    }
}
