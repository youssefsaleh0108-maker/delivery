package com.delivery.appnotification.service;

import java.time.Instant;
import java.util.Date;
import java.util.List;
import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.core.MessageDeliveryMode;
import org.springframework.amqp.core.MessageProperties;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.messaging.simp.user.SimpSubscription;
import org.springframework.messaging.simp.user.SimpUser;
import org.springframework.messaging.simp.user.SimpUserRegistry;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.appnotification.domain.ChatMessageRepository;
import com.delivery.appnotification.domain.ChatParticipantRole;
import com.delivery.platform.notifications.ChatEvents;
import com.delivery.platform.observability.CorrelationIdFilter;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * Gets a stored chat message in front of its recipient: the live socket if they are on it, a push
 * notification if they are not.
 *
 * <p>Reuses the WebSocket this service already runs — the same broker, the same principal-scoped
 * user destinations, the same CONNECT-time token check — on a second queue,
 * {@value #CHAT_DESTINATION}. A separate realtime mechanism for chat would mean a second connection
 * per user, a second authentication path and a second thing to fail, all to carry frames the
 * existing one already carries.
 *
 * <p><strong>This never decides whether a message exists.</strong> By the time anything here runs
 * the row is committed. A frame that is not sent, or a push event that is not published, costs the
 * recipient a delay until their app next fetches the thread — the same trade
 * {@code InAppMessageService} makes, and what lets the reconnect path be a genuine fallback rather
 * than a second, divergent delivery route.
 */
@Service
public class ChatDelivery {

    private static final Logger log = LoggerFactory.getLogger(ChatDelivery.class);

    /** Clients subscribe to {@code /user/queue/chat}; Spring resolves the user prefix. */
    public static final String CHAT_DESTINATION = "/queue/chat";

    private final SimpMessagingTemplate websocket;
    private final SimpUserRegistry connectedUsers;
    private final ChatMessageRepository messages;
    private final RabbitTemplate rabbit;
    private final ObjectMapper objectMapper;
    private final ChatProperties properties;
    private final String exchange;

    public ChatDelivery(SimpMessagingTemplate websocket,
                        SimpUserRegistry connectedUsers,
                        ChatMessageRepository messages,
                        RabbitTemplate rabbit,
                        ObjectMapper objectMapper,
                        ChatProperties properties,
                        @Value("${delivery.outbox.exchange:delivery.events}") String exchange) {
        this.websocket = websocket;
        this.connectedUsers = connectedUsers;
        this.messages = messages;
        this.rabbit = rabbit;
        this.objectMapper = objectMapper;
        this.properties = properties;
        this.exchange = exchange;
    }

    /**
     * Delivers one message, live or by push.
     *
     * <p><strong>{@code REQUIRES_NEW} is load-bearing, not decoration.</strong> This runs from an
     * {@code afterCommit} callback, where the original transaction is finished but still bound to
     * the thread. A {@code REQUIRED} propagation would silently join that dead transaction and the
     * {@code delivered_at} update below would be thrown away on flush with no error anywhere — the
     * message would show as never delivered forever. A new transaction is the only correct
     * propagation here.
     *
     * <p>The frame goes out before the row is touched. If the update then fails, the recipient has
     * the message and the flag catches up when their client refetches; the reverse order would risk
     * a message flagged delivered that never left.
     */
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void deliver(Deliverable message) {
        if (isReachable(message.recipientId())) {
            try {
                websocket.convertAndSendToUser(message.recipientId(), CHAT_DESTINATION, frame(message));
                messages.markDelivered(List.of(message.messageId()), message.recipientId(), Instant.now());
                return;

            } catch (Exception e) {
                // They looked connected a microsecond ago and are not any more, or the broker
                // refused the frame. Falling through to the push is right: the alternative is a
                // recipient who is neither told nor pushed because they were briefly online.
                log.warn("Live chat frame for message {} failed; falling back to push",
                        message.messageId(), e);
            }
        }

        publishMissed(message);
    }

    /**
     * Whether a live frame has somewhere to land.
     *
     * <p>Being connected is not enough — the app holds this socket for order notifications too, so
     * a user can be connected with no chat subscription at all. Checking for the subscription means
     * such a user gets the push instead of a frame that is silently dropped at the broker.
     *
     * <p><strong>Single-instance assumption, inherited.</strong> This registry, like the in-memory
     * broker {@code WebSocketConfiguration} enables, only knows about sockets held by THIS process.
     * Scaled to two instances, a user connected to the other one reads as unreachable and gets a
     * redundant push on top of the frame they already received. That is the failure mode to expect
     * — a duplicate nudge, never a lost message — and it goes away with the same change that
     * removes the simple broker: a shared relay plus a registry behind it.
     */
    private boolean isReachable(String userId) {
        SimpUser user = connectedUsers.getUser(userId);
        if (user == null) {
            return false;
        }
        return user.getSessions().stream()
                .flatMap(session -> session.getSubscriptions().stream())
                .map(SimpSubscription::getDestination)
                // Matched on the suffix because what the registry records is the destination as the
                // client wrote it, "/user/queue/chat", while the broker rewrites it per session.
                .anyMatch(destination -> destination != null && destination.endsWith(CHAT_DESTINATION));
    }

    /**
     * Publishes the "they were not there" event for Notifications Manager to turn into a push.
     *
     * <p>See {@link ChatEvents} for why this is an event to the manager rather than a push command
     * straight to the connector, and why it does not go through the transactional outbox.
     */
    private void publishMissed(Deliverable message) {
        try {
            ChatEvents.MessageMissed event = new ChatEvents.MessageMissed(
                    message.orderId(),
                    message.conversationId(),
                    message.messageId(),
                    message.recipientId(),
                    message.recipientRole().name(),
                    message.senderRole().name(),
                    previewOf(message.text()),
                    message.sentAt(),
                    message.correlationId());

            MessageProperties props = new MessageProperties();
            props.setContentType(MessageProperties.CONTENT_TYPE_JSON);
            props.setDeliveryMode(MessageDeliveryMode.PERSISTENT);
            // Same dedupe key a consumer would get from the outbox relay: one message, one push.
            props.setMessageId(message.messageId().toString());
            props.setTimestamp(Date.from(Instant.now()));
            props.setHeader("eventType", ChatEvents.MESSAGE_MISSED);
            props.setHeader("aggregateType", ChatEvents.AGGREGATE_TYPE);
            props.setHeader("aggregateId", message.orderId().toString());
            if (message.correlationId() != null) {
                props.setCorrelationId(message.correlationId());
                props.setHeader(CorrelationIdFilter.MDC_KEY, message.correlationId());
            }

            rabbit.send(exchange, ChatEvents.MESSAGE_MISSED,
                    new Message(objectMapper.writeValueAsBytes(event), props));

            // Message id only. The body is private to two people and this log line is not.
            log.debug("Chat message {} missed its recipient; push requested", message.messageId());

        } catch (Exception e) {
            log.error("Could not request a push for chat message {}", message.messageId(), e);
        }
    }

    /**
     * What, if anything, of the message travels to a lock screen.
     *
     * <p>Capped hard rather than trusted to the connector. {@code PushPreparer} will truncate the
     * body it is given and reject the whole notification if the assembled payload passes FCM's 4KB
     * limit — and a rejected push is no push at all. Since the cap here is well under both, a
     * sender cannot compose a message long enough to suppress their own notification.
     */
    private String previewOf(String text) {
        if (!properties.getPushPreview().isEnabled()) {
            return null;
        }
        return ChatMessageText.preview(text, properties.getPushPreview().getMaxLength());
    }

    /**
     * The STOMP frame.
     *
     * <p>A record, serialised by the broker's Jackson converter. That is what makes the message
     * body safe on this path: whatever the sender typed — quotes, newlines, braces, a closing
     * script tag — is escaped as a JSON string value and cannot terminate the frame early or add a
     * field. Hand-assembling this payload as a string is the mistake that would undo it.
     */
    private static ChatFrame frame(Deliverable message) {
        return new ChatFrame(
                message.messageId(),
                message.conversationId(),
                message.orderId(),
                message.sequenceNo(),
                message.senderRole().name(),
                message.text(),
                message.sentAt());
    }

    /** What the recipient's client receives on {@value #CHAT_DESTINATION}. */
    public record ChatFrame(
            UUID id,
            UUID conversationId,
            UUID orderId,
            long sequence,
            String senderRole,
            String text,
            Instant sentAt) {
    }

    /**
     * Everything delivery needs, captured while the message was being written.
     *
     * <p>A snapshot rather than the entity: this is handed across a transaction boundary into an
     * {@code afterCommit} callback, where touching a detached entity is a lazy-loading exception
     * waiting to happen.
     */
    public record Deliverable(
            UUID messageId,
            UUID conversationId,
            UUID orderId,
            long sequenceNo,
            String recipientId,
            ChatParticipantRole recipientRole,
            ChatParticipantRole senderRole,
            String text,
            Instant sentAt,
            String correlationId) {
    }
}
