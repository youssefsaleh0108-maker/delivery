package com.delivery.whatsapp.repo;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

import com.delivery.whatsapp.domain.Conversation;

public interface ConversationRepository extends JpaRepository<Conversation, UUID> {

    Optional<Conversation> findByMerchantRefAndCustomerWaId(String merchantRef, String customerWaId);

    /** The inbox: who is waiting, most recent first. */
    List<Conversation> findByMerchantRefAndArchivedOrderByLastMessageAtDesc(
            String merchantRef, boolean archived);

    Optional<Conversation> findByIdAndMerchantRef(UUID id, String merchantRef);
}
