package com.delivery.whatsapp.repo;

import java.util.List;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

import com.delivery.whatsapp.domain.WhatsAppMessage;

public interface MessageRepository extends JpaRepository<WhatsAppMessage, UUID> {

    /** The thread, oldest first, which is how a conversation reads. */
    List<WhatsAppMessage> findByConversationIdOrderBySentAtAsc(UUID conversationId);

    /**
     * The idempotency check. The partial unique index is the real guarantee; this makes the common
     * case a lookup instead of a caught constraint violation.
     */
    boolean existsByProviderMessageId(String providerMessageId);
}
