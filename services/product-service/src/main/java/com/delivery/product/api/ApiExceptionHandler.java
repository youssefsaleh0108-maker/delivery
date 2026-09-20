package com.delivery.product.api;

import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.MissingPathVariableException;
import org.springframework.web.bind.MissingServletRequestParameterException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException;
import org.springframework.web.servlet.resource.NoResourceFoundException;

import com.delivery.platform.observability.CorrelationIdFilter;
import com.delivery.platform.storage.StorageException;
import com.delivery.product.service.CatalogService.CatalogRuleViolationException;
import com.delivery.product.service.CatalogService.CategoryNotFoundException;
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

    /**
     * A category id that names nothing the caller may file under.
     *
     * <p>404, like every other unknown id here. It came back as a 422 for a while, which told a
     * client its payload broke a rule when what had actually happened was a mistyped id — and left
     * the same request answered two different ways depending on which id was wrong.
     */
    @ExceptionHandler(CategoryNotFoundException.class)
    public ProblemDetail onCategoryNotFound(CategoryNotFoundException e) {
        return problem(HttpStatus.NOT_FOUND, "Category not found", e.getMessage());
    }

    /**
     * An order the caller cannot rate.
     *
     * <p>Its own mapping because this used to be raised as a store not-found carrying an order id:
     * a customer looking at a shop that plainly exists was told the shop did not. The message is
     * the service's own and is deliberately silent about whether the order exists.
     */
    @ExceptionHandler(com.delivery.product.service.ReviewService.OrderNotFoundException.class)
    public ProblemDetail onOrderNotFound(
            com.delivery.product.service.ReviewService.OrderNotFoundException e) {
        return problem(HttpStatus.NOT_FOUND, "Order not found", e.getMessage());
    }

    /** A promotion this shop does not have — withdrawing one used to answer 204 either way. */
    @ExceptionHandler(com.delivery.product.service.StoreService.OfferNotFoundException.class)
    public ProblemDetail onOfferNotFound(
            com.delivery.product.service.StoreService.OfferNotFoundException e) {
        return problem(HttpStatus.NOT_FOUND, "Offer not found", e.getMessage());
    }

    /**
     * Two categories cannot stand for one vertical.
     *
     * <p>409 as before, but raised before the write instead of falling out of
     * {@code uq_category_vertical}, so the detail names the category in the way rather than a
     * uniqueness rule the caller has no way to look up.
     */
    @ExceptionHandler(com.delivery.product.service.BannerService.VerticalTakenException.class)
    public ProblemDetail onVerticalTaken(
            com.delivery.product.service.BannerService.VerticalTakenException e) {
        return problem(HttpStatus.CONFLICT, "Vertical already represented", e.getMessage());
    }

    @ExceptionHandler(CatalogRuleViolationException.class)
    public ProblemDetail onRuleViolation(CatalogRuleViolationException e) {
        return problem(HttpStatus.UNPROCESSABLE_ENTITY, "Catalog rule violated", e.getMessage());
    }

    /**
     * A shop that cannot be listed yet: no opening hours, or no pin on the map.
     *
     * <p>422 with the {@code code} a client branches on ({@code STORE_HOURS_REQUIRED},
     * {@code STORE_PIN_REQUIRED}). It is not folded into the rule violation above precisely because
     * of the code: the merchant app has to send the merchant to the week's hours or to the map
     * picker, and choosing between them by matching English prose is not something that survives
     * translation. The detail is still a sentence, so an older client that ignores the code shows
     * something true.
     */
    @ExceptionHandler(com.delivery.product.domain.Store.NotListableException.class)
    public ProblemDetail onNotListable(com.delivery.product.domain.Store.NotListableException e) {
        ProblemDetail detail =
                problem(HttpStatus.UNPROCESSABLE_ENTITY, "Shop not ready to be listed", e.getMessage());
        detail.setProperty("code", e.getCode());
        return detail;
    }

    /**
     * A services applicant reaching a path that would open a shop for them — a first product, a
     * first scan — before their services shop is open.
     *
     * <p>A 422 like any catalogue rule, but with its own title, so a client can tell "open your
     * services shop first" apart from a rule about the product it sent.
     */
    @ExceptionHandler(com.delivery.product.service.StoreService.ServicesShopNotOpenedException.class)
    public ProblemDetail onServicesShopNotOpened(
            com.delivery.product.service.StoreService.ServicesShopNotOpenedException e) {
        return problem(HttpStatus.UNPROCESSABLE_ENTITY, "Services shop not opened", e.getMessage());
    }

    /**
     * Onboarding could not say whether a merchant with no shop applied to offer services, so no shop
     * was opened. A 503 rather than a guess: guessing "no" would open a restaurant that can never
     * become the services shop, and retrying is all it takes.
     */
    @ExceptionHandler(com.delivery.product.service.OnboardingApplicationClient
            .OnboardingUnavailableException.class)
    public ProblemDetail onOnboardingUnavailable(
            com.delivery.product.service.OnboardingApplicationClient.OnboardingUnavailableException e) {
        return problem(HttpStatus.SERVICE_UNAVAILABLE, "Onboarding unavailable",
                "Your shop could not be set up just now. Please try again in a moment.");
    }

    /**
     * A Merchant Blitz scan, photo or line the caller does not own, or that does not exist.
     *
     * <p>One answer for both, like every other id here: a 403 on another merchant's scan would
     * confirm the id is real.
     */
    @ExceptionHandler(com.delivery.product.service.CatalogScanService.CatalogScanNotFoundException.class)
    public ProblemDetail onScanNotFound(
            com.delivery.product.service.CatalogScanService.CatalogScanNotFoundException e) {
        return problem(HttpStatus.NOT_FOUND, "Scan not found", e.getMessage());
    }

    /**
     * The day's scans are spent. 429 with the limit in the body, so the client can say "5 a day"
     * rather than a bare "try later" — each scan is a paid vision call once a real provider is on.
     */
    @ExceptionHandler(com.delivery.product.service.CatalogScanService.ScanQuotaExceededException.class)
    public ProblemDetail onScanQuota(
            com.delivery.product.service.CatalogScanService.ScanQuotaExceededException e) {
        ProblemDetail detail = problem(HttpStatus.TOO_MANY_REQUESTS, "Scan limit reached", e.getMessage());
        detail.setProperty("limit", e.getLimit());
        return detail;
    }

    /** The scan is not in a state for that: already analysing, already complete, out of attempts. */
    @ExceptionHandler(com.delivery.product.service.CatalogScanService.ScanStateException.class)
    public ProblemDetail onScanState(com.delivery.product.service.CatalogScanService.ScanStateException e) {
        return problem(HttpStatus.CONFLICT, "Scan not ready for that", e.getMessage());
    }

    /**
     * A staff member who lacks one permission.
     *
     * <p>The permission is named in the body on purpose: "you cannot do that" sends a cashier to
     * their manager with nothing to act on, while naming the grant tells the manager which toggle
     * to flip.
     */
    @ExceptionHandler(com.delivery.product.service.StoreAccess.StoreAccessDeniedException.class)
    public ProblemDetail onPermissionDenied(
            com.delivery.product.service.StoreAccess.StoreAccessDeniedException e) {
        ProblemDetail detail = problem(HttpStatus.FORBIDDEN, "Permission required", e.getMessage());
        detail.setProperty("permission", e.getPermission().name());
        return detail;
    }

    /**
     * A store the caller has no relationship to.
     *
     * <p>404 rather than 403: someone poking at store ids should not be able to learn which ones
     * exist by the shape of the refusal.
     */
    @ExceptionHandler(StoreStaffController.StoreNotVisibleException.class)
    public ProblemDetail onStoreNotVisible(StoreStaffController.StoreNotVisibleException e) {
        return problem(HttpStatus.NOT_FOUND, "Store not found", e.getMessage());
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

    /**
     * A coordinate outside its range, half a pin, or (0, 0).
     *
     * <p>400 rather than 422: the value is malformed as a coordinate at all, not a well-formed one
     * that breaks a business rule. The message is the value object's own — it explains which rule
     * was broken, including why Null Island is refused, which is otherwise a baffling rejection.
     */
    @ExceptionHandler(com.delivery.product.domain.GeoPoint.InvalidCoordinateException.class)
    public ProblemDetail onInvalidCoordinate(
            com.delivery.product.domain.GeoPoint.InvalidCoordinateException e) {
        return problem(HttpStatus.BAD_REQUEST, "Invalid location", e.getMessage());
    }

    /**
     * An item search that cannot be run: nothing to search, a term too short or too long, too many terms,
     * or a barcode that is not 8 to 14 digits.
     *
     * <p>400 with the {@code code} a client branches on ({@code ItemSearchService.SEARCH_*}), since the
     * detail is prose. The detail is the service's own and names the rule, never the query.
     */
    @ExceptionHandler(com.delivery.product.service.ItemSearchService.SearchRefusedException.class)
    public ProblemDetail onSearchRefused(
            com.delivery.product.service.ItemSearchService.SearchRefusedException e) {
        ProblemDetail detail = problem(HttpStatus.BAD_REQUEST, "Search refused", e.getMessage());
        detail.setProperty("code", e.getCode());
        return detail;
    }

    /**
     * One account searched items more often than a person does ({@code ItemSearchThrottle}).
     *
     * <p>429 with {@code SEARCH_RATE_LIMITED}, and the wait both as Retry-After, which HTTP clients
     * understand, and in the body, which the app reads.
     */
    @ExceptionHandler(com.delivery.product.service.ItemSearchThrottle.SearchThrottledException.class)
    public ResponseEntity<ProblemDetail> onSearchThrottled(
            com.delivery.product.service.ItemSearchThrottle.SearchThrottledException e) {
        ProblemDetail detail = problem(HttpStatus.TOO_MANY_REQUESTS, "Too many searches", e.getMessage());
        detail.setProperty("code", e.getCode());
        detail.setProperty("retryAfterSeconds", e.getRetryAfterSeconds());
        return ResponseEntity.status(HttpStatus.TOO_MANY_REQUESTS)
                .header(HttpHeaders.RETRY_AFTER, Long.toString(e.getRetryAfterSeconds()))
                .body(detail);
    }

    /**
     * The database gave up on an item search at its statement timeout ({@code ItemSearchService}).
     *
     * <p>503 with {@code SEARCH_TIMED_OUT} and a Retry-After: nothing is wrong with the request, the
     * database is busier than a search may wait for, and the same search a little later may well
     * succeed. The detail never repeats the query.
     */
    @ExceptionHandler(com.delivery.product.service.ItemSearchService.SearchTimedOutException.class)
    public ResponseEntity<ProblemDetail> onSearchTimedOut(
            com.delivery.product.service.ItemSearchService.SearchTimedOutException e) {
        ProblemDetail detail = problem(HttpStatus.SERVICE_UNAVAILABLE, "Search timed out", e.getMessage());
        detail.setProperty("code", e.getCode());
        detail.setProperty("retryAfterSeconds", e.getRetryAfterSeconds());
        return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE)
                .header(HttpHeaders.RETRY_AFTER, Long.toString(e.getRetryAfterSeconds()))
                .body(detail);
    }

    /**
     * The geocoder could not answer.
     *
     * <p>503 and never an empty result. An address picker handed an empty list concludes the street
     * does not exist and tells the customer so; the failure has to arrive as a failure so the client
     * can offer a retry instead of a denial.
     *
     * <p>The message is passed through because it is written to be safe — it names the provider and
     * the condition, never a credential and never the query, which for a reverse lookup would be
     * somebody's exact location.
     */
    @ExceptionHandler(com.delivery.product.geocoding.GeocodingException.class)
    public ProblemDetail onGeocodingFailure(com.delivery.product.geocoding.GeocodingException e) {
        log.warn("Geocoding request could not be served: {}", e.getMessage());
        return problem(HttpStatus.SERVICE_UNAVAILABLE, "Geocoding unavailable", e.getMessage());
    }

    /**
     * A missing query parameter is the caller's mistake, and telling them so is the whole fix.
     * These were falling through to the catch-all 500 — noticed when a reverse-geocode call
     * spelled the parameters {@code lat}/{@code lng} and got "Internal error" back, which reads
     * as our fault and sends the caller debugging the wrong side of the wire.
     */
    @ExceptionHandler(MissingServletRequestParameterException.class)
    public ProblemDetail onBadParameter(MissingServletRequestParameterException e) {
        return problem(HttpStatus.BAD_REQUEST, "Bad request", e.getMessage());
    }

    /**
     * A path variable or query parameter that cannot be converted to the type the endpoint
     * declares — the observed case was a word landing in a {@code UUID} store-id slot.
     *
     * <p>400, with a detail written here rather than Spring's own. The framework message names
     * Java classes ("Failed to convert value of type 'java.lang.String' to required type
     * 'java.util.UUID'"), which describes our implementation and nothing about the request.
     * Naming the parameter and the type it should have been is the whole of what a caller can
     * act on.
     */
    @ExceptionHandler(MethodArgumentTypeMismatchException.class)
    public ProblemDetail onTypeMismatch(MethodArgumentTypeMismatchException e) {
        Class<?> requiredType = e.getRequiredType();
        String detail = requiredType == null
                ? "Parameter '" + e.getName() + "' has an invalid value"
                : "Parameter '" + e.getName() + "' is not a valid " + requiredType.getSimpleName();
        return problem(HttpStatus.BAD_REQUEST, "Bad request", detail);
    }

    /**
     * A path variable the handler declares but the matched URI did not supply.
     *
     * <p>Mapped alongside the type mismatch above so that no request which fails to bind a path
     * variable can reach the catch-all and become a 500 with nothing in it for the caller to fix.
     */
    @ExceptionHandler(MissingPathVariableException.class)
    public ProblemDetail onMissingPathVariable(MissingPathVariableException e) {
        return problem(HttpStatus.BAD_REQUEST, "Bad request",
                "Path variable '" + e.getVariableName() + "' is required");
    }

    /**
     * A body the parser could not read: malformed JSON, or a value outside an enum.
     *
     * <p>Sending {@code {"role":"JANITOR"}} was answered with a 500, which tells a caller their
     * request was our fault and invites a retry that can never succeed. Jackson's own message
     * names our Java classes and the accepted constants, so it is deliberately not echoed —
     * the field is enough for a caller to find the typo.
     */
    @ExceptionHandler(HttpMessageNotReadableException.class)
    public ProblemDetail onUnreadableBody(HttpMessageNotReadableException e) {
        String field = fieldOf(e);
        return problem(HttpStatus.BAD_REQUEST, "Bad request", field == null
                ? "The request body could not be read"
                : "Field '" + field + "' has a value this endpoint does not accept");
    }

    /**
     * A URL this service does not route.
     *
     * <p>Without this, a typo in a path fell through to the catch-all and came back as a 500,
     * so a client could not tell a wrong address from a broken server.
     */
    @ExceptionHandler(NoResourceFoundException.class)
    public ProblemDetail onNoResource(NoResourceFoundException e) {
        return problem(HttpStatus.NOT_FOUND, "Not found",
                "No endpoint at " + e.getHttpMethod() + " /" + e.getResourcePath());
    }

    /**
     * A constraint declared on the element of a body collection, rather than on the body itself.
     *
     * <p>Spring reports these as a different exception from the one above, and that exception is a
     * {@code ResponseStatusException} — which the catch-all at the bottom of this class would have
     * swallowed into a 500. So the day {@code List<@Valid HoursRequest>} started actually checking
     * each window, an out-of-range day would have gone from one unhelpful 500 to another. The
     * position in the list is reported because "one of these seven windows is wrong" is not
     * something a merchant can act on.
     */
    @ExceptionHandler(org.springframework.web.method.annotation.HandlerMethodValidationException.class)
    public ProblemDetail onElementValidationFailure(
            org.springframework.web.method.annotation.HandlerMethodValidationException e) {
        ProblemDetail detail = problem(HttpStatus.BAD_REQUEST, "Validation failed",
                "One or more fields are invalid");

        Map<String, String> errors = new LinkedHashMap<>();
        e.getParameterValidationResults().forEach(result -> {
            String at = result.getContainerIndex() == null
                    ? result.getMethodParameter().getParameterName()
                    : "[" + result.getContainerIndex() + "]";
            result.getResolvableErrors().forEach(error ->
                    errors.put(at + fieldOf(error), error.getDefaultMessage()));
        });
        detail.setProperty("errors", errors);
        return detail;
    }

    /** The offending field out of one element error, as a suffix, or "" when it names none. */
    private static String fieldOf(org.springframework.context.MessageSourceResolvable error) {
        if (error instanceof org.springframework.validation.FieldError field) {
            return "." + field.getField();
        }
        return "";
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

    /** What a stale product save is answered with, for a client to branch on: the detail is prose. */
    static final String PRODUCT_CHANGED = "PRODUCT_CHANGED";

    /** What a write refused by V36's take-down CHECK is answered with. */
    static final String OFFER_TAKEN_DOWN = "OFFER_TAKEN_DOWN";

    /** V36's CHECK that keeps a taken-down offer off sale. */
    private static final String TAKEDOWN_CHECK = "chk_product_takedown";

    /**
     * A save that read a product before another save changed it ({@code Product}'s version, V36).
     *
     * <p>409 with a code of its own. The save was judged on a product that is no longer there, so it is
     * refused whole rather than mixed into the change it missed, and only a reload helps: the next try
     * reads the product as it now is. The provider apps show the detail as it is written, so it says what
     * to do next rather than naming a lock.
     *
     * <p>Spring's translation of Hibernate's refusal at commit, and the persistence API's own exception for
     * a flush that meets it outside that translation. Product is the only versioned entity here.
     */
    @ExceptionHandler({org.springframework.dao.OptimisticLockingFailureException.class,
            jakarta.persistence.OptimisticLockException.class})
    public ProblemDetail onProductChanged(RuntimeException e) {
        log.info("Refused a save that read a product before it changed: {}", e.getMessage());
        ProblemDetail detail = problem(HttpStatus.CONFLICT, "Product changed",
                "This product changed while you were editing it. Reload it and try again.");
        detail.setProperty("code", PRODUCT_CHANGED);
        return detail;
    }

    /**
     * How Hibernate 6.6 reports a stale product save on PostgreSQL, which is not the optimistic-lock failure
     * above.
     *
     * <p>Product's {@code updated_at} is read back from the UPDATE itself ({@code @Generated}), and Hibernate
     * reads it before it counts the rows the UPDATE matched. When the version no longer matches there is no
     * row to read, so Hibernate throws a bare {@code HibernateException} saying the database returned no
     * generated values, and Spring passes that on as a {@code JpaSystemException}. Products are never
     * deleted, so for a product an UPDATE that matched no row is exactly a stale save, and it is answered as
     * one. {@code OfferModerationDatabaseTest} pins this against a real database, and keeps passing if a
     * later Hibernate throws the optimistic-lock failure instead.
     *
     * <p>Every other failure of this kind keeps the catch-all's answer.
     */
    @ExceptionHandler(org.springframework.orm.jpa.JpaSystemException.class)
    public ProblemDetail onPersistenceFailure(org.springframework.orm.jpa.JpaSystemException e) {
        return isStaleProductUpdate(e) ? onProductChanged(e) : onUnexpected(e);
    }

    /** Whether Hibernate found no product row to read generated columns back from, as a stale UPDATE leaves. */
    private static boolean isStaleProductUpdate(Throwable e) {
        String unread = "returned no natively generated values : "
                + com.delivery.product.domain.Product.class.getName();
        for (Throwable cause = e; cause != null; cause = cause.getCause()) {
            if (cause instanceof org.hibernate.HibernateException && cause.getMessage() != null
                    && cause.getMessage().endsWith(unread)) {
                return true;
            }
        }
        return false;
    }

    /**
     * A uniqueness clash is the caller's problem, not a server fault — most often re-creating a
     * category that already exists. Returning 500 here would make a retry-safe client give up.
     *
     * <p>Except {@code chk_product_takedown} (V36), which refuses to put a taken-down offer back on sale and
     * is worded as that. The provider apps show the detail as it is written, and "a uniqueness rule" tells
     * a provider nothing. Product refuses those acts first, and its version refuses a save read before the
     * take-down, so only a write that goes around Product can meet the CHECK.
     */
    @ExceptionHandler(DataIntegrityViolationException.class)
    public ProblemDetail onConflict(DataIntegrityViolationException e) {
        log.debug("Constraint violation", e);
        if (TAKEDOWN_CHECK.equalsIgnoreCase(violatedConstraint(e))) {
            ProblemDetail detail = problem(HttpStatus.CONFLICT, "Offer taken down",
                    "YouDrop has taken this offer down, so it cannot go back on sale until YouDrop restores it.");
            detail.setProperty("code", OFFER_TAKEN_DOWN);
            return detail;
        }
        return problem(HttpStatus.CONFLICT, "Conflict",
                "That resource already exists or violates a uniqueness rule");
    }

    /** The constraint the database refused a write on, as Hibernate read it from the error, or null. */
    private static String violatedConstraint(Throwable e) {
        for (Throwable cause = e; cause != null; cause = cause.getCause()) {
            if (cause instanceof org.hibernate.exception.ConstraintViolationException violation) {
                return violation.getConstraintName();
            }
        }
        return null;
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

    /**
     * The offending field name out of a Jackson binding failure, or null.
     *
     * <p>Only the path is taken; the message itself names our classes and is never surfaced.
     */
    private static String fieldOf(HttpMessageNotReadableException e) {
        Throwable cause = e.getCause();
        if (cause instanceof com.fasterxml.jackson.databind.exc.MismatchedInputException mismatch) {
            return mismatch.getPath().stream()
                    .map(com.fasterxml.jackson.databind.JsonMappingException.Reference::getFieldName)
                    .filter(java.util.Objects::nonNull)
                    .reduce((first, second) -> first + "." + second)
                    .orElse(null);
        }
        return null;
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
