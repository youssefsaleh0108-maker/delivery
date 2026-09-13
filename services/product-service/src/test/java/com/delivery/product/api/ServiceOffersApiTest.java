package com.delivery.product.api;

import java.math.BigDecimal;
import java.util.Arrays;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.aop.framework.ProxyFactory;
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
import org.springframework.test.web.servlet.setup.StandaloneMockMvcBuilder;

import com.delivery.platform.outbox.OutboxRecorder;
import com.delivery.product.domain.CategoryRepository;
import com.delivery.product.domain.GeoPoint;
import com.delivery.product.domain.Product;
import com.delivery.product.domain.ProductOptionGroupRepository;
import com.delivery.product.domain.ProductRepository;
import com.delivery.product.domain.ServiceTerms;
import com.delivery.product.domain.ServiceTermsRepository;
import com.delivery.product.domain.Store;
import com.delivery.product.domain.StoreDeliveryZoneRepository;
import com.delivery.product.domain.StoreRepository;
import com.delivery.product.service.CatalogService;
import com.delivery.product.service.CrossSellService;
import com.delivery.product.service.ProductImageService;
import com.delivery.product.service.ProductOptionService;
import com.delivery.product.service.ServiceOfferSearch;
import com.delivery.product.service.ServiceOfferSearch.PopularOffer;
import com.delivery.product.service.StoreService;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Who may pause, resume, count and search service offers, as a client sees the answers.
 *
 * <p>Built like {@code ServicesStoreApiTest}, with the real method-security interceptor in front of the
 * controller, and with a real {@code CatalogService} behind it, so "a merchant pauses only their own
 * offers" is proven through the endpoint rather than assumed from a mock: the rival's request carries a
 * real token subject, and the service's own ownership query is what refuses it.
 */
@DisplayName("who may pause, resume, count and search service offers")
class ServiceOffersApiTest {

    private static final String PROVIDER = "keycloak-sub-provider";
    private static final String RIVAL = "keycloak-sub-rival";

    private ProductRepository products;
    private ServiceOfferSearch serviceOffers;
    private Product offer;

    /** Refusals as the service's exception handler writes them. For callers who present a token. */
    private MockMvc mvc;

    /**
     * For callers with no token. In the service the filter chain answers them 401 before any
     * controller or handler runs; this standalone set-up has no chain, so they go where the bearer
     * entry point answers them, as the chain would.
     */
    private MockMvc noTokenMvc;

    @BeforeEach
    void setUp() {
        products = mock(ProductRepository.class);
        StoreRepository stores = mock(StoreRepository.class);
        ServiceTermsRepository serviceTerms = mock(ServiceTermsRepository.class);
        serviceOffers = mock(ServiceOfferSearch.class);

        Store press = new Store(PROVIDER, "Al Fakhry Press", Store.Vertical.SERVICES,
                Store.ServiceCategory.PRINTING);
        press.pinAt(GeoPoint.of(33.898200d, 35.482500d));
        offer = new Product(PROVIDER, press.getId(), "Business card printing", null,
                new BigDecimal("15.00"), null);
        offer.addImage("products/cards.jpg");
        offer.publish();
        ServiceTerms terms = new ServiceTerms(offer.getId(), ServiceTerms.PricingType.FIXED, "cards",
                500, 24, 48, ServiceTerms.Fulfilment.BOTH, ServiceTerms.AttachmentPolicy.NONE, null);

        when(stores.findById(press.getId())).thenReturn(Optional.of(press));
        when(products.findByIdAndMerchantId(any(UUID.class), anyString())).thenReturn(Optional.empty());
        when(products.findByIdAndMerchantId(offer.getId(), PROVIDER)).thenReturn(Optional.of(offer));
        when(products.existsById(offer.getId())).thenReturn(true);
        when(serviceTerms.findById(offer.getId())).thenReturn(Optional.of(terms));
        when(serviceTerms.findAllById(any())).thenReturn(List.of(terms));

        CatalogService catalog = new CatalogService(products, mock(CategoryRepository.class),
                mock(StoreService.class), mock(OutboxRecorder.class), stores, serviceTerms,
                mock(StoreDeliveryZoneRepository.class), mock(ProductOptionGroupRepository.class));
        ProductImageService images = mock(ProductImageService.class);
        when(images.resolveImages(any())).thenReturn(List.of());

        Object controller = new ProductController(catalog, images, mock(ProductOptionService.class),
                mock(CrossSellService.class), serviceOffers);
        mvc = secured(controller).setControllerAdvice(new ApiExceptionHandler()).build();
        noTokenMvc = secured(controller).build();
    }

    @AfterEach
    void tearDown() {
        SecurityContextHolder.clearContext();
    }

    private static StandaloneMockMvcBuilder secured(Object controller) {
        ProxyFactory factory = new ProxyFactory(controller);
        factory.setProxyTargetClass(true);
        factory.addAdvisor(AuthorizationManagerBeforeMethodInterceptor.preAuthorize());

        ExceptionTranslationFilter refusals =
                new ExceptionTranslationFilter(new BearerTokenAuthenticationEntryPoint());
        refusals.setAccessDeniedHandler(new BearerTokenAccessDeniedHandler());

        return MockMvcBuilders.standaloneSetup(factory.getProxy())
                .setCustomArgumentResolvers(new PageableHandlerMethodArgumentResolver())
                .addFilters(refusals);
    }

    private static void signedInAs(String subject, String... roles) {
        Jwt jwt = Jwt.withTokenValue("token").header("alg", "none").subject(subject).build();
        List<GrantedAuthority> authorities = Arrays.stream(roles)
                .<GrantedAuthority>map(role -> new SimpleGrantedAuthority("ROLE_" + role))
                .toList();
        SecurityContextHolder.getContext().setAuthentication(
                new JwtAuthenticationToken(jwt, authorities));
    }

    private String pausePath() {
        return "/api/products/" + offer.getId() + "/pause";
    }

    private String resumePath() {
        return "/api/products/" + offer.getId() + "/resume";
    }

    @Nested
    @DisplayName("pausing an offer")
    class Pausing {

        @Test
        void without_a_token_it_is_a_401_and_the_offer_stays_on_sale() throws Exception {
            noTokenMvc.perform(post(pausePath())).andExpect(status().isUnauthorized());

            assertThat(offer.getStatus()).isEqualTo(Product.Status.ACTIVE);
        }

        @Test
        void a_customer_is_refused() throws Exception {
            signedInAs("keycloak-sub-customer", "CUSTOMER");

            mvc.perform(post(pausePath())).andExpect(status().isForbidden());

            assertThat(offer.getStatus()).isEqualTo(Product.Status.ACTIVE);
        }

        /** Another merchant's offer is indistinguishable from an id that was never issued. */
        @Test
        void a_rival_merchant_is_told_it_does_not_exist_and_it_stays_on_sale() throws Exception {
            signedInAs(RIVAL, "MERCHANT");

            mvc.perform(post(pausePath())).andExpect(status().isNotFound());

            assertThat(offer.getStatus()).isEqualTo(Product.Status.ACTIVE);
        }

        @Test
        void its_provider_pauses_it_and_reads_it_back_with_its_terms() throws Exception {
            signedInAs(PROVIDER, "MERCHANT");

            mvc.perform(post(pausePath()))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.status").value("PAUSED"))
                    .andExpect(jsonPath("$.service.pricingType").value("FIXED"))
                    .andExpect(jsonPath("$.service.unitSize").value(500))
                    .andExpect(jsonPath("$.service.fulfilmentModes").value("BOTH"));

            assertThat(offer.getStatus()).isEqualTo(Product.Status.PAUSED);
        }

        /** Stopping sales is never gated on approval. */
        @Test
        void a_provider_still_awaiting_approval_may_pause() throws Exception {
            signedInAs(PROVIDER, "MERCHANT", "APPLICANT");

            mvc.perform(post(pausePath())).andExpect(status().isOk());
        }
    }

    @Nested
    @DisplayName("resuming an offer")
    class Resuming {

        @BeforeEach
        void pausedFirst() {
            offer.pause();
        }

        @Test
        void a_rival_merchant_is_told_it_does_not_exist() throws Exception {
            signedInAs(RIVAL, "MERCHANT");

            mvc.perform(post(resumePath())).andExpect(status().isNotFound());

            assertThat(offer.getStatus()).isEqualTo(Product.Status.PAUSED);
        }

        /** The same act as publishing: putting an offer in front of customers. */
        @Test
        void a_provider_awaiting_approval_is_refused_like_publishing() throws Exception {
            signedInAs(PROVIDER, "MERCHANT", "APPLICANT");

            mvc.perform(post(resumePath())).andExpect(status().isForbidden());

            assertThat(offer.getStatus()).isEqualTo(Product.Status.PAUSED);
        }

        @Test
        void its_approved_provider_puts_it_back_on_sale() throws Exception {
            signedInAs(PROVIDER, "MERCHANT");

            mvc.perform(post(resumePath()))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.status").value("ACTIVE"));

            assertThat(offer.getStatus()).isEqualTo(Product.Status.ACTIVE);
        }
    }

    @Nested
    @DisplayName("counting a merchant's offers by status")
    class TheStatusCount {

        @Test
        void a_customer_is_refused() throws Exception {
            signedInAs("keycloak-sub-customer", "CUSTOMER");

            mvc.perform(get("/api/products/mine").param("status", "ACTIVE"))
                    .andExpect(status().isForbidden());
        }

        /** The merchant is the token's subject; nothing in the query can name another. */
        @Test
        void a_merchant_counts_only_their_own_active_offers() throws Exception {
            signedInAs(PROVIDER, "MERCHANT");
            when(products.findByMerchantIdAndStatus(eq(PROVIDER), eq(Product.Status.ACTIVE),
                    any(Pageable.class)))
                    .thenReturn(new PageImpl<>(List.of(offer), org.springframework.data.domain.PageRequest.of(0, 1), 3));

            mvc.perform(get("/api/products/mine")
                            .param("status", "ACTIVE")
                            .param("size", "1")
                            .param("merchantId", RIVAL))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.totalElements").value(3))
                    .andExpect(jsonPath("$.content[0].service.unitLabel").value("cards"));

            verify(products, never()).findByMerchantIdAndStatus(eq(RIVAL), any(), any(Pageable.class));
        }

        @Test
        void a_status_the_service_does_not_have_is_a_400_not_the_whole_list() throws Exception {
            signedInAs(PROVIDER, "MERCHANT");

            mvc.perform(get("/api/products/mine").param("status", "HIDDEN"))
                    .andExpect(status().isBadRequest());

            verify(products, never()).findByMerchantId(anyString(), any(Pageable.class));
        }
    }

    @Nested
    @DisplayName("searching service offers")
    class Searching {

        @Test
        void without_a_token_it_is_a_401_and_nothing_is_searched() throws Exception {
            noTokenMvc.perform(get("/api/products/services")).andExpect(status().isUnauthorized());

            verify(serviceOffers, never()).search(any(), any(), any(Pageable.class));
        }

        @Test
        void a_merchant_without_the_customer_role_is_refused() throws Exception {
            signedInAs(PROVIDER, "MERCHANT");

            mvc.perform(get("/api/products/services")).andExpect(status().isForbidden());

            verify(serviceOffers, never()).search(any(), any(), any(Pageable.class));
        }

        @Test
        void a_signed_in_customer_searches_by_text_and_category() throws Exception {
            signedInAs("keycloak-sub-customer", "CUSTOMER");
            when(serviceOffers.search(any(), any(), any(Pageable.class)))
                    .thenReturn(new PageImpl<>(List.of(offer)));

            mvc.perform(get("/api/products/services")
                            .param("search", "cards")
                            .param("serviceCategory", "PRINTING"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.content[0].name").value("Business card printing"))
                    .andExpect(jsonPath("$.content[0].service.turnaroundMaxHours").value(48));

            verify(serviceOffers).search(eq("cards"), eq(Store.ServiceCategory.PRINTING),
                    any(Pageable.class));
        }

        @Test
        void a_category_the_platform_does_not_have_is_a_400() throws Exception {
            signedInAs("keycloak-sub-customer", "CUSTOMER");

            mvc.perform(get("/api/products/services").param("serviceCategory", "KNITTING"))
                    .andExpect(status().isBadRequest());

            verify(serviceOffers, never()).search(any(), any(), any(Pageable.class));
        }

        @Test
        void popular_without_a_token_is_a_401() throws Exception {
            noTokenMvc.perform(get("/api/products/services/popular"))
                    .andExpect(status().isUnauthorized());

            verify(serviceOffers, never()).popular(any(), anyInt());
        }

        @Test
        void popular_for_a_customer_carries_each_offers_delivered_orders() throws Exception {
            signedInAs("keycloak-sub-customer", "CUSTOMER");
            when(serviceOffers.popular(any(), anyInt())).thenReturn(List.of(new PopularOffer(offer, 7)));

            mvc.perform(get("/api/products/services/popular").param("serviceCategory", "PRINTING"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$[0].offer.name").value("Business card printing"))
                    .andExpect(jsonPath("$[0].deliveredOrders").value(7));
        }
    }
}
