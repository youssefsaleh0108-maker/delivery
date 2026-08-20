package com.delivery.whatsapp.repo;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

import com.delivery.whatsapp.domain.DraftOrder;

public interface DraftOrderRepository extends JpaRepository<DraftOrder, UUID> {

    /** The one open draft for a conversation, if there is one. */
    Optional<DraftOrder> findByConversationIdAndStatus(UUID conversationId, DraftOrder.Status status);

    /** The merchant's work list: what still needs turning into an order. */
    List<DraftOrder> findByMerchantRefAndStatusOrderByCreatedAtAsc(
            String merchantRef, DraftOrder.Status status);

    /** Scoped by merchant in the query, so a row is never loaded before the ownership test. */
    Optional<DraftOrder> findByIdAndMerchantRef(UUID id, String merchantRef);

    List<DraftOrder> findByConversationIdOrderByCreatedAtDesc(UUID conversationId);

    /**
     * The draft an order came from, if it came from WhatsApp at all.
     *
     * <p>How the status listener tells "this order belongs to a conversation" from "this is one of
     * the thousands of ordinary app orders" — which is most of them, and none of its business.
     */
    Optional<DraftOrder> findByOrderId(UUID orderId);
}
