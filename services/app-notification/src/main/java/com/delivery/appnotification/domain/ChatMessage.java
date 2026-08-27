package com.delivery.appnotification.domain;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * One thing somebody said in an order chat.
 *
 * <p>The conversation is referenced by id rather than by a {@code @ManyToOne}. A message is never
 * loaded without already knowing which conversation was asked for — the authorisation check happens
 * on the conversation first, always — so an association would buy a lazy proxy and a second query
 * on a path that has the parent in hand.
 *
 * <p>{@link #body} is untrusted text and is treated as such everywhere: it is bound as a parameter,
 * never appears in a log line, and is only ever emitted as a JSON string value. Nothing in this
 * service formats it into anything.
 */
@Entity
@Table(name = "chat_messages")
public class ChatMessage {

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "conversation_id", nullable = false, updatable = false)
    private UUID conversationId;

    @Column(name = "sequence_no", nullable = false, updatable = false)
    private long sequenceNo;

    @Column(name = "sender_id", nullable = false, updatable = false, length = 64)
    private String senderId;

    @Enumerated(EnumType.STRING)
    @Column(name = "sender_role", nullable = false, updatable = false, length = 16)
    private ChatParticipantRole senderRole;

    @Column(name = "body", nullable = false, updatable = false, columnDefinition = "text")
    private String body;

    @Column(name = "client_message_id", updatable = false, length = 64)
    private String clientMessageId;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    @Column(name = "delivered_at")
    private Instant deliveredAt;

    @Column(name = "read_at")
    private Instant readAt;

    protected ChatMessage() {
        // for JPA
    }

    public ChatMessage(UUID conversationId, long sequenceNo, String senderId,
                       ChatParticipantRole senderRole, String body, String clientMessageId,
                       Instant createdAt) {
        this.id = UUID.randomUUID();
        this.conversationId = conversationId;
        this.sequenceNo = sequenceNo;
        this.senderId = senderId;
        this.senderRole = senderRole;
        this.body = body;
        this.clientMessageId = clientMessageId;
        this.createdAt = createdAt;
    }

    /**
     * Idempotent, like {@code InAppMessage.markRead()} and for the same reason: the recipient can
     * reach a message twice — once on a live frame, once when their app refetches the thread on
     * resume — and "when did it get to them" must keep meaning the first time.
     */
    public void markDelivered(Instant when) {
        if (deliveredAt == null) {
            deliveredAt = when;
        }
    }

    /** A read implies a delivery, even if the frame that should have recorded one never landed. */
    public void markRead(Instant when) {
        markDelivered(when);
        if (readAt == null) {
            readAt = when;
        }
    }

    public UUID getId() {
        return id;
    }

    public UUID getConversationId() {
        return conversationId;
    }

    public long getSequenceNo() {
        return sequenceNo;
    }

    public String getSenderId() {
        return senderId;
    }

    public ChatParticipantRole getSenderRole() {
        return senderRole;
    }

    public String getBody() {
        return body;
    }

    public String getClientMessageId() {
        return clientMessageId;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public Instant getDeliveredAt() {
        return deliveredAt;
    }

    public Instant getReadAt() {
        return readAt;
    }
}
