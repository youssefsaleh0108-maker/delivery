package com.delivery.appnotification.domain;

import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface ChatBlockRepository extends JpaRepository<ChatBlock, UUID> {

    /** Blocks unless already blocked; an upsert so a double tap is one block. */
    @Modifying(flushAutomatically = true)
    @Query(value = "insert into chat_blocks (id, blocker_id, blocked_id, blocked_name, created_at) "
            + "values (:id, :blockerId, :blockedId, :blockedName, now()) "
            + "on conflict (blocker_id, blocked_id) do nothing",
            nativeQuery = true)
    int insertIfAbsent(@Param("id") UUID id,
                       @Param("blockerId") String blockerId,
                       @Param("blockedId") String blockedId,
                       @Param("blockedName") String blockedName);

    Optional<ChatBlock> findByBlockerIdAndBlockedId(String blockerId, String blockedId);

    List<ChatBlock> findByBlockerIdOrderByCreatedAtDesc(String blockerId);

    /** A block the caller made, and only that: somebody else's block id answers as not found. */
    Optional<ChatBlock> findByIdAndBlockerId(UUID id, String blockerId);

    /** Which of these listeners blocked this author, so live delivery can leave them out. */
    @Query("select b.blockerId from ChatBlock b "
            + "where b.blockedId = :authorId and b.blockerId in :listeners")
    List<String> blockersAmong(@Param("authorId") String authorId,
                               @Param("listeners") Collection<String> listeners);
}
