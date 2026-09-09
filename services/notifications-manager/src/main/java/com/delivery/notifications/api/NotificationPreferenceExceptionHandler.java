package com.delivery.notifications.api;

import java.time.Instant;

import org.slf4j.MDC;
import org.springframework.http.HttpStatus;
import org.springframework.http.HttpStatusCode;
import org.springframework.http.ProblemDetail;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.server.ResponseStatusException;

import com.delivery.platform.observability.CorrelationIdFilter;

/**
 * Puts the settings screen's refusals back into the response body.
 *
 * <p>The three ways a preference change is refused are three different instructions to the person
 * at the settings screen — pick a category that exists, pick a channel that exists, stop trying to
 * silence security notices — and {@link NotificationPreferenceController} authors a sentence for
 * each. Without this advice all three arrive as the same empty 400: a bare
 * {@code ResponseStatusException} is rendered by the container's error page, which omits the reason
 * unless {@code server.error.include-message} is turned on, and turning that on globally would also
 * start leaking framework and binding messages the platform deliberately keeps in.
 *
 * <p>So the reason is rendered here instead, and only the reason. A refusal that carries none is
 * one Spring raised rather than one of ours, and is answered generically rather than by echoing
 * whatever the framework put in the message.
 *
 * <p>Scoped to the preference controller rather than declared globally, on the same reasoning as
 * app-notification's chat advice: the other controllers in this service choose their own status
 * codes and bodies, and an advice that quietly began intercepting them would change responses
 * nobody asked to change.
 */
@RestControllerAdvice(assignableTypes = NotificationPreferenceController.class)
public class NotificationPreferenceExceptionHandler {

    @ExceptionHandler(ResponseStatusException.class)
    public ProblemDetail onRefusal(ResponseStatusException e) {
        HttpStatusCode status = e.getStatusCode();
        String reason = e.getReason();

        ProblemDetail problem = ProblemDetail.forStatusAndDetail(status,
                reason == null || reason.isBlank() ? "The change was refused" : reason);

        HttpStatus resolved = HttpStatus.resolve(status.value());
        problem.setTitle(resolved == null ? "Change refused" : resolved.getReasonPhrase());
        problem.setProperty("timestamp", Instant.now());

        // The one value a user reporting "it just said no" can hand over to find this request
        // across the Gateway and this service.
        String correlationId = MDC.get(CorrelationIdFilter.MDC_KEY);
        if (correlationId != null) {
            problem.setProperty("correlationId", correlationId);
        }
        return problem;
    }
}
