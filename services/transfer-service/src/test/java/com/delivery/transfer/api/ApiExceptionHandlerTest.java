package com.delivery.transfer.api;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.mock.http.MockHttpInputMessage;
import org.springframework.web.server.ResponseStatusException;

import com.delivery.transfer.client.OrderManagerClient.OrderUnavailableException;

import static org.assertj.core.api.Assertions.assertThat;

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
}
