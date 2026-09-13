package com.delivery.appnotification.domain;

import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

/** Append-only in practice: nothing in this service updates or deletes an audit row. */
public interface ChatModerationActionRepository extends JpaRepository<ChatModerationAction, UUID> {
}
