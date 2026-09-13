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
     */
    @Query("select m from ChatRoomMessage m where m.roomId = :roomId "
            + "and m.sequenceNo < :beforeSequence order by m.sequenceNo desc")
    List<ChatRoomMessage> newestBefore(@Param("roomId") UUID roomId,
                                       @Param("beforeSequence") long beforeSequence,
                                       Pageable pageable);

    /** Oldest first, strictly after a sequence: what a reconnecting client missed. */
    @Query("select m from ChatRoomMessage m where m.roomId = :roomId "
            + "and m.sequenceNo > :afterSequence order by m.sequenceNo asc")
    List<ChatRoomMessage> oldestAfter(@Param("roomId") UUID roomId,
                                      @Param("afterSequence") long afterSequence,
                                      Pageable pageable);

    /** The send rate limit: how much this person has said, anywhere, since an instant. */
    long countBySenderIdAndCreatedAtAfter(String senderId, Instant since);
}
