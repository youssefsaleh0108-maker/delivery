package com.delivery.tracking.api;

import java.util.UUID;

import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.delivery.platform.security.CurrentUser;
import com.delivery.tracking.service.CheckoutTrackingService;
import com.delivery.tracking.service.CheckoutTrackingService.CheckoutNotFoundException;
import com.delivery.tracking.service.CheckoutView;

/**
 * A multi-shop checkout on one map — the customer's view of every shop they checked out together,
 * the riders on the way and the expected routes. See {@link CheckoutTrackingService} for what is
 * drawn and why nothing is guessed.
 *
 * <p>Its own controller rather than a route on {@link TrackingController}: the subject is a
 * customer's purchase rather than one delivery, and so is the audience. Only the checkout's
 * customer may read it (and the back office). A sibling order's merchant and the rider each have
 * their own order's tracking, and neither may learn which other shops the customer bought from;
 * the rider in particular sees only that they hold several of this customer's orders.
 *
 * <p>Roles are checked twice: by {@code @PreAuthorize} and again in the handler, as the attendance
 * controller does, so the refusal holds without the method-security proxy and is tested that way.
 */
@RestController
@RequestMapping("/api/tracking")
public class CheckoutTrackingController {

    private final CheckoutTrackingService checkouts;

    public CheckoutTrackingController(CheckoutTrackingService checkouts) {
        this.checkouts = checkouts;
    }

    /**
     * One checkout's map: shop pins, the door, each order's status and estimate, riders' latest
     * fixes once assigned, and the expected routes with how to draw them.
     *
     * <p>404 — identically — for a checkout that does not exist and for one that is not the
     * caller's, so checkout ids cannot be probed. A caller holding neither CUSTOMER nor BACKOFFICE
     * is refused by role before any lookup.
     */
    @GetMapping("/checkouts/{checkoutId}")
    @PreAuthorize("hasAnyRole('CUSTOMER','BACKOFFICE')")
    public CheckoutView checkout(@PathVariable UUID checkoutId) {
        String caller = CurrentUser.id().orElseThrow(NotSignedInException::new);
        boolean backoffice = CurrentUser.hasRole("BACKOFFICE");
        if (!backoffice && !CurrentUser.hasRole("CUSTOMER")) {
            throw new RoleRefusedException();
        }
        return checkouts.view(checkoutId, caller, backoffice);
    }

    static final class NotSignedInException extends RuntimeException {
    }

    static final class RoleRefusedException extends RuntimeException {
    }

    @ExceptionHandler(NotSignedInException.class)
    public ProblemDetail onNotSignedIn(NotSignedInException e) {
        return TrackingProblems.of(HttpStatus.UNAUTHORIZED, "Not signed in",
                "Sign in to see your order's map.");
    }

    @ExceptionHandler(RoleRefusedException.class)
    public ProblemDetail onRoleRefused(RoleRefusedException e) {
        return TrackingProblems.of(HttpStatus.FORBIDDEN, "Not allowed",
                "Your account cannot do that.");
    }

    /** No checkout id in the body: the caller already has it, and an echoed id is untrusted text. */
    @ExceptionHandler(CheckoutNotFoundException.class)
    public ProblemDetail onNotFound(CheckoutNotFoundException e) {
        return TrackingProblems.of(HttpStatus.NOT_FOUND, "Checkout not found", e.getMessage());
    }
}
