package com.delivery.notifications.domain;

import java.util.List;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

public interface NotificationTemplateRepository extends JpaRepository<NotificationTemplate, UUID> {

    /**
     * Every channel configured for this event.
     *
     * <p>Which channels fire is a data question, not a code one: adding an SMS for a status change
     * means inserting a template row, not editing the manager.
     */
    List<NotificationTemplate> findByEventTypeAndLocale(String eventType, String locale);
}
