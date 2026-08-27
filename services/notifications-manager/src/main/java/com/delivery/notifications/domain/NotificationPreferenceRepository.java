package com.delivery.notifications.domain;

import java.util.List;
import java.util.Optional;

import org.springframework.data.jpa.repository.JpaRepository;

public interface NotificationPreferenceRepository
        extends JpaRepository<NotificationPreference, NotificationPreference.Key> {

    /**
     * Everything one user has changed.
     *
     * <p>The settings screen needs the whole grid, not just the deviations, so the caller merges
     * this over the category defaults. Fetching the user's rows in one query rather than asking per
     * category and channel keeps that merge to a single round trip — sixteen point lookups to paint
     * one screen would be a poor trade for a slightly simpler service method.
     */
    List<NotificationPreference> findByRecipientId(String recipientId);

    Optional<NotificationPreference> findByRecipientIdAndCategoryAndChannel(
            String recipientId, NotificationCategory category, String channel);
}
