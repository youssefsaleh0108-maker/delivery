package com.delivery.appnotification.domain;

import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface ChatRoomMessageRepository extends JpaRepository<ChatRoomMessage, UUID> {

    /** A retry of something this sender already said here. Keyed per sender; see V22. */
    Optional<ChatRoomMessage> findByRoomIdAndSenderIdAndClientMessageId(
            UUID roomId, String senderId, String clientMessageId);

    /**
     * Newest first, strictly before a sequence: the first screen ({@code Long.MAX_VALUE}) and every
     * "load older" after it. The caller reverses the page so the thread reads top to bottom.
     *
     * <p>Authors the viewer blocked are excluded <em>by the query</em>, not filtered afterwards: a
     * page is then always full, and the block holds however a client renders what it is given.
     */
    @Query("select m from ChatRoomMessage m where m.roomId = :roomId "
            + "and m.sequenceNo < :beforeSequence "
            + "and m.senderId not in (select b.blockedId from ChatBlock b where b.blockerId = :viewerId) "
            + "order by m.sequenceNo desc")
    List<ChatRoomMessage> newestBefore(@Param("roomId") UUID roomId,
                                       @Param("beforeSequence") long beforeSequence,
                                       @Param("viewerId") String viewerId,
                                       Pageable pageable);

    /** Oldest first, strictly after a sequence: what a reconnecting client missed. Blocks as above. */
    @Query("select m from ChatRoomMessage m where m.roomId = :roomId "
            + "and m.sequenceNo > :afterSequence "
            + "and m.senderId not in (select b.blockedId from ChatBlock b where b.blockerId = :viewerId) "
            + "order by m.sequenceNo asc")
    List<ChatRoomMessage> oldestAfter(@Param("roomId") UUID roomId,
                                      @Param("afterSequence") long afterSequence,
                                      @Param("viewerId") String viewerId,
                                      Pageable pageable);

    /** The send rate limit: how much this person has said, anywhere, since an instant. */
    long countBySenderIdAndCreatedAtAfter(String senderId, Instant since);
}
