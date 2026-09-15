package com.delivery.appnotification.api;

import org.slf4j.MDC;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import com.delivery.appnotification.service.ConversationClosedException;
import com.delivery.appnotification.service.ConversationNotFoundException;
import com.delivery.appnotification.service.MessageRejectedException;
import com.delivery.appnotification.service.NeighbourhoodRoomService;
import com.delivery.appnotification.service.RoomExceptions;
import com.delivery.platform.observability.CorrelationIdFilter;

/**
 * Turns the chat service's refusals into responses a client can act on.
 *
 * <p>Scoped to the chat controllers rather than declared globally: this service also serves the
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
@RestControllerAdvice(assignableTypes = {ChatController.class, ChatBackofficeController.class,
        NeighbourhoodChatController.class, ChatModerationController.class, ShopChatController.class})
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

    /** A room or thread that does not exist and one that is not the caller's answer identically. */
    @ExceptionHandler(RoomExceptions.RoomNotFoundException.class)
    public ProblemDetail onRoomNotFound(RoomExceptions.RoomNotFoundException e) {
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(HttpStatus.NOT_FOUND, e.getMessage());
        problem.setTitle("Not found");
        return withCorrelation(problem);
    }

    /** 404 with a reason the app acts on — "choose your area" rather than "something went wrong". */
    @ExceptionHandler(RoomExceptions.NoNeighbourhoodException.class)
    public ProblemDetail onNoNeighbourhood(RoomExceptions.NoNeighbourhoodException e) {
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(HttpStatus.NOT_FOUND, e.getMessage());
        problem.setTitle("No neighbourhood");
        problem.setProperty("reason", e.getReason().name());
        return withCorrelation(problem);
    }

    /** 403 with when it ends, so the composer explains itself instead of failing each send. */
    @ExceptionHandler(RoomExceptions.MemberMutedException.class)
    public ProblemDetail onMuted(RoomExceptions.MemberMutedException e) {
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(HttpStatus.FORBIDDEN, e.getMessage());
        problem.setTitle("Muted");
        problem.setProperty("mutedUntil", e.getMutedUntil());
        return withCorrelation(problem);
    }

    /**
     * 403 with a reason, like the mute's but without an end: the room stays readable, and what would
     * open the composer is a delivery in the area, not the passing of time.
     */
    @ExceptionHandler(RoomExceptions.PostingLockedException.class)
    public ProblemDetail onPostingLocked(RoomExceptions.PostingLockedException e) {
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(HttpStatus.FORBIDDEN, e.getMessage());
        problem.setTitle("Posting locked");
        problem.setProperty("reason", NeighbourhoodRoomService.PostingStatus.NEEDS_DELIVERY.name());
        return withCorrelation(problem);
    }

    /** 503: whether the caller may post could not be checked, and nobody posts on a guess. */
    @ExceptionHandler(RoomExceptions.ProofUnavailableException.class)
    public ProblemDetail onProofUnavailable(RoomExceptions.ProofUnavailableException e) {
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(HttpStatus.SERVICE_UNAVAILABLE, e.getMessage());
        problem.setTitle("Temporarily unavailable");
        return withCorrelation(problem);
    }

    /** 429 with Retry-After: the one refusal whose instruction is "the same request, later". */
    @ExceptionHandler(RoomExceptions.SendRateLimitedException.class)
    public ResponseEntity<ProblemDetail> onRateLimited(RoomExceptions.SendRateLimitedException e) {
        long seconds = Math.max(1L, e.getRetryAfter().toSeconds());
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(HttpStatus.TOO_MANY_REQUESTS, e.getMessage());
        problem.setTitle("Slow down");
        problem.setProperty("retryAfterSeconds", seconds);
        return ResponseEntity.status(HttpStatus.TOO_MANY_REQUESTS)
                .header(HttpHeaders.RETRY_AFTER, Long.toString(seconds))
                .body(withCorrelation(problem));
    }

    /** 503: an answer this depends on could not be had, and guessing it either way is unsafe. */
    @ExceptionHandler(RoomExceptions.DirectoryUnavailableException.class)
    public ProblemDetail onDirectoryUnavailable(RoomExceptions.DirectoryUnavailableException e) {
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(HttpStatus.SERVICE_UNAVAILABLE, e.getMessage());
        problem.setTitle("Temporarily unavailable");
        return withCorrelation(problem);
    }

    /**
     * 409 with when it closed, the instruction a quiet thread gives: the order is on the shop's screen
     * and is theirs, so a 404 would be a lie the screen disproves, and nothing about the merchant as a
     * person is refused, which is what this service's 403s say (a mute, a missing delivery). What
     * changed is only time, as when a conversation closes.
     */
    @ExceptionHandler(RoomExceptions.OrderChatClosedException.class)
    public ProblemDetail onOrderChatClosed(RoomExceptions.OrderChatClosedException e) {
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(HttpStatus.CONFLICT, e.getMessage());
        problem.setTitle("Order chat closed");
        problem.setProperty("closedAt", e.getClosedAt());
        return withCorrelation(problem);
    }

    /** 503: whether an order is the caller's could not be checked, and no order is attached on a guess. */
    @ExceptionHandler(RoomExceptions.OrderUnavailableException.class)
    public ProblemDetail onOrderUnavailable(RoomExceptions.OrderUnavailableException e) {
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(HttpStatus.SERVICE_UNAVAILABLE, e.getMessage());
        problem.setTitle("Temporarily unavailable");
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
