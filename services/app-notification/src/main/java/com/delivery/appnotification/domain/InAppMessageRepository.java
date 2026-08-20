package com.delivery.appnotification.domain;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface InAppMessageRepository extends JpaRepository<InAppMessage, UUID> {

    List<InAppMessage> findByUserIdOrderByCreatedAtDesc(String userId, Pageable pageable);

    List<InAppMessage> findByUserIdAndReadAtIsNullOrderByCreatedAtDesc(String userId);

    long countByUserIdAndReadAtIsNull(String userId);

    /**
     * Dedupe check for redelivered commands.
     *
     * <p>The unique constraint would catch it too, but relying on the constraint means an exception
     * on a perfectly normal at-least-once redelivery, and an exception in a listener is a
     * redelivery loop waiting to happen.
     */
    boolean existsByNotificationId(UUID notificationId);

    Optional<InAppMessage> findByIdAndUserId(UUID id, String userId);

    /**
     * Marks everything unread as read in one statement.
     *
     * <p>Loading the entities to call {@code markRead()} on each would be N+1 selects and N updates
     * for a user who has ignored their inbox for a week.
     */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("update InAppMessage m set m.readAt = CURRENT_TIMESTAMP "
            + "where m.userId = :userId and m.readAt is null")
    int markAllRead(@Param("userId") String userId);
}
