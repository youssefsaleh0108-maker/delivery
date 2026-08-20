package com.delivery.whatsapp.domain;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * One thing that was said, in either direction.
 *
 * <p>Kept verbatim. The merchant is reading this to decide what to put in an order, and a cleaned-up
 * or summarised version would lose exactly the detail that matters — "no onions", "the small one",
 * "same as last time".
 */
@Entity
@Table(name = "wa_messages")
public class WhatsAppMessage {

    public enum Direction { INBOUND, OUTBOUND }

    /**
     * What kind of message arrived.
     *
     * <p>Only TEXT carries a body today. The others are recorded so the thread is honest: a merchant
     * who sees nothing where the customer sent a voice note would conclude the platform lost it, and
     * chase the wrong problem.
     */
    public enum Kind { TEXT, IMAGE, AUDIO, DOCUMENT, LOCATION, OTHER }

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "conversation_id", nullable = false, updatable = false)
    private UUID conversationId;

    @Enumerated(EnumType.STRING)
    @Column(name = "direction", nullable = false, updatable = false, length = 8)
    private Direction direction;

    @Column(name = "body", columnDefinition = "text")
    private String body;

    @Enumerated(EnumType.STRING)
    @Column(name = "message_type", nullable = false, length = 24)
    private Kind messageType = Kind.TEXT;

    /** The provider's own id. What makes a redelivered webhook harmless. */
    @Column(name = "provider_message_id", length = 128)
    private String providerMessageId;

    @Column(name = "sent_at", nullable = false)
    private Instant sentAt;

    @Column(name = "created_at", nullable = false, insertable = false, updatable = false)
    private Instant createdAt;

    protected WhatsAppMessage() {
        // for JPA
    }

    private WhatsAppMessage(UUID conversationId, Direction direction, String body, Kind kind,
                            String providerMessageId, Instant sentAt) {
        this.id = UUID.randomUUID();
        this.conversationId = conversationId;
        this.direction = direction;
        this.body = body;
        this.messageType = kind;
        this.providerMessageId = providerMessageId;
        this.sentAt = sentAt;
    }

    public static WhatsAppMessage inbound(UUID conversationId, String body, Kind kind,
                                          String providerMessageId, Instant sentAt) {
        return new WhatsAppMessage(conversationId, Direction.INBOUND, body, kind,
                providerMessageId, sentAt);
    }

    public static WhatsAppMessage outbound(UUID conversationId, String body) {
        return new WhatsAppMessage(conversationId, Direction.OUTBOUND, body, Kind.TEXT,
                null, Instant.now());
    }

    /** Records the provider's id once a send has been accepted. */
    public void acceptedAs(String providerMessageId) {
        this.providerMessageId = providerMessageId;
    }

    /** Whether this message carries anything a merchant can read. */
    public boolean hasText() {
        return body != null && !body.isBlank();
    }

    public UUID getId() {
        return id;
    }

    public UUID getConversationId() {
        return conversationId;
    }

    public Direction getDirection() {
        return direction;
    }

    public String getBody() {
        return body;
    }

    public Kind getMessageType() {
        return messageType;
    }

    public String getProviderMessageId() {
        return providerMessageId;
    }

    public Instant getSentAt() {
        return sentAt;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }
}
