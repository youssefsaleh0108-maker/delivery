package com.delivery.appnotification.domain;

import java.time.Instant;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface ChatMessageRepository extends JpaRepository<ChatMessage, UUID> {

    /**
     * The thread, from a cursor.
     *
     * <p>One query serves both the first open ({@code afterSequence = 0}) and the reconnect
     * ({@code afterSequence =} the last number the client holds). Making reconnect a special case
     * is how the two paths drift until one of them starts skipping messages.
     */
    List<ChatMessage> findByConversationIdAndSequenceNoGreaterThanOrderBySequenceNoAsc(
            UUID conversationId, long afterSequence, Pageable pageable);

    /** For the idempotent repost: the same client id in the same thread is the same message. */
    Optional<ChatMessage> findByConversationIdAndClientMessageId(
            UUID conversationId, String clientMessageId);

    /**
     * The badge for one conversation: what the other person said and this person has not read.
     *
     * <p>Counted as "not sent by me" rather than "sent by them" so that it cannot be thrown off by
     * a conversation whose participants were somehow recorded wrong — the worst case is counting
     * nothing, not counting your own messages as unread at yourself.
     */
    long countByConversationIdAndSenderIdNotAndReadAtIsNull(UUID conversationId, String senderId);

    /**
     * Every badge at once, for the conversation list.
     *
     * <p>One grouped query rather than a count per row: the list screen shows every conversation a
     * rider has had, and a count each is the N+1 that makes opening the app slow at exactly the
     * moment a rider is standing on a doorstep.
     */
    @Query("select m.conversationId as conversationId, count(m) as unread from ChatMessage m "
            + "where m.conversationId in :conversationIds "
            + "and m.senderId <> :userId and m.readAt is null "
            + "group by m.conversationId")
    List<UnreadTally> countUnreadByConversation(
            @Param("conversationIds") Collection<UUID> conversationIds,
            @Param("userId") String userId);

    /**
     * Marks everything the other person said up to a cursor as read, in one statement.
     *
     * <p>A cursor rather than per-message calls because that is what the client actually knows: it
     * has scrolled to the bottom, so everything up to the last number on screen has been seen.
     * Loading each entity to call {@code markRead()} would be N selects and N updates for a thread
     * somebody left unopened all afternoon.
     *
     * <p>{@code readAt is null} in the predicate keeps it idempotent — a client that fires this on
     * every render must not keep moving the timestamp forward, or "when did they see it" stops
     * being answerable. The same statement sets {@code deliveredAt} for anything that never got a
     * frame, because being read is proof enough that it arrived.
     */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("update ChatMessage m set m.readAt = :now, "
            + "m.deliveredAt = coalesce(m.deliveredAt, :now) "
            + "where m.conversationId = :conversationId "
            + "and m.senderId <> :readerId "
            + "and m.sequenceNo <= :upToSequence "
            + "and m.readAt is null")
    int markReadUpTo(@Param("conversationId") UUID conversationId,
                     @Param("readerId") String readerId,
                     @Param("upToSequence") long upToSequence,
                     @Param("now") Instant now);

    /**
     * Records that messages reached the recipient — used both by the live push and by the refetch a
     * client does when its socket comes back.
     *
     * <p>Scoped to messages the recipient did not send, so a client fetching its own thread cannot
     * mark its own outgoing messages as delivered to itself.
     */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("update ChatMessage m set m.deliveredAt = :now "
            + "where m.id in :ids and m.senderId <> :recipientId and m.deliveredAt is null")
    int markDelivered(@Param("ids") Collection<UUID> ids,
                      @Param("recipientId") String recipientId,
                      @Param("now") Instant now);

    /** Projection for {@link #countUnreadByConversation}. */
    interface UnreadTally {
        UUID getConversationId();

        long getUnread();
    }
}
