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

import com.delivery.product.domain.Store;
import com.delivery.product.service.CatalogService;
import com.delivery.product.service.ProductImageService;
import com.delivery.product.service.ReviewService;
import com.delivery.product.service.StoreImageService;
import com.delivery.product.service.StoreService;
import com.delivery.product.service.StoreService.StoreView;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyBoolean;
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
 * Only Backoffice awards the dekkane "Trusted Local" badge.
 *
 * <p>The badge is a claim the platform makes to a shop's neighbours, so the refusals are the point:
 * a shop that could award itself the badge would make it certify nothing, and V23 made the column
 * not merchant-writable for exactly that reason. Until this endpoint existed nothing could write it
 * at all, and the badge the customer app draws for it could never appear.
 *
 * <p>Built the way {@code AutoApprovalSettingsAccessTest} is, and for the same reason: the whole
 * guard here is the {@code @PreAuthorize} annotation, which a plain standalone MockMvc never
 * evaluates. So the controller is wrapped in the real method-security interceptor and the real
 * {@link ExceptionTranslationFilter}, and the refusals come back as the 401 and 403 a client sees.
 */
@DisplayName("awarding the trust badge")
class StoreVerifiedLocalAccessTest {

    private static final String BACKOFFICE = "keycloak-sub-backoffice";
    private static final String OWNER = "keycloak-sub-owner";

    private StoreService storeService;
    private Store store;
    private String path;
    private MockMvc mvc;

    @BeforeEach
    void setUp() {
        storeService = mock(StoreService.class);
        store = new Store(OWNER, "Abu Hassan Mini Market", Store.Vertical.GROCERY);
        path = "/api/stores/" + store.getId() + "/verified-local";

        when(storeService.setVerifiedLocal(any(UUID.class), anyString(), anyBoolean()))
                .thenAnswer(invocation -> {
                    store.setVerifiedLocal(invocation.getArgument(2));
                    return new StoreView(store, Store.Availability.OPEN, null, false);
                });

        mvc = secured(new StoreController(storeService, mock(CatalogService.class),
                mock(ProductImageService.class), mock(StoreImageService.class),
                mock(ReviewService.class)));
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
        Jwt jwt = Jwt.withTokenValue("token")
                .header("alg", "none")
                .subject(subject)
                .build();
        List<GrantedAuthority> authorities = Arrays.stream(roles)
                .<GrantedAuthority>map(role -> new SimpleGrantedAuthority("ROLE_" + role))
                .toList();
        SecurityContextHolder.getContext().setAuthentication(
                new JwtAuthenticationToken(jwt, authorities));
    }

    private void grant() throws Exception {
        mvc.perform(put(path)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"verified\": true}"));
    }

    @Test
    @DisplayName("without a token it is a 401 and nothing is written")
    void no_token_is_refused() throws Exception {
        mvc.perform(put(path)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"verified\": true}"))
                .andExpect(status().isUnauthorized());

        verify(storeService, never()).setVerifiedLocal(any(UUID.class), anyString(), anyBoolean());
    }

    @Test
    @DisplayName("a CUSTOMER is refused with a 403")
    void a_customer_is_refused() throws Exception {
        signedInAs("keycloak-sub-shopper", "CUSTOMER");

        mvc.perform(put(path)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"verified\": true}"))
                .andExpect(status().isForbidden());

        verify(storeService, never()).setVerifiedLocal(any(UUID.class), anyString(), anyBoolean());
    }

    /**
     * The shop's own merchant most of all. A merchant token is exactly the token that could put
     * the badge on its own shop, which is the one thing the badge exists to rule out.
     */
    @Test
    @DisplayName("the shop's own MERCHANT is refused with a 403")
    void the_owning_merchant_is_refused() throws Exception {
        signedInAs(OWNER, "MERCHANT");

        mvc.perform(put(path)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"verified\": true}"))
                .andExpect(status().isForbidden());

        verify(storeService, never()).setVerifiedLocal(any(UUID.class), anyString(), anyBoolean());
    }

    @Test
    @DisplayName("a RIDER or a CARRIER is refused with a 403")
    void other_partners_are_refused() throws Exception {
        signedInAs("keycloak-sub-rider", "RIDER", "CARRIER");

        mvc.perform(put(path)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"verified\": true}"))
                .andExpect(status().isForbidden());

        verify(storeService, never()).setVerifiedLocal(any(UUID.class), anyString(), anyBoolean());
    }

    @Test
    @DisplayName("BACKOFFICE grants it, is recorded as the actor, and the shop carries it")
    void backoffice_grants_it() throws Exception {
        signedInAs(BACKOFFICE, "BACKOFFICE");

        mvc.perform(put(path)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"verified\": true}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.verifiedLocal").value(true));

        // The actor is the token's subject — nothing in the body could name one.
        verify(storeService).setVerifiedLocal(eq(store.getId()), eq(BACKOFFICE), eq(true));
    }

    @Test
    @DisplayName("BACKOFFICE withdraws it the same way")
    void backoffice_withdraws_it() throws Exception {
        signedInAs(BACKOFFICE, "BACKOFFICE");
        grant();

        mvc.perform(put(path)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"verified\": false}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.verifiedLocal").value(false));
    }

    /**
     * A body that does not say is refused rather than read as a withdrawal. With a primitive on the
     * request this would have quietly taken a shop's badge away and answered 200.
     */
    @Test
    @DisplayName("a body that does not say which is a 400 and nothing is written")
    void a_silent_body_is_refused() throws Exception {
        signedInAs(BACKOFFICE, "BACKOFFICE");

        mvc.perform(put(path).contentType(MediaType.APPLICATION_JSON).content("{}"))
                .andExpect(status().isBadRequest());
        mvc.perform(put(path).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"verified\": null}"))
                .andExpect(status().isBadRequest());

        verify(storeService, never()).setVerifiedLocal(any(UUID.class), anyString(), anyBoolean());
    }
}
