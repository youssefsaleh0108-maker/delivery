package com.delivery.whatsapp.web.dto;

import java.time.Instant;
import java.util.UUID;

import com.delivery.whatsapp.domain.Conversation;

/**
 * A row in the merchant's inbox.
 *
 * <p>Deliberately does not carry the merchant's own id. It is the caller's own {@code sub}, so
 * echoing it back tells them nothing and puts an identifier on the wire that need not be there.
 */
public record ConversationView(
        UUID id,
        String customerWaId,
        String customerName,
        Instant lastMessageAt,
        int unreadCount,
        boolean archived) {

    public static ConversationView of(Conversation conversation) {
        return new ConversationView(
                conversation.getId(),
                conversation.getCustomerWaId(),
                conversation.displayName(),
                conversation.getLastMessageAt(),
                conversation.getUnreadCount(),
                conversation.isArchived());
    }
}
