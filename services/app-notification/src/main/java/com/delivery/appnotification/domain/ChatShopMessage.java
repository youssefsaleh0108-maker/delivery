package com.delivery.appnotification.domain;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/** Something said in a shop thread, by the customer or by the shop. */
@Entity
@Table(name = "chat_shop_messages")
public class ChatShopMessage {

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "thread_id", nullable = false, updatable = false)
    private UUID threadId;

    @Column(name = "sequence_no", nullable = false, updatable = false)
    private long sequenceNo;

    @Column(name = "sender_id", nullable = false, updatable = false, length = 64)
    private String senderId;

    @Enumerated(EnumType.STRING)
    @Column(name = "sender_side", nullable = false, updatable = false, length = 16)
    private ShopThreadSide senderSide;

    @Column(name = "body", nullable = false, updatable = false)
    private String body;

    /** Reserved for a verified order or booking reference; never written from a client. */
    @Column(name = "order_id", updatable = false)
    private UUID orderId;

    @Column(name = "client_message_id", updatable = false, length = 64)
    private String clientMessageId;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    @Column(name = "read_at")
    private Instant readAt;

    protected ChatShopMessage() {
        // for JPA
    }

    public ChatShopMessage(UUID threadId, long sequenceNo, String senderId, ShopThreadSide senderSide,
                           String body, String clientMessageId, Instant createdAt) {
        this.id = UUID.randomUUID();
        this.threadId = threadId;
        this.sequenceNo = sequenceNo;
        this.senderId = senderId;
        this.senderSide = senderSide;
        this.body = body;
        this.clientMessageId = clientMessageId;
        this.createdAt = createdAt;
    }

    public UUID getId() {
        return id;
    }

    public UUID getThreadId() {
        return threadId;
    }

    public long getSequenceNo() {
        return sequenceNo;
    }

    public String getSenderId() {
        return senderId;
    }

    public ShopThreadSide getSenderSide() {
        return senderSide;
    }

    public String getBody() {
        return body;
    }

    public UUID getOrderId() {
        return orderId;
    }

    public String getClientMessageId() {
        return clientMessageId;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public Instant getReadAt() {
        return readAt;
    }
}
