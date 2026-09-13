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

public interface ChatShopMessageRepository extends JpaRepository<ChatShopMessage, UUID> {

    /** First open ({@code 0}) and reconnect alike, as in order chat. */
    List<ChatShopMessage> findByThreadIdAndSequenceNoGreaterThanOrderBySequenceNoAsc(
            UUID threadId, long afterSequence, Pageable pageable);

    /** Keyed per sender: the shop and the customer can generate the same client id. */
    Optional<ChatShopMessage> findByThreadIdAndSenderIdAndClientMessageId(
            UUID threadId, String senderId, String clientMessageId);

    /** The send rate limit. */
    long countBySenderIdAndCreatedAtAfter(String senderId, Instant since);

    /** Unread badges: what one side said that the other has not read, per thread, in one query. */
    @Query("select m.threadId as threadId, count(m) as unread from ChatShopMessage m "
            + "where m.threadId in :threadIds and m.senderSide = :fromSide and m.readAt is null "
            + "group by m.threadId")
    List<UnreadTally> unreadFrom(@Param("threadIds") Collection<UUID> threadIds,
                                 @Param("fromSide") ShopThreadSide fromSide);

    /** The last line of each thread, for the inbox preview. */
    @Query("select m from ChatShopMessage m where m.threadId in :threadIds and m.sequenceNo = "
            + "(select max(x.sequenceNo) from ChatShopMessage x where x.threadId = m.threadId)")
    List<ChatShopMessage> latestIn(@Param("threadIds") Collection<UUID> threadIds);

    /** "I have read what the other side said, up to here." Idempotent, as order chat's is. */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("update ChatShopMessage m set m.readAt = :now "
            + "where m.threadId = :threadId and m.senderSide = :fromSide "
            + "and m.sequenceNo <= :upToSequence and m.readAt is null")
    int markReadUpTo(@Param("threadId") UUID threadId,
                     @Param("fromSide") ShopThreadSide fromSide,
                     @Param("upToSequence") long upToSequence,
                     @Param("now") Instant now);

    interface UnreadTally {
        UUID getThreadId();

        long getUnread();
    }
}
