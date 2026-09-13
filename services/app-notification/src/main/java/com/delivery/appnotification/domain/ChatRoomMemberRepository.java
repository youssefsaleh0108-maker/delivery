package com.delivery.appnotification.domain;

import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface ChatRoomMemberRepository extends JpaRepository<ChatRoomMember, UUID> {

    /** The room this person is in now, if any. The partial unique index makes it at most one. */
    Optional<ChatRoomMember> findByUserIdAndLeftAtIsNull(String userId);

    /** Current or former — a returning neighbour gets their old row, mute and handle back. */
    Optional<ChatRoomMember> findByRoomIdAndUserId(UUID roomId, String userId);

    /** The membership check behind every read, post, report and subscribe. */
    Optional<ChatRoomMember> findByRoomIdAndUserIdAndLeftAtIsNull(UUID roomId, String userId);

    boolean existsByRoomIdAndUserIdAndLeftAtIsNull(UUID roomId, String userId);

    long countByRoomIdAndLeftAtIsNull(UUID roomId);

    /**
     * Which of these connected people are still in the room.
     *
     * <p>Asked at delivery time rather than trusted from the subscription, because a subscription
     * outlives the membership it was checked against: somebody who moved neighbourhood an hour ago
     * may still hold a socket subscribed to the old room.
     */
    @Query("select m.userId from ChatRoomMember m "
            + "where m.roomId = :roomId and m.leftAt is null and m.userId in :userIds")
    List<String> currentAmong(@Param("roomId") UUID roomId,
                              @Param("userIds") Collection<String> userIds);
}
