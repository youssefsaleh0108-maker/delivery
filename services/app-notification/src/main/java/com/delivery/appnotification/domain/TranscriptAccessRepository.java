package com.delivery.appnotification.domain;

import java.util.List;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

public interface TranscriptAccessRepository extends JpaRepository<TranscriptAccess, UUID> {

    /**
     * Who has read this conversation.
     *
     * <p>Exposed to nobody over HTTP today — it is here so the question is answerable from the
     * database during an access review or a subject access request, which is the only reason the
     * table is worth keeping.
     */
    List<TranscriptAccess> findByConversationIdOrderByAccessedAtDesc(UUID conversationId);
}
