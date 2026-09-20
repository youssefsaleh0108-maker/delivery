package com.delivery.tracking.api;

import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import com.delivery.platform.security.CurrentUser;
import com.delivery.tracking.service.FixPolicy.FixRejectedException;
import com.delivery.tracking.service.PresenceService.OffDutyException;

/**
 * Who may report a position, and the answers a report can get, for the two routes that take one:
 * {@code POST /api/tracking/orders/{id}/ping} and {@code POST /api/tracking/riders/me/ping}.
 *
 * <p>One place because one handset sends both, and the app reads their refusals the same way: a
 * 422 carries a machine-readable {@code reason} (see {@link com.delivery.tracking.service.FixPolicy.Reason})
 * which the app acts on when it says the phone's clock is wrong, and a 409 says the rider's state
 * — off duty, or a delivery already finished — is why nothing was recorded.
 *
 * <p>Scoped to those two controllers so it cannot change what any other route answers.
 */
@RestControllerAdvice(assignableTypes = {TrackingController.class, RiderPresenceController.class})
public class PingProblems {

    /**
     * The caller's subject, provided they are a rider.
     *
     * <p>A second check behind {@code @PreAuthorize("hasRole('DELIVERY')")}, as the attendance
     * routes do it: method security is a proxy, and a refusal that holds only while the proxy is
     * there cannot be tested standalone and will one day stop holding. A customer's token must
     * not be able to write a position under the customer's own name even then.
     */
    static String rider() {
        String id = CurrentUser.id().orElseThrow(NotSignedInException::new);
        if (!CurrentUser.hasRole("DELIVERY")) {
            throw new NotARiderException();
        }
        return id;
    }

    /**
     * 422: the report was understood and refused on its content. Not a 400 — the body is well
     * formed — and not silently accepted, because a handset that keeps sending a future-dated fix
     * needs to learn that its clock is wrong, and a silent 202 would teach it nothing.
     */
    @ExceptionHandler(FixRejectedException.class)
    public ProblemDetail onRejected(FixRejectedException e) {
        ProblemDetail problem = TrackingProblems.of(HttpStatus.UNPROCESSABLE_ENTITY,
                "Location not recorded", e.getMessage());
        problem.setProperty("reason", e.reason().name());
        return problem;
    }

    @ExceptionHandler(OffDutyException.class)
    public ProblemDetail onOffDuty(OffDutyException e) {
        return TrackingProblems.of(HttpStatus.CONFLICT, "Off duty", e.getMessage());
    }

    @ExceptionHandler(NotSignedInException.class)
    public ProblemDetail onNotSignedIn(NotSignedInException e) {
        return TrackingProblems.of(HttpStatus.UNAUTHORIZED, "Not signed in",
                "Sign in to share your location.");
    }

    @ExceptionHandler(NotARiderException.class)
    public ProblemDetail onNotARider(NotARiderException e) {
        return TrackingProblems.of(HttpStatus.FORBIDDEN, "Riders only",
                "Only a rider's app reports a location here.");
    }

    static final class NotSignedInException extends RuntimeException {
    }

    static final class NotARiderException extends RuntimeException {
    }
}
