package com.delivery.platform.outbox;

import java.util.List;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface OutboxEventRepository extends JpaRepository<OutboxEvent, UUID> {

    /**
     * Claims a batch of pending events for this relay instance.
     *
     * <p>{@code FOR UPDATE SKIP LOCKED} is what makes the relay safe to run on every replica of a
     * service: two instances polling at the same time take disjoint batches instead of both
     * publishing the same event. Ordering by {@code created_at} keeps per-aggregate ordering
     * intact in practice, since a single aggregate's events are written sequentially.
     *
     * <p>The {@code next_attempt_at} predicate is what makes the retry backoff real. Without it a
     * row that failed was re-claimed on the very next tick, and a broker outage longer than
     * {@code pollInterval * maxAttempts} dead-lettered the entire backlog rather than waiting.
     * A row that is not yet due is left in place for a later tick, not skipped permanently.
     */
    @Query(value = """
            SELECT * FROM outbox_event
            WHERE status = 'PENDING'
              AND next_attempt_at <= now()
            ORDER BY created_at
            LIMIT :batchSize
            FOR UPDATE SKIP LOCKED
            """, nativeQuery = true)
    List<OutboxEvent> claimPendingBatch(@Param("batchSize") int batchSize);

    long countByStatus(OutboxEvent.Status status);
}
