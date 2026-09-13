package com.delivery.appnotification.domain;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import jakarta.persistence.Version;

/**
 * A neighbourhood's public room: one per curated delivery zone.
 *
 * <p>Keyed by zone rather than by the merchant's free-text neighbourhood because membership has to
 * be something the server can check. A customer's address names a zone from Product Service's
 * curated list; "Mar Mikhael", "mar mikhayel" and "Mar-Mikhael" typed by three shops would otherwise
 * be three rooms that nobody's address matches.
 *
 * <p>Carries no member list and no content. Who may read or post is {@link ChatRoomMember}'s
 * business, so there is nothing on this row that a bug could widen.
 */
@Entity
@Table(name = "chat_rooms")
public class ChatRoom {

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "zone_id", nullable = false, updatable = false)
    private UUID zoneId;

    @Column(name = "name", nullable = false, length = 120)
    private String name;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    @Column(name = "next_sequence", nullable = false)
    private long nextSequence;

    @Column(name = "last_message_at")
    private Instant lastMessageAt;

    /** Belt to the row lock's braces, for the same reason as {@link ChatConversation}'s. */
    @Version
    @Column(name = "version", nullable = false)
    private long version;

    protected ChatRoom() {
        // for JPA
    }

    public ChatRoom(UUID zoneId, String name) {
        this.id = UUID.randomUUID();
        this.zoneId = zoneId;
        this.name = name;
        this.createdAt = Instant.now();
        this.nextSequence = 1L;
    }

    /**
     * Follows a zone that Backoffice renamed. The room is the zone, so its title should read the way
     * the address picker does today, not the way it did when the first neighbour arrived.
     */
    public void rename(String zoneName) {
        if (zoneName != null && !zoneName.isBlank() && !zoneName.equals(name)) {
            this.name = zoneName;
        }
    }

    /** Only safe under the row lock; see {@code ChatRoomRepository.lockById}. */
    public long claimSequence(Instant at) {
        long claimed = nextSequence;
        nextSequence = claimed + 1;
        lastMessageAt = at;
        return claimed;
    }

    public UUID getId() {
        return id;
    }

    public UUID getZoneId() {
        return zoneId;
    }

    public String getName() {
        return name;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public long getNextSequence() {
        return nextSequence;
    }

    public Instant getLastMessageAt() {
        return lastMessageAt;
    }
}
