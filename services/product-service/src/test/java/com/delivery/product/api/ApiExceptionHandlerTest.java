package com.delivery.product.api;

import java.util.UUID;

import jakarta.validation.Valid;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.core.MethodParameter;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ProblemDetail;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.bind.MissingPathVariableException;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException;

import com.delivery.product.api.dto.StoreDtos.HoursRequest;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * What a caller gets back when a path variable or query parameter cannot be bound.
 *
 * <p>The observed case: a word where a store id belongs. Spring refuses to convert it to a UUID,
 * and a refusal that reaches the catch-all comes back as "Internal error" — a 500 for a mistake
 * only the caller can fix, with a body that tells them nothing.
 */
@DisplayName("a parameter that cannot be bound")
class ApiExceptionHandlerTest {

    private final ApiExceptionHandler handler = new ApiExceptionHandler();

    @Nested
    @DisplayName("of the wrong type")
    class TypeMismatch {

        @Test
        void is_a_400_naming_the_parameter_and_the_expected_type() {
            ProblemDetail problem = handler.onTypeMismatch(mismatch("staff", UUID.class));

            assertThat(problem.getStatus()).isEqualTo(HttpStatus.BAD_REQUEST.value());
            assertThat(problem.getTitle()).isEqualTo("Bad request");
            assertThat(problem.getDetail()).isEqualTo("Parameter 'storeId' is not a valid UUID");
        }

        /**
         * Spring's own message names Java classes — "Failed to convert value of type
         * 'java.lang.String' to required type 'java.util.UUID'". That describes our implementation,
         * not the caller's request, so it must never be the detail.
         */
        @Test
        void never_echoes_the_framework_message() {
            MethodArgumentTypeMismatchException e = mismatch("staff", UUID.class);

            ProblemDetail problem = handler.onTypeMismatch(e);

            assertThat(problem.getDetail())
                    .isNotEqualTo(e.getMessage())
                    .doesNotContain("java.lang", "java.util", "Failed to convert");
        }

        @Test
        void still_names_the_parameter_when_the_required_type_is_unknown() {
            ProblemDetail problem = handler.onTypeMismatch(mismatch("staff", null));

            assertThat(problem.getStatus()).isEqualTo(HttpStatus.BAD_REQUEST.value());
            assertThat(problem.getDetail()).isEqualTo("Parameter 'storeId' has an invalid value");
        }
    }

    @Nested
    @DisplayName("that the URI did not supply")
    class MissingPathVariable {

        @Test
        void is_a_400_naming_the_variable() {
            ProblemDetail problem = handler.onMissingPathVariable(
                    new MissingPathVariableException("storeId", storeIdParameter()));

            assertThat(problem.getStatus()).isEqualTo(HttpStatus.BAD_REQUEST.value());
            assertThat(problem.getTitle()).isEqualTo("Bad request");
            assertThat(problem.getDetail()).isEqualTo("Path variable 'storeId' is required");
        }
    }

    /**
     * The one test that goes through Spring MVC itself, so the handler is proven against the
     * exception the framework really throws for a bad UUID path variable — not one built by hand.
     * Standalone MockMvc: one throwaway controller plus the advice, no application context.
     */
    @Nested
    @DisplayName("on a real request")
    class ThroughSpringMvc {

        private final MockMvc mvc = MockMvcBuilders.standaloneSetup(new Probe())
                .setControllerAdvice(handler)
                .build();

        @Test
        void a_word_in_a_uuid_slot_is_a_400_problem_not_a_500() throws Exception {
            mvc.perform(get("/probe/staff/me"))
                    .andExpect(status().isBadRequest())
                    .andExpect(content().contentTypeCompatibleWith("application/problem+json"))
                    .andExpect(jsonPath("$.title").value("Bad request"))
                    .andExpect(jsonPath("$.detail").value("Parameter 'storeId' is not a valid UUID"));
        }

        @Test
        void a_real_uuid_still_reaches_the_endpoint() throws Exception {
            mvc.perform(get("/probe/" + UUID.randomUUID() + "/me"))
                    .andExpect(status().isOk());
        }

        /**
         * The other half of the opening-hours fix, at the wire.
         *
         * <p>The probe carries the same signature the real endpoint does — {@code List<@Valid …>}
         * rather than {@code @Valid List<…>} — because that difference is the whole bug: on the
         * parameter, the constraints on each window are never evaluated. Spring reports an element
         * failure as its own exception, which is a {@code ResponseStatusException} and would have
         * gone straight to this class's catch-all, so the fix would have swapped one 500 for
         * another without this.
         */
        @Test
        void a_constraint_on_a_list_element_is_a_400_and_not_a_500() throws Exception {
            mvc.perform(put("/probe/hours")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("[{\"dayOfWeek\":0,\"opensAt\":\"09:00\","
                                    + "\"closesAt\":\"17:00\"}]"))
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.title").value("Validation failed"));
        }

        @Test
        void a_week_that_is_actually_valid_still_gets_through() throws Exception {
            mvc.perform(put("/probe/hours")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("[{\"dayOfWeek\":1,\"opensAt\":\"09:00\","
                                    + "\"closesAt\":\"17:00\"}]"))
                    .andExpect(status().isOk());
        }

        /**
         * And the real endpoint is declared the way the probe is.
         *
         * <p>Without this the two drift: the probe above proves the wire behaviour of a signature
         * that only this file contains, so moving {@code @Valid} back onto the parameter of
         * {@code StoreController.setHours} would restore the original defect with every test still
         * green. Asserted by reflection because the difference lives in the annotated type and
         * there is no Spring context here to route a request through the real controller.
         */
        @Test
        void the_real_endpoint_cascades_into_each_window_and_not_into_the_list() throws Exception {
            java.lang.reflect.Method setHours = StoreController.class
                    .getDeclaredMethod("setHours", UUID.class, java.util.List.class);
            java.lang.reflect.AnnotatedType windows = setHours.getAnnotatedParameterTypes()[1];

            assertThat(windows.getAnnotation(Valid.class))
                    .as("@Valid on the list itself cascades into nothing")
                    .isNull();
            assertThat(((java.lang.reflect.AnnotatedParameterizedType) windows)
                    .getAnnotatedActualTypeArguments()[0].getAnnotation(Valid.class))
                    .as("each window is what has to be checked")
                    .isNotNull();
        }
    }

    /**
     * The status a refusal arrives as, per kind.
     *
     * <p>These are mapped one by one rather than left to the catch-all, and the catch-all is why:
     * anything not named here comes back as a 500 saying "the request could not be completed",
     * which tells a caller their own mistake was our fault. Each of these was that 500, or was a
     * status that described the wrong thing.
     */
    @Nested
    @DisplayName("carries the status its kind deserves")
    class Statuses {

        @Test
        void an_unknown_category_is_a_404_and_not_a_rule_violation() {
            UUID id = UUID.randomUUID();

            ProblemDetail problem = handler.onCategoryNotFound(
                    new com.delivery.product.service.CatalogService.CategoryNotFoundException(id));

            assertThat(problem.getStatus()).isEqualTo(HttpStatus.NOT_FOUND.value());
            assertThat(problem.getTitle()).isEqualTo("Category not found");
            assertThat(problem.getDetail()).contains(id.toString());
        }

        @Test
        void an_order_that_cannot_be_rated_is_a_404_about_the_order() {
            UUID orderId = UUID.randomUUID();

            ProblemDetail problem = handler.onOrderNotFound(
                    new com.delivery.product.service.ReviewService.OrderNotFoundException(orderId));

            assertThat(problem.getStatus()).isEqualTo(HttpStatus.NOT_FOUND.value());
            assertThat(problem.getTitle()).isEqualTo("Order not found");
            assertThat(problem.getDetail()).doesNotContain("Store");
        }

        @Test
        void an_offer_this_shop_does_not_have_is_a_404() {
            ProblemDetail problem = handler.onOfferNotFound(
                    new com.delivery.product.service.StoreService.OfferNotFoundException(
                            UUID.randomUUID()));

            assertThat(problem.getStatus()).isEqualTo(HttpStatus.NOT_FOUND.value());
            assertThat(problem.getTitle()).isEqualTo("Offer not found");
        }

        /** 409 as before, but naming the chip in the way rather than the index that refused. */
        @Test
        void a_vertical_another_category_holds_is_a_409_naming_it() {
            ProblemDetail problem = handler.onVerticalTaken(
                    new com.delivery.product.service.BannerService.VerticalTakenException(
                            "Groceries"));

            assertThat(problem.getStatus()).isEqualTo(HttpStatus.CONFLICT.value());
            assertThat(problem.getDetail())
                    .contains("Groceries")
                    .doesNotContain("uniqueness");
        }
    }

    private static MethodArgumentTypeMismatchException mismatch(String value, Class<?> requiredType) {
        return new MethodArgumentTypeMismatchException(value, requiredType, "storeId",
                storeIdParameter(), new IllegalArgumentException("Invalid UUID string: " + value));
    }

    private static MethodParameter storeIdParameter() {
        try {
            return new MethodParameter(Probe.class.getMethod("me", UUID.class), 0);
        } catch (NoSuchMethodException e) {
            throw new AssertionError(e);
        }
    }

    @RestController
    public static class Probe {

        @GetMapping("/probe/{storeId}/me")
        public String me(@PathVariable UUID storeId) {
            return storeId.toString();
        }

        /** The signature StoreController.setHours declares, and nothing else of it. */
        @PutMapping("/probe/hours")
        public String hours(@RequestBody java.util.List<@Valid HoursRequest> windows) {
            return String.valueOf(windows.size());
        }
    }
}
