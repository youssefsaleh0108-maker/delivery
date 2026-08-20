package com.delivery.product.api;

import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import com.delivery.platform.observability.CorrelationIdFilter;
import com.delivery.platform.storage.StorageException;
import com.delivery.product.service.CatalogService.CatalogRuleViolationException;
import com.delivery.product.service.CatalogService.ProductNotFoundException;
import com.delivery.product.service.StoreService.StoreNotFoundException;

/**
 * Turns domain exceptions into RFC 9457 problem responses.
 *
 * <p>Every response carries the correlation id, so a user reporting "it failed" hands over the one
 * value that finds the request across the Gateway, this service and the bus (Section 10).
 */
@RestControllerAdvice
public class ApiExceptionHandler {

    private static final Logger log = LoggerFactory.getLogger(ApiExceptionHandler.class);

    @ExceptionHandler(ProductNotFoundException.class)
    public ProblemDetail onNotFound(ProductNotFoundException e) {
        return problem(HttpStatus.NOT_FOUND, "Product not found", e.getMessage());
    }

    /**
     * A missing store is a 404, and so is one the caller may not see.
     *
     * <p>The service throws the same exception for both, deliberately — a 403 on an unlisted store
     * would confirm it exists. Without this mapping the exception falls through to the catch-all
     * below and the client gets a 500, which is what happened the first time.
     */
    @ExceptionHandler(StoreNotFoundException.class)
    public ProblemDetail onStoreNotFound(StoreNotFoundException e) {
        return problem(HttpStatus.NOT_FOUND, "Store not found", e.getMessage());
    }

    @ExceptionHandler(CatalogRuleViolationException.class)
    public ProblemDetail onRuleViolation(CatalogRuleViolationException e) {
        return problem(HttpStatus.UNPROCESSABLE_ENTITY, "Catalog rule violated", e.getMessage());
    }

    /**
     * A delivery area that does not exist, and one that already does.
     *
     * <p>Mapped explicitly for the same reason the store cases above are: without a handler these
     * fall through to the catch-all and become a 500, which tells a caller nothing about a
     * situation they can fix by choosing another name.
     */
    @ExceptionHandler(com.delivery.product.service.DeliveryZoneService.ZoneNotFoundException.class)
    public ProblemDetail onZoneNotFound(
            com.delivery.product.service.DeliveryZoneService.ZoneNotFoundException e) {
        return problem(HttpStatus.NOT_FOUND, "Delivery area not found", e.getMessage());
    }

    @ExceptionHandler(com.delivery.product.service.DeliveryZoneService.ZoneConflictException.class)
    public ProblemDetail onZoneConflict(
            com.delivery.product.service.DeliveryZoneService.ZoneConflictException e) {
        return problem(HttpStatus.CONFLICT, "Delivery area already exists", e.getMessage());
    }

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

    /**
     * A uniqueness clash is the caller's problem, not a server fault — most often re-creating a
     * category that already exists. Returning 500 here would make a retry-safe client give up.
     */
    @ExceptionHandler(DataIntegrityViolationException.class)
    public ProblemDetail onConflict(DataIntegrityViolationException e) {
        log.debug("Constraint violation", e);
        return problem(HttpStatus.CONFLICT, "Conflict",
                "That resource already exists or violates a uniqueness rule");
    }

    @ExceptionHandler(AccessDeniedException.class)
    public ProblemDetail onAccessDenied(AccessDeniedException e) {
        return problem(HttpStatus.FORBIDDEN, "Forbidden",
                "Your account does not have permission to perform this action");
    }

    @ExceptionHandler(StorageException.class)
    public ProblemDetail onStorageFailure(StorageException e) {
        // Storage failures are frequently the client's fault (unsupported type, never uploaded,
        // too large) but can also be MinIO being down, so log the detail and return a safe message.
        log.warn("Storage operation failed", e);
        return problem(HttpStatus.UNPROCESSABLE_ENTITY, "Upload failed", e.getMessage());
    }

    @ExceptionHandler(Exception.class)
    public ProblemDetail onUnexpected(Exception e) {
        log.error("Unhandled exception", e);
        // Never echo an internal message: stack traces and SQL leak schema details to callers.
        return problem(HttpStatus.INTERNAL_SERVER_ERROR, "Internal error",
                "The request could not be completed");
    }

    private static ProblemDetail problem(HttpStatus status, String title, String detail) {
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(status, detail);
        problem.setTitle(title);
        problem.setProperty("timestamp", Instant.now());

        String correlationId = org.slf4j.MDC.get(CorrelationIdFilter.MDC_KEY);
        if (correlationId != null) {
            problem.setProperty("correlationId", correlationId);
        }
        return problem;
    }
}
