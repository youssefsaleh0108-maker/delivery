package com.delivery.whatsapp.web;

import java.util.List;
import java.util.UUID;

import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.delivery.platform.security.CurrentUser;
import com.delivery.whatsapp.service.ConversationService;
import com.delivery.whatsapp.web.dto.ConversationView;
import com.delivery.whatsapp.web.dto.MessageView;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

/**
 * The merchant's side of the front door: their inbox, and the threads in it.
 *
 * <p>Every method scopes on the caller's own {@code sub}. A merchant cannot name a merchant, so
 * there is no request that could read another shop's customers — the ownership check is the query,
 * not a test applied to a row already loaded.
 */
@RestController
@RequestMapping("/api/whatsapp/conversations")
@PreAuthorize("hasRole('MERCHANT')")
public class ConversationController {

    private final ConversationService conversations;

    public ConversationController(ConversationService conversations) {
        this.conversations = conversations;
    }

    @GetMapping
    public List<ConversationView> inbox(
            @RequestParam(name = "archived", defaultValue = "false") boolean archived) {
        return conversations.inbox(CurrentUser.requireId(), archived).stream()
                .map(ConversationView::of)
                .toList();
    }

    @GetMapping("/{id}")
    public ResponseEntity<ConversationView> one(@PathVariable UUID id) {
        return conversations.find(id, CurrentUser.requireId())
                .map(ConversationView::of)
                .map(ResponseEntity::ok)
                .orElseGet(() -> ResponseEntity.notFound().build());
    }

    /**
     * The thread.
     *
     * <p>404 for a conversation belonging to someone else, the same answer as one that does not
     * exist. Telling an unauthorised caller "that exists but is not yours" confirms a customer is
     * talking to a competitor, which is not ours to reveal.
     */
    @GetMapping("/{id}/messages")
    public ResponseEntity<List<MessageView>> thread(@PathVariable UUID id) {
        return conversations.find(id, CurrentUser.requireId())
                .map(conversation -> ResponseEntity.ok(
                        conversations.thread(conversation.getId()).stream()
                                .map(MessageView::of)
                                .toList()))
                .orElseGet(() -> ResponseEntity.notFound().build());
    }

    /**
     * The merchant answering.
     *
     * <p>202, not 200, and the body says whether it actually went out. A merchant who sees no trace
     * of a message they typed will type it again — so the reply is always recorded in the thread,
     * with {@code sent: false} when the provider refused it. One honest failure beats three
     * duplicate sends.
     */
    @PostMapping("/{id}/reply")
    public ResponseEntity<ReplyResult> reply(@PathVariable UUID id,
                                             @Valid @RequestBody ReplyRequest request) {
        ConversationService.Reply reply =
                conversations.reply(id, CurrentUser.requireId(), request.body());
        return ResponseEntity.accepted().body(new ReplyResult(
                MessageView.of(reply.message()), reply.sent(), reply.failureDetail()));
    }

    public record ReplyRequest(@NotBlank @Size(max = 4000) String body) {
    }

    public record ReplyResult(MessageView message, boolean sent, String failureDetail) {
    }

    /** A conversation that is not this merchant's reads as absent — see the note above. */
    @ExceptionHandler(ConversationService.UnknownConversationException.class)
    public ResponseEntity<Void> unknown(ConversationService.UnknownConversationException e) {
        return ResponseEntity.notFound().build();
    }

    @PostMapping("/{id}/read")
    public ResponseEntity<ConversationView> markRead(@PathVariable UUID id) {
        return conversations.markRead(id, CurrentUser.requireId())
                .map(ConversationView::of)
                .map(ResponseEntity::ok)
                .orElseGet(() -> ResponseEntity.notFound().build());
    }

    @PostMapping("/{id}/archive")
    public ResponseEntity<ConversationView> archive(@PathVariable UUID id) {
        return conversations.archive(id, CurrentUser.requireId())
                .map(ConversationView::of)
                .map(ResponseEntity::ok)
                .orElseGet(() -> ResponseEntity.notFound().build());
    }
}
