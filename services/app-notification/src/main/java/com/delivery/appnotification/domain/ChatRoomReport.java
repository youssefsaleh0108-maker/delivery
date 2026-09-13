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
 * A neighbour telling a moderator a message should not be in the room.
 *
 * <p>Created through {@code ChatRoomReportRepository.insertIfAbsent} so a double tap is one report;
 * the entity is only read and resolved.
 */
@Entity
@Table(name = "chat_room_reports")
public class ChatRoomReport {

    /** What the app offers, kept short on purpose: a report is a flag, not a form. */
    public enum Reason {
        SPAM,
        ABUSE,
        /** Somebody's phone number, address or other private details posted to the room. */
        PERSONAL_INFO,
        OTHER
    }

    public enum Resolution {
        HIDDEN,
        DISMISSED
    }

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "message_id", nullable = false, updatable = false)
    private UUID messageId;

    @Column(name = "room_id", nullable = false, updatable = false)
    private UUID roomId;

    @Column(name = "reporter_id", nullable = false, updatable = false, length = 64)
    private String reporterId;

    @Enumerated(EnumType.STRING)
    @Column(name = "reason", nullable = false, updatable = false, length = 24)
    private Reason reason;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    @Column(name = "resolved_at")
    private Instant resolvedAt;

    @Column(name = "resolved_by", length = 64)
    private String resolvedBy;

    @Enumerated(EnumType.STRING)
    @Column(name = "resolution", length = 16)
    private Resolution resolution;

    protected ChatRoomReport() {
        // for JPA
    }

    /** For tests and projections; production inserts go through the repository's upsert. */
    public ChatRoomReport(ChatRoomMessage message, String reporterId, Reason reason, Instant at) {
        this.id = UUID.randomUUID();
        this.messageId = message.getId();
        this.roomId = message.getRoomId();
        this.reporterId = reporterId;
        this.reason = reason;
        this.createdAt = at;
    }

    /** First resolution wins, so a second moderator's click cannot re-date or re-label the first's. */
    public void resolve(String actorId, Resolution how, Instant at) {
        if (resolvedAt == null) {
            resolvedAt = at;
            resolvedBy = actorId;
            resolution = how;
        }
    }

    public UUID getId() {
        return id;
    }

    public UUID getMessageId() {
        return messageId;
    }

    public UUID getRoomId() {
        return roomId;
    }

    public String getReporterId() {
        return reporterId;
    }

    public Reason getReason() {
        return reason;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public Instant getResolvedAt() {
        return resolvedAt;
    }

    public String getResolvedBy() {
        return resolvedBy;
    }

    public Resolution getResolution() {
        return resolution;
    }
}
