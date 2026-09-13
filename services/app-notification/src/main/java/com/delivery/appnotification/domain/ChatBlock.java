package com.delivery.appnotification.domain;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * One person choosing not to see another's messages.
 *
 * <p>The blocked person's account id is held here and nowhere the blocker can read it: the blocker
 * blocks through a message, and later sees this row as an opaque id plus the name the person went by.
 * One-directional, as a block in a public room usually is — the blocked person is not told, and still
 * sees the room.
 */
@Entity
@Table(name = "chat_blocks")
public class ChatBlock {

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "blocker_id", nullable = false, updatable = false, length = 64)
    private String blockerId;

    @Column(name = "blocked_id", nullable = false, updatable = false, length = 64)
    private String blockedId;

    @Column(name = "blocked_name", updatable = false, length = 80)
    private String blockedName;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    protected ChatBlock() {
        // for JPA
    }

    /** For tests; production inserts go through the repository's upsert. */
    public ChatBlock(String blockerId, String blockedId, String blockedName, Instant at) {
        this.id = UUID.randomUUID();
        this.blockerId = blockerId;
        this.blockedId = blockedId;
        this.blockedName = blockedName;
        this.createdAt = at;
    }

    public UUID getId() {
        return id;
    }

    public String getBlockerId() {
        return blockerId;
    }

    public String getBlockedId() {
        return blockedId;
    }

    public String getBlockedName() {
        return blockedName;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }
}
