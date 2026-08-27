package com.delivery.appnotification.domain;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * A record that support read somebody's conversation.
 *
 * <p>Written before the transcript is returned, not after, and in the same transaction. If the row
 * cannot be written the read does not happen — an unaudited read of a private conversation is
 * exactly the thing this table exists to make impossible, so failing the request is the correct
 * outcome rather than serving it and logging a warning.
 *
 * <p>Holds no message text and no participant identity. It answers "who looked, at which
 * conversation, when, and why", which is what an access review asks; copying the conversation into
 * the audit trail would double the number of places the private text lives.
 */
@Entity
@Table(name = "chat_transcript_access")
public class TranscriptAccess {

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "conversation_id", nullable = false, updatable = false)
    private UUID conversationId;

    @Column(name = "actor_id", nullable = false, updatable = false, length = 64)
    private String actorId;

    @Column(name = "reason", nullable = false, updatable = false, length = 200)
    private String reason;

    @Column(name = "correlation_id", updatable = false, length = 64)
    private String correlationId;

    @Column(name = "accessed_at", nullable = false, updatable = false)
    private Instant accessedAt;

    protected TranscriptAccess() {
        // for JPA
    }

    public TranscriptAccess(UUID conversationId, String actorId, String reason,
                            String correlationId) {
        this.id = UUID.randomUUID();
        this.conversationId = conversationId;
        this.actorId = actorId;
        this.reason = reason;
        this.correlationId = correlationId;
        this.accessedAt = Instant.now();
    }

    public UUID getId() {
        return id;
    }

    public UUID getConversationId() {
        return conversationId;
    }

    public String getActorId() {
        return actorId;
    }

    public String getReason() {
        return reason;
    }

    public String getCorrelationId() {
        return correlationId;
    }

    public Instant getAccessedAt() {
        return accessedAt;
    }
}
