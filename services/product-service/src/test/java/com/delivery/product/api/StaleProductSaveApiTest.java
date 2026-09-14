package com.delivery.product.api;

import java.sql.SQLException;
import java.util.UUID;
import java.util.stream.Stream;

import jakarta.persistence.OptimisticLockException;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.Arguments;
import org.junit.jupiter.params.provider.MethodSource;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.MediaType;
import org.springframework.orm.ObjectOptimisticLockingFailureException;
import org.springframework.security.core.authority.AuthorityUtils;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import com.delivery.product.domain.Product;
import com.delivery.product.service.CatalogService;
import com.delivery.product.service.CrossSellService;
import com.delivery.product.service.GiftBundleService;
import com.delivery.product.service.ProductImageService;
import com.delivery.product.service.ProductOptionService;
import com.delivery.product.service.ServiceOfferSearch;
import com.delivery.product.service.StoreService;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyBoolean;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * What a product write that lost a race is answered, as a client sees it.
 *
 * <p>Of two saves from one read of a product, the one that commits second is refused (Product's version,
 * V36). {@code OfferModerationDatabaseTest} proves the database refuses it, and that the transaction manager
 * hands up the exception thrown here. This proves that every write that can meet it answers one 409, with a
 * code to branch on and a detail that says what to do. The provider apps show the detail as it is written,
 * and it used to read "That resource already exists or violates a uniqueness rule".
 *
 * <p>Standalone, with the service's exception handler. Who may call each endpoint is for the access tests;
 * this is about the answer a refused save gets.
 */
@DisplayName("a product write that read the product before it changed")
class StaleProductSaveApiTest {

    private static final UUID PRODUCT = UUID.randomUUID();
    private static final UUID FILE = UUID.randomUUID();
    private static final String MERCHANT = "keycloak-sub-provider";
    private static final String PHOTO = "products/cards.jpg";
    private static final String EDIT = "{\"name\":\"Business cards\",\"price\":12.00}";

    private CatalogService catalog;
    private MockMvc mvc;

    @BeforeEach
    void setUp() {
        catalog = mock(CatalogService.class);
        ProductImageService images = mock(ProductImageService.class);
        GiftBundleService gifts = mock(GiftBundleService.class);

        // Every write refused as the transaction manager refuses a stale save when it commits.
        ObjectOptimisticLockingFailureException stale =
                new ObjectOptimisticLockingFailureException(Product.class, PRODUCT);
        doThrow(stale).when(catalog).update(eq(PRODUCT), eq(MERCHANT), any());
        doThrow(stale).when(catalog).publish(PRODUCT, MERCHANT);
        doThrow(stale).when(catalog).pause(PRODUCT, MERCHANT);
        doThrow(stale).when(catalog).resume(PRODUCT, MERCHANT);
        doThrow(stale).when(catalog).archive(PRODUCT, MERCHANT);
        doThrow(stale).when(images).confirmImage(PRODUCT, MERCHANT, FILE);
        doThrow(stale).when(images).removeImage(PRODUCT, MERCHANT, PHOTO);
        doThrow(stale).when(gifts).setFeatured(eq(PRODUCT), anyBoolean(), anyString(), any());

        mvc = MockMvcBuilders.standaloneSetup(
                        new ProductController(catalog, images, mock(ProductOptionService.class),
                                mock(CrossSellService.class), mock(ServiceOfferSearch.class),
                                mock(StoreService.class)),
                        new ProductImageController(images),
                        new GiftBundleController(gifts, images))
                .setControllerAdvice(new ApiExceptionHandler())
                .build();

        Jwt token = Jwt.withTokenValue("token").header("alg", "none").subject(MERCHANT).build();
        SecurityContextHolder.getContext().setAuthentication(new JwtAuthenticationToken(token,
                AuthorityUtils.createAuthorityList("ROLE_MERCHANT")));
    }

    @AfterEach
    void signOut() {
        SecurityContextHolder.clearContext();
    }

    static Stream<Arguments> writes() {
        return Stream.of(
                Arguments.of("an edit", put("/api/products/{id}", PRODUCT)
                        .contentType(MediaType.APPLICATION_JSON).content(EDIT)),
                Arguments.of("a publish", post("/api/products/{id}/publish", PRODUCT)),
                Arguments.of("a pause", post("/api/products/{id}/pause", PRODUCT)),
                Arguments.of("a resume", post("/api/products/{id}/resume", PRODUCT)),
                Arguments.of("an archive", delete("/api/products/{id}", PRODUCT)),
                Arguments.of("a photo added", post("/api/products/{id}/images/{fileId}/confirm", PRODUCT, FILE)),
                Arguments.of("a photo removed", delete("/api/products/{id}/images", PRODUCT)
                        .param("objectKey", PHOTO)),
                Arguments.of("back office's gift-hub switch", put("/api/products/{id}/gift-featured", PRODUCT)
                        .contentType(MediaType.APPLICATION_JSON).content("{\"featured\":true}")));
    }

    @ParameterizedTest(name = "{0}")
    @MethodSource("writes")
    @DisplayName("is answered 409 PRODUCT_CHANGED, with a detail that says to reload")
    void is_answered_product_changed(String write, MockHttpServletRequestBuilder request) throws Exception {
        mvc.perform(request)
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("PRODUCT_CHANGED"))
                .andExpect(jsonPath("$.title").value("Product changed"))
                .andExpect(jsonPath("$.detail")
                        .value("This product changed while you were editing it. Reload it and try again."));
    }

    @Test
    @DisplayName("is answered the same when the persistence API's own exception arrives untranslated")
    void the_untranslated_exception_is_answered_the_same() throws Exception {
        doThrow(new OptimisticLockException("Row was updated or deleted by another transaction"))
                .when(catalog).archive(PRODUCT, MERCHANT);

        mvc.perform(delete("/api/products/{id}", PRODUCT))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("PRODUCT_CHANGED"));
    }

    /**
     * The shape a stale save actually arrives in on Hibernate 6.6 and PostgreSQL, as
     * {@code OfferModerationDatabaseTest} meets it: Hibernate reads the generated {@code updated_at} back
     * before counting rows, finds none, and says so.
     */
    @Test
    @DisplayName("is answered the same when Hibernate reports it as no generated values to read back")
    void hibernates_report_of_nothing_to_read_back_is_answered_the_same() throws Exception {
        doThrow(new org.springframework.orm.jpa.JpaSystemException(new org.hibernate.HibernateException(
                "The database returned no natively generated values : " + Product.class.getName())))
                .when(catalog).publish(PRODUCT, MERCHANT);

        mvc.perform(post("/api/products/{id}/publish", PRODUCT))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("PRODUCT_CHANGED"));
    }

    @Test
    @DisplayName("any other failure of that kind is still the 500 that names nothing inside")
    void another_persistence_failure_is_still_a_server_error() throws Exception {
        doThrow(new org.springframework.orm.jpa.JpaSystemException(new org.hibernate.HibernateException(
                "The database returned no natively generated values : com.delivery.product.domain.Store")))
                .when(catalog).publish(PRODUCT, MERCHANT);

        mvc.perform(post("/api/products/{id}/publish", PRODUCT))
                .andExpect(status().isInternalServerError())
                .andExpect(jsonPath("$.detail").value("The request could not be completed"))
                .andExpect(jsonPath("$.code").doesNotExist());
    }

    @Test
    @DisplayName("refused by the take-down CHECK, is answered as the take-down with a code, not as a uniqueness clash")
    void the_take_down_check_is_answered_as_the_take_down() throws Exception {
        doThrow(violationOf("chk_product_takedown", "23514",
                "new row for relation \"products\" violates check constraint \"chk_product_takedown\""))
                .when(catalog).resume(PRODUCT, MERCHANT);

        mvc.perform(post("/api/products/{id}/resume", PRODUCT))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("OFFER_TAKEN_DOWN"))
                .andExpect(jsonPath("$.title").value("Offer taken down"))
                .andExpect(jsonPath("$.detail").value(
                        "YouDrop has taken this offer down, so it cannot go back on sale until YouDrop restores it."));
    }

    @Test
    @DisplayName("refused by any other constraint, keeps the conflict it was answered before, with no code")
    void another_constraint_keeps_its_answer() throws Exception {
        doThrow(violationOf("uq_products_store_sku", "23505",
                "duplicate key value violates unique constraint \"uq_products_store_sku\""))
                .when(catalog).update(eq(PRODUCT), eq(MERCHANT), any());

        mvc.perform(put("/api/products/{id}", PRODUCT).contentType(MediaType.APPLICATION_JSON).content(EDIT))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.title").value("Conflict"))
                .andExpect(jsonPath("$.detail").value("That resource already exists or violates a uniqueness rule"))
                .andExpect(jsonPath("$.code").doesNotExist());
    }

    /** A refusal as Spring hands it up from Hibernate, which read the constraint's name out of the error. */
    private static DataIntegrityViolationException violationOf(String constraint, String sqlState, String error) {
        return new DataIntegrityViolationException("could not execute statement",
                new org.hibernate.exception.ConstraintViolationException("could not execute statement",
                        new SQLException("ERROR: " + error, sqlState), constraint));
    }
}
