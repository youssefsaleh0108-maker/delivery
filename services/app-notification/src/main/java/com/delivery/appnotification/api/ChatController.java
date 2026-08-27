package com.delivery.appnotification.api;

import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import org.slf4j.MDC;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.delivery.appnotification.domain.ChatMessage;
import com.delivery.appnotification.service.ChatService;
import com.delivery.platform.observability.CorrelationIdFilter;
import com.delivery.platform.security.CurrentUser;

/**
 * The chat a customer and their rider have about one order.
 *
 * <p><strong>There is no parameter anywhere in this controller that names a user.</strong> Every
 * endpoint reads the caller's {@code sub} from the validated token and passes it down, exactly as
 * {@code InAppNotificationController} does with the inbox. Combined with membership being a property
 * of the conversation row, that makes reading or posting to somebody else's conversation
 * unexpressible rather than merely checked — there is no request a rider could compose that names
 * another rider's thread and no field they could tamper with.
 *
 * <p><strong>And no endpoint that creates a conversation.</strong> One opens when Order Manager says
 * a rider was assigned; see {@code OrderChatLifecycleListener}. A create endpoint would need the
 * caller to name the participants, and a caller who can name participants can name the wrong ones.
 *
 * <p>Posting is REST rather than a STOMP frame even though the socket is right there. The socket is
 * the delivery path, not the write path: a client SEND would need its own membership check, its own
 * length validation and its own error channel, all duplicating what the resource-server filter
 * chain and bean validation give this method for free. {@code WebSocketConfiguration} refuses client
 * SEND frames outright for the same reason.
 */
@RestController
@RequestMapping("/api/chat")
public class ChatController {

    private final ChatService chat;

    public ChatController(ChatService chat) {
        this.chat = chat;
    }

    /** Every conversation the caller is in, most recently active first, each with its badge. */
    @GetMapping("/conversations")
    public List<ChatService.ConversationView> conversations() {
        return chat.conversationsFor(CurrentUser.requireId());
    }

    /**
     * The conversation attached to an order.
     *
     * <p>Here because the app holds an order id long before it holds a conversation id — the chat
     * button lives on the order screen. 404 when the caller is not in it, which is the same answer
     * they get for an order that does not exist.
     */
    @GetMapping("/orders/{orderId}/conversation")
    public ChatService.ConversationView forOrder(@PathVariable UUID orderId) {
        return chat.conversationForOrder(orderId, CurrentUser.requireId());
    }

    /**
     * The thread, from a cursor.
     *
     * <p>{@code afterSequence} is what makes a reconnect cheap and correct: a client that held 41
     * messages asks for everything after 41 and gets exactly what it missed while its socket was
     * down. Passing 0 — the default — fetches from the beginning, which is what a fresh open does.
     */
    @GetMapping("/conversations/{conversationId}/messages")
    public List<MessageView> messages(@PathVariable UUID conversationId,
                                      @RequestParam(defaultValue = "0") @Min(0) long afterSequence) {
        String me = CurrentUser.requireId();
        return chat.thread(conversationId, me, afterSequence).stream()
                .map(message -> MessageView.of(message, me))
                .toList();
    }

    /**
     * Says something.
     *
     * <p>201 with the stored message, so the client learns the sequence number it needs for its
     * next cursor and its read receipt. 422 if the text is refused, 409 if the conversation has
     * closed, 404 if it is not the caller's — see {@link ChatExceptionHandler}.
     */
    @PostMapping("/conversations/{conversationId}/messages")
    public ResponseEntity<MessageView> post(@PathVariable UUID conversationId,
                                            @Valid @RequestBody PostMessageRequest request) {
        String me = CurrentUser.requireId();
        ChatMessage message = chat.post(conversationId, me, request.text(),
                request.clientMessageId(), MDC.get(CorrelationIdFilter.MDC_KEY));
        return ResponseEntity.status(HttpStatus.CREATED).body(MessageView.of(message, me));
    }

    /**
     * "I have read up to here."
     *
     * <p>A cursor rather than a list of ids because that is what the client actually knows, and
     * because it stays correct if a frame arrived that the client never told us about.
     */
    @PostMapping("/conversations/{conversationId}/read")
    public Map<String, Integer> markRead(@PathVariable UUID conversationId,
                                         @Valid @RequestBody MarkReadRequest request) {
        return Map.of("updated",
                chat.markRead(conversationId, CurrentUser.requireId(), request.upToSequence()));
    }

    /**
     * The badge.
     *
     * <p>Its own endpoint for the same reason the inbox's is: it is polled on every app foreground
     * and on a timer, and returning whole threads to render a number would be most of this feature's
     * traffic.
     */
    @GetMapping("/unread-count")
    public ChatService.UnreadSummary unreadCount() {
        return chat.unreadSummary(CurrentUser.requireId());
    }

    /**
     * @param text           what to say. The cap here is a fast structural rejection so an absurd
     *                       body never reaches the service; the authoritative limit is
     *                       {@code delivery.chat.max-message-length}, applied in
     *                       {@code ChatMessageText} where every route into the table passes
     * @param clientMessageId the sender's own id, so a retry after a lost response does not post
     *                        twice. Optional — a client that omits it opts out of the guarantee
     */
    public record PostMessageRequest(
            @NotBlank @Size(max = 4000) String text,
            @Size(max = 64) String clientMessageId) {
    }

    public record MarkReadRequest(@Min(0) long upToSequence) {
    }

    /**
     * One message as a participant sees it.
     *
     * <p>Carries the sender's <em>role</em> and a {@code mine} flag, never the sender's user id.
     * There are only two people in the conversation, so the role says everything the UI needs, and
     * handing a rider the customer's Keycloak sub would give them a durable identifier for that
     * person that outlives the delivery.
     */
    public record MessageView(
            UUID id,
            long sequence,
            String senderRole,
            boolean mine,
            String text,
            Instant sentAt,
            Instant deliveredAt,
            Instant readAt) {

        static MessageView of(ChatMessage message, String viewerId) {
            return new MessageView(
                    message.getId(),
                    message.getSequenceNo(),
                    message.getSenderRole().name(),
                    message.getSenderId().equals(viewerId),
                    message.getBody(),
                    message.getCreatedAt(),
                    message.getDeliveredAt(),
                    message.getReadAt());
        }
    }
}
