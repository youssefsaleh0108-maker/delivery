package com.delivery.appnotification.domain;

import java.time.Instant;
import java.util.Optional;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import jakarta.persistence.Version;

/**
 * One order's chat: exactly two people, opened when a rider is assigned, closed some time after the
 * order reaches its end.
 *
 * <p><strong>Membership is the whole security model.</strong> Everything else in this feature —
 * reading the thread, posting to it, counting what is unread, receiving a live frame — resolves to
 * {@link #isParticipant(String)} against these two columns. There is no membership table to get out
 * of step with the order, and no "add participant" operation for a bug to reach.
 *
 * <p>The merchant is deliberately not in it. The design puts a chat button on the delivery, not on
 * the shop, and a merchant who could read the customer's conversation with the rider would be
 * reading a conversation about their own late order without either party knowing.
 */
@Entity
@Table(name = "chat_conversations")
public class ChatConversation {

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "order_id", nullable = false, updatable = false)
    private UUID orderId;

    @Column(name = "customer_id", nullable = false, updatable = false, length = 64)
    private String customerId;

    @Column(name = "rider_id", nullable = false, updatable = false, length = 64)
    private String riderId;

    @Column(name = "opened_at", nullable = false, updatable = false)
    private Instant openedAt;

    @Column(name = "closes_at")
    private Instant closesAt;

    @Column(name = "next_sequence", nullable = false)
    private long nextSequence;

    @Column(name = "last_message_at")
    private Instant lastMessageAt;

    /**
     * Optimistic locking on the sequence counter.
     *
     * <p>Belt to the pessimistic row lock's braces. The lock is what makes concurrent posts
     * serialise; this is what turns a future caller who forgets to take the lock into a failed
     * transaction rather than two messages quietly sharing sequence 7.
     */
    @Version
    @Column(name = "version", nullable = false)
    private long version;

    protected ChatConversation() {
        // for JPA
    }

    public ChatConversation(UUID orderId, String customerId, String riderId) {
        this.id = UUID.randomUUID();
        this.orderId = orderId;
        this.customerId = customerId;
        this.riderId = riderId;
        this.openedAt = Instant.now();
        this.nextSequence = 1L;
    }

    public boolean isParticipant(String userId) {
        return customerId.equals(userId) || riderId.equals(userId);
    }

    public Optional<ChatParticipantRole> roleOf(String userId) {
        if (customerId.equals(userId)) {
            return Optional.of(ChatParticipantRole.CUSTOMER);
        }
        if (riderId.equals(userId)) {
            return Optional.of(ChatParticipantRole.RIDER);
        }
        return Optional.empty();
    }

    /** The other participant — who a message from {@code userId} has to reach. */
    public Optional<String> counterpartOf(String userId) {
        if (customerId.equals(userId)) {
            return Optional.of(riderId);
        }
        if (riderId.equals(userId)) {
            return Optional.of(customerId);
        }
        return Optional.empty();
    }

    /**
     * Open means "still accepting posts". Reading a closed conversation is still allowed — the
     * transcript does not disappear, it only stops growing.
     */
    public boolean isOpenAt(Instant now) {
        return closesAt == null || now.isBefore(closesAt);
    }

    /**
     * Sets when this conversation stops accepting posts.
     *
     * <p><strong>First terminal event wins.</strong> Bus delivery is at-least-once, so {@code
     * order.delivered} can arrive three times; if each one re-armed the window, a redelivery an hour
     * later would silently extend a conversation that should already have closed. Re-closing an
     * already-closed conversation is therefore a no-op rather than an error — the caller is a
     * listener that must not throw on a normal redelivery.
     */
    public void closeAt(Instant when) {
        if (closesAt == null) {
            closesAt = when;
        }
    }

    /**
     * Hands out the next message number and records that the thread moved.
     *
     * <p>Only safe under the row lock the repository takes; see
     * {@code ChatConversationRepository.lockById}.
     */
    public long claimSequence(Instant at) {
        long claimed = nextSequence;
        nextSequence = claimed + 1;
        lastMessageAt = at;
        return claimed;
    }

    public UUID getId() {
        return id;
    }

    public UUID getOrderId() {
        return orderId;
    }

    public String getCustomerId() {
        return customerId;
    }

    public String getRiderId() {
        return riderId;
    }

    public Instant getOpenedAt() {
        return openedAt;
    }

    public Instant getClosesAt() {
        return closesAt;
    }

    public long getNextSequence() {
        return nextSequence;
    }

    public Instant getLastMessageAt() {
        return lastMessageAt;
    }
}
