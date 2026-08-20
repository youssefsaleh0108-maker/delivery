package com.delivery.appnotification.service;

import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.data.domain.PageRequest;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

import com.delivery.appnotification.domain.InAppMessage;
import com.delivery.appnotification.domain.InAppMessageRepository;

/**
 * Persists in-app messages and pushes them to whoever is currently connected.
 *
 * <p>Persist first, push second, and the push happens after commit. A WebSocket frame is fire and
 * forget — if it went out before the transaction committed and the commit then failed, the user
 * would have a message on screen that vanishes on refresh, which is worse than a message that
 * arrives a moment late.
 *
 * <p>The WebSocket is an optimisation, not the delivery mechanism. The row is the delivery; the
 * frame just saves a poll. That is what lets the REST fallback be a genuine fallback rather than a
 * second, divergent path.
 */
@Service
public class InAppMessageService {

    private static final Logger log = LoggerFactory.getLogger(InAppMessageService.class);

    /** Clients subscribe to {@code /user/queue/notifications}; Spring resolves the user prefix. */
    static final String USER_DESTINATION = "/queue/notifications";

    private final InAppMessageRepository messages;
    private final SimpMessagingTemplate websocket;

    public InAppMessageService(InAppMessageRepository messages, SimpMessagingTemplate websocket) {
        this.messages = messages;
        this.websocket = websocket;
    }

    /**
     * Records a message, unless it is a redelivery of one already recorded.
     *
     * @return true if this was a new message
     */
    @Transactional
    public boolean record(UUID notificationId, String userId, UUID orderId, String eventType,
                          String title, String body, Map<String, String> metadata) {

        if (messages.existsByNotificationId(notificationId)) {
            // Normal, not exceptional: bus delivery is at-least-once, and one status change must
            // not put two identical items in someone's inbox.
            log.debug("In-app message for notification {} already recorded", notificationId);
            return false;
        }

        InAppMessage message = messages.save(new InAppMessage(
                userId, notificationId, orderId, eventType, title, body, metadata));

        pushAfterCommit(message);
        return true;
    }

    @Transactional(readOnly = true)
    public List<InAppMessage> inbox(String userId, int limit) {
        return messages.findByUserIdOrderByCreatedAtDesc(userId, PageRequest.of(0, limit));
    }

    @Transactional(readOnly = true)
    public long unreadCount(String userId) {
        return messages.countByUserIdAndReadAtIsNull(userId);
    }

    /**
     * Marks one message read, scoped to its owner.
     *
     * @return false if the message does not exist <em>or</em> belongs to someone else — the caller
     *         cannot tell which, so this cannot be used to probe for other users' message ids
     */
    @Transactional
    public boolean markRead(UUID id, String userId) {
        return messages.findByIdAndUserId(id, userId)
                .map(message -> {
                    message.markRead();
                    return true;
                })
                .orElse(false);
    }

    @Transactional
    public int markAllRead(String userId) {
        return messages.markAllRead(userId);
    }

    private void pushAfterCommit(InAppMessage message) {
        if (!TransactionSynchronizationManager.isSynchronizationActive()) {
            push(message);
            return;
        }
        TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
            @Override
            public void afterCommit() {
                push(message);
            }
        });
    }

    private void push(InAppMessage message) {
        try {
            websocket.convertAndSendToUser(message.getUserId(), USER_DESTINATION, Map.of(
                    "id", message.getId().toString(),
                    "notificationId", message.getNotificationId().toString(),
                    "orderId", message.getOrderId() == null ? "" : message.getOrderId().toString(),
                    "eventType", message.getEventType(),
                    "title", message.getTitle(),
                    "body", message.getBody(),
                    "metadata", message.getMetadata(),
                    "createdAt", message.getCreatedAt().toString()));

        } catch (Exception e) {
            // The row is committed, so the client will see it on its next poll or reconnect. A
            // failed push is a latency problem, not a lost notification - which is exactly why the
            // order is persist-then-push.
            log.warn("Could not push in-app message {} over WebSocket", message.getId(), e);
        }
    }
}
