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

public interface ChatRoomReportRepository extends JpaRepository<ChatRoomReport, UUID> {

    /**
     * Files a report unless this person already reported this message.
     *
     * <p>An upsert rather than find-then-save for the reason {@code ChatRoomRepository.insertIfAbsent}
     * gives: a double tap would otherwise race to the unique constraint and poison the transaction.
     */
    @Modifying(flushAutomatically = true)
    @Query(value = "insert into chat_room_reports (id, message_id, room_id, reporter_id, reason, created_at) "
            + "values (:id, :messageId, :roomId, :reporterId, :reason, now()) "
            + "on conflict (message_id, reporter_id) do nothing",
            nativeQuery = true)
    int insertIfAbsent(@Param("id") UUID id,
                       @Param("messageId") UUID messageId,
                       @Param("roomId") UUID roomId,
                       @Param("reporterId") String reporterId,
                       @Param("reason") String reason);

    Optional<ChatRoomReport> findByMessageIdAndReporterId(UUID messageId, String reporterId);

    List<ChatRoomReport> findByMessageIdAndResolvedAtIsNull(UUID messageId);

    List<ChatRoomReport> findByMessageIdInAndResolvedAtIsNull(Collection<UUID> messageIds);

    /**
     * The queue: one line per reported message still waiting, oldest wait first.
     *
     * <p>Oldest first rather than most-reported first. Ordering by count lets a brigade of reports on
     * one harmless message push a genuinely harmful one down the queue indefinitely; a queue worked in
     * arrival order has a wait anyone can reason about.
     */
    @Query("select r.messageId as messageId, count(r) as reports, "
            + "min(r.createdAt) as firstReportedAt, max(r.createdAt) as lastReportedAt "
            + "from ChatRoomReport r where r.resolvedAt is null "
            + "group by r.messageId order by min(r.createdAt) asc")
    List<OpenTally> openTallies(Pageable pageable);

    interface OpenTally {
        UUID getMessageId();

        long getReports();

        Instant getFirstReportedAt();

        Instant getLastReportedAt();
    }
}
