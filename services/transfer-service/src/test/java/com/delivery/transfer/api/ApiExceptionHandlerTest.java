package com.delivery.transfer.api;

import java.math.BigDecimal;
import java.util.Map;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ProblemDetail;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.mock.http.MockHttpInputMessage;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.HttpRequestMethodNotSupportedException;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.context.request.async.AsyncRequestTimeoutException;
import org.springframework.web.server.ResponseStatusException;
import org.springframework.web.servlet.resource.NoResourceFoundException;

import com.delivery.transfer.client.OrderManagerClient.OrderUnavailableException;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * A refusal has to say what it refused.
 *
 * <p>Every one of these left the service as the same empty 400: "amountUsd must be positive",
 * "No provider currently carries WHISH" and "That order does not exist, or is not yours" were
 * indistinguishable to the app, which could only show a customer "something went wrong" when each
 * of them names a different thing to do next.
 */
class ApiExceptionHandlerTest {

    private final ApiExceptionHandler handler = new ApiExceptionHandler();

    @Test
    @DisplayName("a refusal keeps its own words and its own status")
    void refusalKeepsItsWording() {
        ProblemDetail problem = handler.onResponseStatus(new ResponseStatusException(
                HttpStatus.UNPROCESSABLE_ENTITY, "splitUsd must be between 0 and amountUsd"));

        assertThat(problem.getStatus()).isEqualTo(HttpStatus.UNPROCESSABLE_ENTITY.value());
        assertThat(problem.getDetail()).isEqualTo("splitUsd must be between 0 and amountUsd");
    }

    @Test
    @DisplayName("a refusal with no wording still says something a client can render")
    void refusalWithoutWordingStillHasABody() {
        ProblemDetail problem =
                handler.onResponseStatus(new ResponseStatusException(HttpStatus.CONFLICT));

        assertThat(problem.getStatus()).isEqualTo(HttpStatus.CONFLICT.value());
        assertThat(problem.getDetail()).isNotBlank();
        assertThat(problem.getTitle()).isNotBlank();
    }

    @Test
    @DisplayName("an order that cannot be confirmed refuses the transfer with the reason")
    void orderUnavailableCarriesTheReason() {
        ProblemDetail problem = handler.onOrderUnavailable(
                new OrderUnavailableException("That order does not exist, or is not yours"));

        assertThat(problem.getStatus()).isEqualTo(HttpStatus.UNPROCESSABLE_ENTITY.value());
        assertThat(problem.getDetail()).isEqualTo("That order does not exist, or is not yours");
    }

    @Test
    @DisplayName("a body Jackson cannot read is the caller's 400, not our 500")
    void unreadableBodyIsA400() {
        ProblemDetail problem = handler.onUnreadableBody(new HttpMessageNotReadableException(
                "JSON parse error: not one of the values accepted for Enum class TransferMethod",
                new MockHttpInputMessage(new byte[0])));

        assertThat(problem.getStatus()).isEqualTo(HttpStatus.BAD_REQUEST.value());
        // Jackson's own message names internal types; it must not reach the caller.
        assertThat(problem.getDetail()).doesNotContain("Enum", "TransferMethod", "JSON parse");
    }

    /**
     * A handler nothing registers is a handler that does not run, and the empty-400 behaviour
     * comes straight back. Only Spring's wiring can prove the advice is actually consulted and
     * these tests have no context, so the annotation is asserted instead — the cheapest check that
     * fails if the class is ever unhooked.
     */
    @Test
    @DisplayName("the advice is registered, not merely written")
    void adviceIsRegistered() {
        assertThat(ApiExceptionHandler.class.getAnnotation(
                org.springframework.web.bind.annotation.RestControllerAdvice.class)).isNotNull();
        assertThat(ApiExceptionHandler.class.getPackageName())
                .startsWith(com.delivery.transfer.TransferServiceApplication.class.getPackageName());
    }

    @Test
    @DisplayName("an unexpected failure says nothing about the inside of the service")
    void unexpectedFailureLeaksNothing() {
        ProblemDetail problem = handler.onUnexpected(
                new IllegalStateException("could not extract ResultSet from money_transfers"));

        assertThat(problem.getStatus()).isEqualTo(HttpStatus.INTERNAL_SERVER_ERROR.value());
        assertThat(problem.getDetail()).doesNotContain("ResultSet", "money_transfers");
    }

    /**
     * The refusals Spring raises before any of this service's code runs.
     *
     * <p>They reached the catch-all, so the wrong method on an endpoint that exists — and, here, a
     * query parameter a caller simply left out — answered 500 with a full stack trace logged at
     * ERROR. A 500 tells a customer's app the platform is broken and invites a retry that can never
     * succeed, and the trace is log volume any caller can generate at will.
     *
     * <p>The status is the one the framework chose, for the same reason {@code onResponseStatus}
     * keeps the one a refusal of ours chose.
     */
    @Nested
    @DisplayName("a request Spring itself refuses")
    class FrameworkRefusals {

        private final MockMvc mvc = MockMvcBuilders.standaloneSetup(new Probe())
                .setControllerAdvice(handler)
                .build();

        @Test
        @DisplayName("the wrong method on a path that exists is a 405, not a 500")
        void the_wrong_method_is_a_405() throws Exception {
            mvc.perform(get("/probe/transfers"))
                    .andExpect(status().isMethodNotAllowed())
                    .andExpect(content().contentTypeCompatibleWith("application/problem+json"))
                    .andExpect(jsonPath("$.status").value(405))
                    .andExpect(jsonPath("$.title").value("Method Not Allowed"));
        }

        @Test
        @DisplayName("a body in a content type nothing here reads is a 415, not a 500")
        void an_unsupported_content_type_is_a_415() throws Exception {
            mvc.perform(post("/probe/transfers")
                            .contentType(MediaType.TEXT_PLAIN)
                            .content("50 usd to 71 123 456"))
                    .andExpect(status().isUnsupportedMediaType())
                    .andExpect(jsonPath("$.title").value("Unsupported Media Type"));
        }

        /**
         * A parameter the endpoint requires and the request left out. Unlike its sibling services
         * this one never mapped that by hand, so it was a 500 saying "the request could not be
         * completed" over a caller's own omission.
         */
        @Test
        @DisplayName("a query parameter the request left out is a 400, not a 500")
        void a_missing_required_parameter_is_a_400() throws Exception {
            mvc.perform(get("/probe/quote"))
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.status").value(400));
        }

        /**
         * Nothing a caller is refused with may say more about this service than the status does.
         * A 405 that started quoting the framework would put class names and our own routing into a
         * body, which is what the catch-all's comment promises it will never do.
         */
        @Test
        @DisplayName("and carries no internal detail in the body")
        void a_refusal_says_nothing_about_the_inside_of_the_service() throws Exception {
            String body = mvc.perform(get("/probe/transfers"))
                    .andReturn().getResponse().getContentAsString();

            assertThat(body)
                    .doesNotContain("org.springframework", "java.lang", "com.delivery")
                    .doesNotContain("Exception", "\tat ")
                    // Spring's own wording, which names the method and our routing decision.
                    .doesNotContain("not supported", "Supported methods");
        }

        /** Malformed JSON was already a 400 and stays one: its own handler is the specific match. */
        @Test
        @DisplayName("malformed JSON is still the 400 its own handler chose")
        void malformed_json_is_unchanged() throws Exception {
            mvc.perform(post("/probe/transfers")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{\"amountUsd\":"))
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.title").value("Malformed request"));
        }

        @Test
        void a_well_formed_transfer_still_reaches_the_endpoint() throws Exception {
            mvc.perform(post("/probe/transfers")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{\"amountUsd\":50}"))
                    .andExpect(status().isOk());
        }
    }

    /**
     * The same rule without a request behind it: a 4xx the framework chose is kept, and everything
     * else is still the catch-all's 500 with its ERROR and its stack trace.
     */
    @Nested
    @DisplayName("the catch-all")
    class CatchAll {

        @Test
        void keeps_the_status_a_framework_refusal_already_chose() {
            ProblemDetail problem =
                    handler.onUnexpected(new HttpRequestMethodNotSupportedException("GET"));

            assertThat(problem.getStatus()).isEqualTo(HttpStatus.METHOD_NOT_ALLOWED.value());
            assertThat(problem.getTitle()).isEqualTo("Method Not Allowed");
            assertThat(problem.getDetail()).doesNotContain("supported", "GET");
        }

        /**
         * A URL this service does not route. Its sibling services map this by hand; here it went to
         * the catch-all, so a typo in a path was answered the same way an outage is — and a retry,
         * which is what a 500 invites, could never succeed.
         */
        @Test
        void answers_404_for_a_path_this_service_does_not_route() {
            ProblemDetail problem =
                    handler.onUnexpected(new NoResourceFoundException(HttpMethod.GET, "api/transfrs"));

            assertThat(problem.getStatus()).isEqualTo(HttpStatus.NOT_FOUND.value());
            assertThat(problem.getTitle()).isEqualTo("Not Found");
        }

        /**
         * A 5xx the framework raises is a failure whatever raised it, so it keeps the catch-all's
         * answer. Only the 4xx half of {@code ErrorResponse} is a client's mistake.
         */
        @Test
        void still_answers_500_for_a_framework_failure_that_is_not_the_callers_fault() {
            ProblemDetail problem = handler.onUnexpected(new AsyncRequestTimeoutException());

            assertThat(problem.getStatus()).isEqualTo(HttpStatus.INTERNAL_SERVER_ERROR.value());
            assertThat(problem.getTitle()).isEqualTo("Internal error");
        }
    }

    /** The shapes the real controllers declare, and nothing else of them. */
    @RestController
    public static class Probe {

        @PostMapping("/probe/transfers")
        public String transfer(@RequestBody Map<String, Object> request) {
            return String.valueOf(request.size());
        }

        @GetMapping("/probe/quote")
        public String quote(@RequestParam BigDecimal amountUsd) {
            return amountUsd.toPlainString();
        }
    }
}
