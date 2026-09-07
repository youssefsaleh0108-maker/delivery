package com.delivery.product.api;

import java.util.UUID;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.core.MethodParameter;
import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.bind.MissingPathVariableException;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
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
    }
}
