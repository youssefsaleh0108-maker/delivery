package com.delivery.transfer.api;

import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;
import org.springframework.http.HttpStatus;
import org.springframework.http.HttpStatusCode;
import org.springframework.http.ProblemDetail;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.server.ResponseStatusException;

import com.delivery.platform.observability.CorrelationIdFilter;
import com.delivery.transfer.client.OrderManagerClient.OrderUnavailableException;

/**
 * Refusals to RFC 9457 problem responses, each carrying the correlation id so a customer
 * reporting "it wouldn't take my payment" hands over the one value that finds the request
 * everywhere (Section 10).
 *
 * <p>Without this advice every refusal in the service left through Spring's default error path,
 * which drops the reason: "splitUsd must be between 0 and amountUsd", "No provider currently
 * carries WHISH" and "Not your order" all reached the app as the same empty 400. The wording is
 * written where the refusal is decided precisely because those are three different things for a
 * customer to do about, and a client that cannot tell them apart can only say "something went
 * wrong".
 */
@RestControllerAdvice
public class ApiExceptionHandler {

    private static final Logger log = LoggerFactory.getLogger(ApiExceptionHandler.class);

    /**
     * The services' own refusals. The status the thrower chose is kept — 422 for a rule the
     * payload broke, 404 for something that is not there, 403 for someone else's — and so is its
     * wording.
     */
    @ExceptionHandler(ResponseStatusException.class)
    public ProblemDetail onResponseStatus(ResponseStatusException e) {
        HttpStatusCode status = e.getStatusCode();
        String reason = e.getReason();
        return problem(status, titleFor(status),
                reason != null && !reason.isBlank()
                        ? reason
                        : "The request could not be completed");
    }

    /**
     * 422, matching the rest of the money paths: the payload was well-formed, the order behind it
     * was not one this customer can pay for. The client's own explanation is carried through — the
     * customer can act on "That order does not exist, or is not yours" and cannot act on a bare
     * status code.
     */
    @ExceptionHandler(OrderUnavailableException.class)
    public ProblemDetail onOrderUnavailable(OrderUnavailableException e) {
        return problem(HttpStatus.UNPROCESSABLE_ENTITY, "Order unavailable", e.getMessage());
    }

    /**
     * A field the request had to carry and did not. Naming the fields is the whole point: a
     * missing {@code amountUsd} used to reach the arithmetic and answer 500, which told the caller
     * the platform was broken over their own omission.
     */
    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ProblemDetail onValidationFailure(MethodArgumentNotValidException e) {
        ProblemDetail detail = problem(HttpStatus.BAD_REQUEST, "Validation failed",
                "One or more fields are invalid");
        Map<String, String> errors = new LinkedHashMap<>();
        e.getBindingResult().getFieldErrors()
                .forEach(error -> errors.put(error.getField(), error.getDefaultMessage()));
        detail.setProperty("errors", errors);
        return detail;
    }

    @ExceptionHandler(AccessDeniedException.class)
    public ProblemDetail onAccessDenied(AccessDeniedException e) {
        return problem(HttpStatus.FORBIDDEN, "Forbidden",
                "Your account does not have permission to perform this action");
    }

    /**
     * A body Jackson could not turn into the DTO — malformed JSON, or a value outside an enum like
     * {@code "method":"CRYPTO"}. That is the caller's payload being wrong, which is the definition
     * of 400. The message stays generic on purpose: Jackson's own text names internal types.
     */
    @ExceptionHandler(HttpMessageNotReadableException.class)
    public ProblemDetail onUnreadableBody(HttpMessageNotReadableException e) {
        return problem(HttpStatus.BAD_REQUEST, "Malformed request",
                "The request body could not be read — check field values and types");
    }

    @ExceptionHandler(Exception.class)
    public ProblemDetail onUnexpected(Exception e) {
        log.error("Unhandled exception", e);
        // Never echo an internal message: stack traces and SQL leak schema details to callers.
        return problem(HttpStatus.INTERNAL_SERVER_ERROR, "Internal error",
                "The request could not be completed");
    }

    /** A title from the status alone, so no refusal has to repeat itself to get one. */
    private static String titleFor(HttpStatusCode status) {
        HttpStatus known = HttpStatus.resolve(status.value());
        return known != null ? known.getReasonPhrase() : "Request refused";
    }

    private static ProblemDetail problem(HttpStatusCode status, String title, String detail) {
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(status, detail);
        problem.setTitle(title);
        problem.setProperty("timestamp", Instant.now());
        String correlationId = MDC.get(CorrelationIdFilter.MDC_KEY);
        if (correlationId != null) {
            problem.setProperty("correlationId", correlationId);
        }
        return problem;
    }
}
