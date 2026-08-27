package com.delivery.tracking.api;

import org.slf4j.MDC;
import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;

import com.delivery.platform.observability.CorrelationIdFilter;

/**
 * Builds the RFC 7807 bodies this service returns, with the correlation id attached.
 *
 * <p>Extracted once there was a second controller: the correlation id on an error body is what lets
 * a support engineer find the request in the logs, and a handler that quietly forgot to attach it
 * would leave a caller holding a message and no way to have it looked up. One place to get right.
 *
 * <p>Nothing here interpolates a caller-supplied value into a detail message. These bodies are
 * rendered by web and mobile clients, and an id echoed out of a request path is untrusted text.
 */
final class TrackingProblems {

    private TrackingProblems() {
    }

    static ProblemDetail of(HttpStatus status, String title, String detail) {
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(status, detail);
        problem.setTitle(title);

        String correlationId = MDC.get(CorrelationIdFilter.MDC_KEY);
        if (correlationId != null) {
            problem.setProperty("correlationId", correlationId);
        }
        return problem;
    }
}
