package com.delivery.product.api;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.Arrays;
import java.util.List;
import java.util.UUID;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.aop.framework.ProxyFactory;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;
import org.springframework.data.web.PageableHandlerMethodArgumentResolver;
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
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.test.web.servlet.setup.StandaloneMockMvcBuilder;

import com.delivery.product.domain.OfferModerationAction;
import com.delivery.product.domain.Product;
import com.delivery.product.domain.ServiceTerms;
import com.delivery.product.domain.Store;
import com.delivery.product.service.CatalogService.CatalogRuleViolationException;
import com.delivery.product.service.CatalogService.ProductNotFoundException;
import com.delivery.product.service.CatalogService.ProductView;
import com.delivery.product.service.OfferModerationService;
import com.delivery.product.service.OfferModerationService.ModeratedOffer;
import com.delivery.product.service.OfferModerationService.Moderator;
import com.delivery.product.service.OfferModerationService.StatusFilter;
import com.delivery.product.service.ProductImageService;

import static org.assertj.core.api.Assertions.assertThat;
import static org.hamcrest.Matchers.nullValue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Who may list service offers across shops, take one down, restore it and read its trail, as a client sees
 * the answers.
 *
 * <p>Built like {@code StoreVerifiedLocalAccessTest}, and for the same reason. The whole guard is the
 * {@code @PreAuthorize} on each endpoint, which a plain standalone MockMvc never evaluates, so the controller
 * is wrapped in the real method-security interceptor and the real {@link ExceptionTranslationFilter}. The
 * refusals are the point. A hold that a merchant could lift, above all the offer's own provider, would hold
 * nothing, and the list shows offers no customer may see.
 */
@DisplayName("who may moderate service offers")
class OfferModerationApiTest {

    private static final String BACKOFFICE = "keycloak-sub-backoffice";
    private static final String PROVIDER = "keycloak-sub-provider";
    private static final String REASON = "Prints copies of official exam papers.";
    private static final Instant TAKEN_DOWN_AT = Instant.parse("2026-09-14T09:30:00Z");

    private OfferModerationService moderation;
    private Store press;
    private ServiceTerms terms;

    /** Live, until a test takes it down. */
    private Product offer;

    /** Refusals as the service's exception handler writes them. For callers who present a token. */
    private MockMvc mvc;

    /**
     * For callers with no token. In the service the filter chain answers them 401 before any controller or
     * handler runs; this standalone set-up has no chain, so they go where the bearer entry point answers
     * them, as the chain would.
     */
    private MockMvc noTokenMvc;

    @BeforeEach
    void setUp() {
        moderation = mock(OfferModerationService.class);
        press = new Store(PROVIDER, "Al Fakhry Press", Store.Vertical.SERVICES, Store.ServiceCategory.PRINTING);
        offer = new Product(PROVIDER, press.getId(), "Business card printing", null, new BigDecimal("15.00"), null);
        offer.addImage("products/cards.jpg");
        offer.publish();
        terms = new ServiceTerms(offer.getId(), ServiceTerms.PricingType.FIXED, "cards", 500, 24, 48,
                ServiceTerms.Fulfilment.PICKUP, ServiceTerms.AttachmentPolicy.NONE, null);

        // The service's acts, as far as a response shows them.
        when(moderation.takeDown(any(UUID.class), any(Moderator.class), anyString())).thenAnswer(call -> {
            offer.takeDown(call.getArgument(2), TAKEN_DOWN_AT);
            return moderated();
        });
        when(moderation.restore(any(UUID.class), any(Moderator.class), anyString())).thenAnswer(call -> {
            offer.restore();
            return moderated();
        });

        ProductImageService images = mock(ProductImageService.class);
        when(images.resolveImages(any())).thenReturn(List.of());
        Object controller = new OfferModerationController(moderation, images);
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

    /** Signed in, with the username claim Keycloak's tokens carry unless {@code username} is null. */
    private static void signedInAs(String subject, String username, String... roles) {
        Jwt.Builder jwt = Jwt.withTokenValue("token").header("alg", "none").subject(subject);
        if (username != null) {
            jwt.claim("preferred_username", username);
        }
        List<GrantedAuthority> authorities = Arrays.stream(roles)
                .<GrantedAuthority>map(role -> new SimpleGrantedAuthority("ROLE_" + role))
                .toList();
        SecurityContextHolder.getContext().setAuthentication(new JwtAuthenticationToken(jwt.build(), authorities));
    }

    private ModeratedOffer moderated() {
        return new ModeratedOffer(new ProductView(offer, terms, new BigDecimal("15.00")), press);
    }

    private String offerPath() {
        return "/api/products/" + offer.getId();
    }

    private static String reason(String text) {
        return "{\"reason\": \"" + text + "\"}";
    }

    /** Every endpoint, each asked well formed, so a refusal can only be about who is asking. */
    private List<MockHttpServletRequestBuilder> everyEndpoint() {
        return List.of(
                get("/api/products/services/all"),
                post(offerPath() + "/moderation/take-down")
                        .contentType(MediaType.APPLICATION_JSON).content(reason(REASON)),
                post(offerPath() + "/moderation/restore")
                        .contentType(MediaType.APPLICATION_JSON).content(reason(REASON)),
                get(offerPath() + "/moderation"));
    }

    private void nothingWasAskedOrChanged() {
        verify(moderation, never()).list(any(), any(), any(), any(), any());
        verify(moderation, never()).takeDown(any(), any(), any());
        verify(moderation, never()).restore(any(), any(), any());
        verify(moderation, never()).history(any());
        assertThat(offer.getStatus()).isEqualTo(Product.Status.ACTIVE);
        assertThat(offer.isTakenDown()).isFalse();
    }

    @Nested
    @DisplayName("everyone but back office is refused")
    class Refusals {

        @Test
        @DisplayName("without a token every endpoint is a 401")
        void without_a_token_every_endpoint_is_a_401() throws Exception {
            for (MockHttpServletRequestBuilder request : everyEndpoint()) {
                noTokenMvc.perform(request).andExpect(status().isUnauthorized());
            }
            nothingWasAskedOrChanged();
        }

        /** The list shows offers no customer may see, and a customer has no say in what is on sale. */
        @Test
        @DisplayName("a CUSTOMER is refused every endpoint with a 403")
        void a_customer_is_refused_everywhere() throws Exception {
            signedInAs("keycloak-sub-customer", "shopper", "CUSTOMER");
            for (MockHttpServletRequestBuilder request : everyEndpoint()) {
                mvc.perform(request).andExpect(status().isForbidden());
            }
            nothingWasAskedOrChanged();
        }

        /** The offer's own provider most of all: a hold its provider could lift would hold nothing. */
        @Test
        @DisplayName("a MERCHANT, the offer's own provider included, is refused every endpoint with a 403")
        void a_merchant_is_refused_everywhere() throws Exception {
            for (String merchant : List.of(PROVIDER, "keycloak-sub-rival")) {
                signedInAs(merchant, merchant, "MERCHANT");
                for (MockHttpServletRequestBuilder request : everyEndpoint()) {
                    mvc.perform(request).andExpect(status().isForbidden());
                }
            }
            nothingWasAskedOrChanged();
        }

        @Test
        @DisplayName("a RIDER or a CARRIER is refused every endpoint with a 403")
        void other_partners_are_refused_everywhere() throws Exception {
            signedInAs("keycloak-sub-rider", "rider", "RIDER", "CARRIER");
            for (MockHttpServletRequestBuilder request : everyEndpoint()) {
                mvc.perform(request).andExpect(status().isForbidden());
            }
            nothingWasAskedOrChanged();
        }
    }

    @Nested
    @DisplayName("back office")
    class BackOffice {

        @BeforeEach
        void signedIn() {
            signedInAs(BACKOFFICE, "rana.ops", "BACKOFFICE");
        }

        @Test
        @DisplayName("takes an offer down with a reason, is named from its token, and reads the offer back held, with its shop")
        void takes_an_offer_down() throws Exception {
            mvc.perform(post(offerPath() + "/moderation/take-down")
                            .contentType(MediaType.APPLICATION_JSON)
                            // An actor in the body is not how an actor is named.
                            .content("{\"reason\": \"" + REASON + "\", \"actorId\": \"keycloak-sub-someone-else\"}"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.offer.id").value(offer.getId().toString()))
                    .andExpect(jsonPath("$.offer.status").value("ARCHIVED"))
                    .andExpect(jsonPath("$.offer.moderation.state").value("TAKEN_DOWN"))
                    .andExpect(jsonPath("$.offer.moderation.reason").value(REASON))
                    .andExpect(jsonPath("$.offer.moderation.takenDownAt").exists())
                    .andExpect(jsonPath("$.offer.service.unitLabel").value("cards"))
                    .andExpect(jsonPath("$.storeId").value(press.getId().toString()))
                    .andExpect(jsonPath("$.storeName").value("Al Fakhry Press"))
                    .andExpect(jsonPath("$.serviceCategory").value("PRINTING"))
                    .andExpect(jsonPath("$.storeStatus").value(press.getStatus().name()));

            verify(moderation).takeDown(offer.getId(), new Moderator(BACKOFFICE, "rana.ops"), REASON);
        }

        @Test
        @DisplayName("restores an offer with a reason and reads it back paused with no hold, naming by id a staff member whose token has no username")
        void restores_an_offer() throws Exception {
            offer.takeDown(REASON, TAKEN_DOWN_AT);
            signedInAs(BACKOFFICE, null, "BACKOFFICE");

            mvc.perform(post(offerPath() + "/moderation/restore")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(reason("The provider replaced the designs.")))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.offer.status").value("PAUSED"))
                    .andExpect(jsonPath("$.offer.moderation").value(nullValue()));

            verify(moderation).restore(offer.getId(), new Moderator(BACKOFFICE, null),
                    "The provider replaced the designs.");
        }

        @Test
        @DisplayName("a missing, blank or overlong reason is a 400, and nothing is taken down or restored")
        void a_reason_is_required() throws Exception {
            List<String> bodies = List.of("{}", "{\"reason\": null}", reason("   "),
                    reason("x".repeat(Product.MAX_TAKEDOWN_REASON_LENGTH + 1)));
            for (String act : List.of("/moderation/take-down", "/moderation/restore")) {
                for (String body : bodies) {
                    mvc.perform(post(offerPath() + act).contentType(MediaType.APPLICATION_JSON).content(body))
                            .andExpect(status().isBadRequest());
                }
                mvc.perform(post(offerPath() + act)).andExpect(status().isBadRequest());
            }
            nothingWasAskedOrChanged();
        }

        @Test
        @DisplayName("the service's refusals reach the client: a goods product or an offer in the wrong state is a 422, an unknown id a 404")
        void the_services_refusals_reach_the_client() throws Exception {
            UUID goods = UUID.randomUUID();
            UUID nothing = UUID.randomUUID();
            doThrow(new CatalogRuleViolationException(
                    "Only a service offer can be taken down by back office, and this product is in a goods shop."))
                    .when(moderation).takeDown(eq(goods), any(), anyString());
            doThrow(new CatalogRuleViolationException("This offer is not taken down, so there is nothing to restore"))
                    .when(moderation).restore(eq(offer.getId()), any(), anyString());
            doThrow(new ProductNotFoundException(nothing)).when(moderation).takeDown(eq(nothing), any(), anyString());
            doThrow(new ProductNotFoundException(nothing)).when(moderation).history(nothing);

            mvc.perform(post("/api/products/" + goods + "/moderation/take-down")
                            .contentType(MediaType.APPLICATION_JSON).content(reason(REASON)))
                    .andExpect(status().isUnprocessableEntity());
            mvc.perform(post(offerPath() + "/moderation/restore")
                            .contentType(MediaType.APPLICATION_JSON).content(reason("Reviewed.")))
                    .andExpect(status().isUnprocessableEntity());
            mvc.perform(post("/api/products/" + nothing + "/moderation/take-down")
                            .contentType(MediaType.APPLICATION_JSON).content(reason(REASON)))
                    .andExpect(status().isNotFound());
            mvc.perform(get("/api/products/" + nothing + "/moderation"))
                    .andExpect(status().isNotFound());
        }

        @Test
        @DisplayName("lists service offers a page at a time, narrowed by status, category, shop and text")
        void lists_offers_with_every_filter() throws Exception {
            offer.takeDown(REASON, TAKEN_DOWN_AT);
            when(moderation.list(any(), any(), any(), any(), any(Pageable.class)))
                    .thenReturn(new PageImpl<>(List.of(moderated()), PageRequest.of(1, 5), 6));

            mvc.perform(get("/api/products/services/all")
                            .param("status", "TAKEN_DOWN")
                            .param("serviceCategory", "PRINTING")
                            .param("storeId", press.getId().toString())
                            .param("search", "cards")
                            .param("page", "1")
                            .param("size", "5"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.totalElements").value(6))
                    .andExpect(jsonPath("$.page").value(1))
                    .andExpect(jsonPath("$.content[0].offer.name").value("Business card printing"))
                    .andExpect(jsonPath("$.content[0].offer.moderation.reason").value(REASON))
                    .andExpect(jsonPath("$.content[0].storeName").value("Al Fakhry Press"))
                    .andExpect(jsonPath("$.content[0].serviceCategory").value("PRINTING"));

            ArgumentCaptor<Pageable> page = ArgumentCaptor.forClass(Pageable.class);
            verify(moderation).list(eq(StatusFilter.TAKEN_DOWN), eq(Store.ServiceCategory.PRINTING),
                    eq(press.getId()), eq("cards"), page.capture());
            assertThat(page.getValue().getPageNumber()).isEqualTo(1);
            assertThat(page.getValue().getPageSize()).isEqualTo(5);
        }

        @Test
        @DisplayName("with no filter it asks for every service offer, twenty at a time, newest first")
        void with_no_filter_it_asks_for_everything_newest_first() throws Exception {
            when(moderation.list(any(), any(), any(), any(), any(Pageable.class))).thenReturn(Page.empty());

            mvc.perform(get("/api/products/services/all"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.totalElements").value(0));

            ArgumentCaptor<Pageable> page = ArgumentCaptor.forClass(Pageable.class);
            verify(moderation).list(isNull(), isNull(), isNull(), isNull(), page.capture());
            assertThat(page.getValue().getPageSize()).isEqualTo(20);
            assertThat(page.getValue().getSort().getOrderFor("createdAt")).isEqualTo(Sort.Order.desc("createdAt"));
        }

        @Test
        @DisplayName("a status or category this service does not have is a 400, not the whole list")
        void an_unknown_filter_is_a_400() throws Exception {
            mvc.perform(get("/api/products/services/all").param("status", "HIDDEN"))
                    .andExpect(status().isBadRequest());
            mvc.perform(get("/api/products/services/all").param("serviceCategory", "KNITTING"))
                    .andExpect(status().isBadRequest());

            verify(moderation, never()).list(any(), any(), any(), any(), any());
        }

        @Test
        @DisplayName("reads an offer's trail newest first, naming who acted, when and why")
        void reads_the_trail() throws Exception {
            OfferModerationAction takenDown = new OfferModerationAction(offer,
                    OfferModerationAction.Action.TAKE_DOWN, REASON, BACKOFFICE, "rana.ops", TAKEN_DOWN_AT);
            OfferModerationAction restored = new OfferModerationAction(offer,
                    OfferModerationAction.Action.RESTORE, "Reviewed.", "keycloak-sub-lead", null,
                    TAKEN_DOWN_AT.plusSeconds(3_600));
            when(moderation.history(offer.getId())).thenReturn(List.of(restored, takenDown));

            mvc.perform(get(offerPath() + "/moderation"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$[0].action").value("RESTORE"))
                    .andExpect(jsonPath("$[0].actorId").value("keycloak-sub-lead"))
                    .andExpect(jsonPath("$[0].actorName").value(nullValue()))
                    .andExpect(jsonPath("$[1].action").value("TAKE_DOWN"))
                    .andExpect(jsonPath("$[1].reason").value(REASON))
                    .andExpect(jsonPath("$[1].actorId").value(BACKOFFICE))
                    .andExpect(jsonPath("$[1].actorName").value("rana.ops"))
                    .andExpect(jsonPath("$[1].createdAt").exists())
                    .andExpect(jsonPath("$[1].productId").value(offer.getId().toString()))
                    .andExpect(jsonPath("$[1].storeId").value(press.getId().toString()));
        }
    }
}
