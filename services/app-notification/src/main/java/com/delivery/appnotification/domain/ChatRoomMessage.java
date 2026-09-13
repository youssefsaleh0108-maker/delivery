package com.delivery.appnotification.domain;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * Something one neighbour said in a room.
 *
 * <p>Carries the sender's per-room handle and display name as they were when the message was sent.
 * The sender's Keycloak sub is stored too, because rate limits, blocks and moderation have to act on
 * the person, but it never leaves this service — see {@code NeighbourhoodChatController.MessageView}.
 */
@Entity
@Table(name = "chat_room_messages")
public class ChatRoomMessage {

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "room_id", nullable = false, updatable = false)
    private UUID roomId;

    @Column(name = "sequence_no", nullable = false, updatable = false)
    private long sequenceNo;

    @Column(name = "sender_id", nullable = false, updatable = false, length = 64)
    private String senderId;

    @Column(name = "sender_handle", nullable = false, updatable = false)
    private UUID senderHandle;

    @Column(name = "sender_name", updatable = false, length = 80)
    private String senderName;

    @Column(name = "body", nullable = false, updatable = false)
    private String body;

    @Column(name = "client_message_id", updatable = false, length = 64)
    private String clientMessageId;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    @Column(name = "hidden_at")
    private Instant hiddenAt;

    @Column(name = "hidden_by", length = 64)
    private String hiddenBy;

    protected ChatRoomMessage() {
        // for JPA
    }

    /**
     * Removes the message from every neighbour's view, keeping the row.
     *
     * <p>A tombstone rather than a delete: the words stay for the audit trail and for an appeal, and
     * the thread keeps its numbering, so a client holding sequence 41 does not find a hole.
     *
     * @return whether this call hid it — false if a moderator already had
     */
    public boolean hide(String actorId, Instant at) {
        if (hiddenAt != null) {
            return false;
        }
        hiddenAt = at;
        hiddenBy = actorId;
        return true;
    }

    public boolean isHidden() {
        return hiddenAt != null;
    }

    public Instant getHiddenAt() {
        return hiddenAt;
    }

    public String getHiddenBy() {
        return hiddenBy;
    }

    public ChatRoomMessage(UUID roomId, long sequenceNo, ChatRoomMember sender, String body,
                           String clientMessageId, Instant createdAt) {
        this.id = UUID.randomUUID();
        this.roomId = roomId;
        this.sequenceNo = sequenceNo;
        this.senderId = sender.getUserId();
        this.senderHandle = sender.getHandle();
        this.senderName = sender.getDisplayName();
        this.body = body;
        this.clientMessageId = clientMessageId;
        this.createdAt = createdAt;
    }

    public UUID getId() {
        return id;
    }

    public UUID getRoomId() {
        return roomId;
    }

    public long getSequenceNo() {
        return sequenceNo;
    }

    public String getSenderId() {
        return senderId;
    }

    public UUID getSenderHandle() {
        return senderHandle;
    }

    public String getSenderName() {
        return senderName;
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
}
