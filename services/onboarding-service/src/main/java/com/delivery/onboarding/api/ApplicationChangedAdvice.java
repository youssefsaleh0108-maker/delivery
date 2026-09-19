package com.delivery.onboarding.api;

import java.util.Map;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.OptimisticLockingFailureException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

/**
 * 409 for a write that lost a race on an application, from every controller in this package.
 *
 * <p>The application carries a version (V46), so of two overlapping writes the later one fails and
 * changes nothing, where it used to overwrite the earlier one whole. The answer to that used to live
 * on {@link OnboardingController} alone, so the same conflict reached through another controller —
 * back office correcting a record with {@code PATCH /applications/{id}} on
 * {@link PartnerManagementController} while an applicant's sign-in was being recorded, say — fell
 * through to a 500 that told the caller nothing. It is answered here once, for the whole package:
 * every optimistic-lock failure in this service is about an application, because the application is
 * the only versioned entity it has.
 *
 * <p>A handler written on a controller itself still wins over this one, as Spring resolves them, so
 * a controller that ever needs its own wording can have it.
 */
@RestControllerAdvice(basePackageClasses = OnboardingController.class)
public class ApplicationChangedAdvice {

    private static final Logger LOG = LoggerFactory.getLogger(ApplicationChangedAdvice.class);

    /** The code the portal and the app translate. */
    public static final String CODE = "application-changed";

    /**
     * Somebody else wrote this application between this request reading it and writing it — an
     * applicant's sign-in being recorded while a reviewer decided, say. Nothing is half done:
     * opening the application again shows where it stands.
     */
    @ExceptionHandler(OptimisticLockingFailureException.class)
    public ResponseEntity<Map<String, String>> changedMeanwhile(OptimisticLockingFailureException e) {
        LOG.info("An application changed while a request was writing it", e);
        return ResponseEntity.status(HttpStatus.CONFLICT).body(Map.of(
                "message", "This application changed while you were working on it. Open it again "
                        + "to see where it stands.",
                "code", CODE));
    }
}
