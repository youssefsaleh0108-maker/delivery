package com.delivery.appnotification.api;

import org.slf4j.MDC;
import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import com.delivery.appnotification.service.ConversationClosedException;
import com.delivery.appnotification.service.ConversationNotFoundException;
import com.delivery.appnotification.service.MessageRejectedException;
import com.delivery.platform.observability.CorrelationIdFilter;

/**
 * Turns the chat service's refusals into responses a client can act on.
 *
 * <p>Scoped to the two chat controllers rather than declared globally: this service also serves the
 * in-app inbox, whose controller answers with status codes directly, and a global advice would
 * quietly start intercepting anything a later endpoint throws.
 *
 * <p>The three statuses are three different instructions to the client, which is the whole reason
 * they are not collapsed: 404 means stop asking, 409 means the thread is readable but the composer
 * should be disabled, 422 means show the sender what they typed and let them fix it.
 *
 * <p>None of these details ever contains the message body. The exception messages are written not
 * to quote the sender's text, and a ProblemDetail is one of the places untrusted input most easily
 * ends up rendered somewhere it should not be.
 */
@RestControllerAdvice(assignableTypes = {ChatController.class, ChatBackofficeController.class})
public class ChatExceptionHandler {

    @ExceptionHandler(ConversationNotFoundException.class)
    public ProblemDetail onNotFound(ConversationNotFoundException e) {
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(HttpStatus.NOT_FOUND, e.getMessage());
        problem.setTitle("Conversation not found");
        return withCorrelation(problem);
    }

    @ExceptionHandler(ConversationClosedException.class)
    public ProblemDetail onClosed(ConversationClosedException e) {
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(HttpStatus.CONFLICT, e.getMessage());
        problem.setTitle("Conversation closed");
        // The client shows "this chat closed at ..." rather than a bare failure, which is the
        // difference between a customer understanding and a customer retrying.
        problem.setProperty("closedAt", e.getClosedAt());
        return withCorrelation(problem);
    }

    @ExceptionHandler(MessageRejectedException.class)
    public ProblemDetail onRejected(MessageRejectedException e) {
        // 422, not 400: the request was well-formed and understood, and refusing it is a decision
        // about its content. A client treats a 400 as its own bug and a 422 as something to show
        // the person typing.
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(
                HttpStatus.UNPROCESSABLE_ENTITY, e.getMessage());
        problem.setTitle("Message rejected");
        return withCorrelation(problem);
    }

    private static ProblemDetail withCorrelation(ProblemDetail problem) {
        String correlationId = MDC.get(CorrelationIdFilter.MDC_KEY);
        if (correlationId != null) {
            problem.setProperty("correlationId", correlationId);
        }
        return problem;
    }
}
