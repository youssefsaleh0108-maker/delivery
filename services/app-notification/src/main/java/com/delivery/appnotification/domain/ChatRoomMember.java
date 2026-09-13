package com.delivery.appnotification.domain;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * One person's place in one neighbourhood room.
 *
 * <p><strong>This row is the room's whole security model.</strong> Reading the history, posting,
 * reporting and subscribing to the live feed all resolve to "is there a current row for this room
 * and this caller" — and the only thing that writes a current row is {@code NeighbourhoodRoomService}
 * placing a caller in the room of their own delivery zone. There is no "join room X" operation.
 *
 * <p>Kept, not deleted, when the person moves to another neighbourhood. Deleting it would let a
 * muted neighbour shed the mute by moving away and back, and would hand them a new handle that their
 * neighbours' blocks no longer recognise.
 */
@Entity
@Table(name = "chat_room_members")
public class ChatRoomMember {

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "room_id", nullable = false, updatable = false)
    private UUID roomId;

    @Column(name = "user_id", nullable = false, updatable = false, length = 64)
    private String userId;

    @Column(name = "handle", nullable = false, updatable = false)
    private UUID handle;

    @Column(name = "display_name", length = 80)
    private String displayName;

    @Column(name = "joined_at", nullable = false)
    private Instant joinedAt;

    @Column(name = "left_at")
    private Instant leftAt;

    @Column(name = "muted_until")
    private Instant mutedUntil;

    protected ChatRoomMember() {
        // for JPA
    }

    public ChatRoomMember(UUID roomId, String userId, String displayName, Instant joinedAt) {
        this.id = UUID.randomUUID();
        this.roomId = roomId;
        this.userId = userId;
        this.handle = UUID.randomUUID();
        this.displayName = displayName;
        this.joinedAt = joinedAt;
    }

    public boolean isCurrent() {
        return leftAt == null;
    }

    public boolean isMutedAt(Instant now) {
        return mutedUntil != null && now.isBefore(mutedUntil);
    }

    /** Moving away. A no-op if already gone, so a retried move cannot re-date it. */
    public void leave(Instant at) {
        if (leftAt == null) {
            leftAt = at;
        }
    }

    /**
     * Coming back, or simply visiting again.
     *
     * <p>The join time restarts only on a genuine return: it is what the move cooldown counts from,
     * and a visit to the room you are already in must not reset the clock on your next move.
     */
    public void arrive(Instant at, String currentName) {
        if (leftAt != null) {
            leftAt = null;
            joinedAt = at;
        }
        this.displayName = currentName;
    }

    public void muteUntil(Instant until) {
        this.mutedUntil = until;
    }

    public void unmute() {
        this.mutedUntil = null;
    }

    public UUID getId() {
        return id;
    }

    public UUID getRoomId() {
        return roomId;
    }

    public String getUserId() {
        return userId;
    }

    public UUID getHandle() {
        return handle;
    }

    public String getDisplayName() {
        return displayName;
    }

    public Instant getJoinedAt() {
        return joinedAt;
    }

    public Instant getLeftAt() {
        return leftAt;
    }

    public Instant getMutedUntil() {
        return mutedUntil;
    }
}
