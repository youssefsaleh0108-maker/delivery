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
 * The audit trail of what a moderator did in a room, and why.
 *
 * <p>Written in the same transaction as the action, like {@link TranscriptAccess}: an action whose
 * record cannot be written does not happen. Immutable once written — an audit row that can be edited
 * is a note, not a trail.
 */
@Entity
@Table(name = "chat_moderation_actions")
public class ChatModerationAction {

    public enum Type {
        HIDE_MESSAGE,
        DISMISS_REPORTS,
        MUTE_MEMBER,
        UNMUTE_MEMBER
    }

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "actor_id", nullable = false, updatable = false, length = 64)
    private String actorId;

    @Enumerated(EnumType.STRING)
    @Column(name = "action", nullable = false, updatable = false, length = 24)
    private Type action;

    @Column(name = "room_id", nullable = false, updatable = false)
    private UUID roomId;

    @Column(name = "message_id", updatable = false)
    private UUID messageId;

    @Column(name = "target_user_id", updatable = false, length = 64)
    private String targetUserId;

    @Column(name = "muted_until", updatable = false)
    private Instant mutedUntil;

    @Column(name = "reason", nullable = false, updatable = false, length = 200)
    private String reason;

    @Column(name = "correlation_id", updatable = false, length = 64)
    private String correlationId;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    protected ChatModerationAction() {
        // for JPA
    }

    /**
     * @param message      the message the moderator acted through — every action is reached from a
     *                     reported message, which is also how staff avoid ever handling account ids
     * @param targetUserId whose membership changed, for mutes; null for actions on the message alone
     */
    public ChatModerationAction(String actorId, Type action, ChatRoomMessage message,
                                String targetUserId, Instant mutedUntil, String reason,
                                String correlationId) {
        this.id = UUID.randomUUID();
        this.actorId = actorId;
        this.action = action;
        this.roomId = message.getRoomId();
        this.messageId = message.getId();
        this.targetUserId = targetUserId;
        this.mutedUntil = mutedUntil;
        this.reason = reason;
        this.correlationId = correlationId;
        this.createdAt = Instant.now();
    }

    public UUID getId() {
        return id;
    }

    public String getActorId() {
        return actorId;
    }

    public Type getAction() {
        return action;
    }

    public UUID getRoomId() {
        return roomId;
    }

    public UUID getMessageId() {
        return messageId;
    }

    public String getTargetUserId() {
        return targetUserId;
    }

    public Instant getMutedUntil() {
        return mutedUntil;
    }

    public String getReason() {
        return reason;
    }

    public String getCorrelationId() {
        return correlationId;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }
}
