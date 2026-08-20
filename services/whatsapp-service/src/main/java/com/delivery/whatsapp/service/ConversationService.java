package com.delivery.whatsapp.service;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.whatsapp.client.OutboundSender;
import com.delivery.whatsapp.domain.Conversation;
import com.delivery.whatsapp.domain.WhatsAppMessage;
import com.delivery.whatsapp.repo.ConversationRepository;
import com.delivery.whatsapp.repo.MessageRepository;

/**
 * The inbox: conversations, and the messages in them.
 */
@Service
public class ConversationService {

    private static final Logger log = LoggerFactory.getLogger(ConversationService.class);

    private final ConversationRepository conversations;
    private final MessageRepository messages;
    private final NumberDirectory numbers;
    private final OutboundSender sender;

    public ConversationService(ConversationRepository conversations,
                               MessageRepository messages,
                               NumberDirectory numbers,
                               OutboundSender sender) {
        this.conversations = conversations;
        this.messages = messages;
        this.numbers = numbers;
        this.sender = sender;
    }

    /**
     * Files an inbound message under the right conversation, creating one if this is a new customer.
     *
     * <p>Each message gets its own transaction. A callback can carry several, and one unparseable or
     * duplicated message must not roll back the others in the batch — the provider would then retry
     * the whole callback and we would be right back where we started.
     *
     * @return the conversation it landed in, or empty if it was ignored
     */
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public Optional<Conversation> record(InboundMessage inbound) {
        String merchantRef = numbers.merchantFor(inbound.phoneNumberId()).orElse(null);
        if (merchantRef == null) {
            // Nobody has connected this number. Dropped rather than parked: there is no merchant who
            // could ever read it, so storing it would only grow a pile no screen will show.
            log.warn("WhatsApp message for unclaimed number {}; no merchant owns it",
                    inbound.phoneNumberId());
            return Optional.empty();
        }

        // Cheap path first. The partial unique index below is the actual guarantee — two concurrent
        // redeliveries would both pass this check — but the overwhelmingly common case is a single
        // retry arriving late, and a lookup is better than a caught constraint violation.
        if (messages.existsByProviderMessageId(inbound.providerMessageId())) {
            log.debug("Ignoring a redelivered WhatsApp message {}", inbound.providerMessageId());
            return Optional.empty();
        }

        Conversation conversation = conversations
                .findByMerchantRefAndCustomerWaId(merchantRef, inbound.customerWaId())
                .orElseGet(() -> conversations.save(new Conversation(
                        merchantRef, inbound.customerWaId(), inbound.customerName(),
                        inbound.phoneNumberId())));

        WhatsAppMessage message = WhatsAppMessage.inbound(
                conversation.getId(), inbound.body(), inbound.kind(),
                inbound.providerMessageId(), inbound.sentAt());

        try {
            messages.saveAndFlush(message);
        } catch (DataIntegrityViolationException e) {
            // The index did its job: another delivery of the same message won the race. Nothing to
            // do, and nothing wrong — this is the mechanism working, not an error.
            log.debug("Concurrent redelivery of WhatsApp message {}", inbound.providerMessageId());
            return Optional.empty();
        }

        conversation.customerSpoke(inbound.sentAt(), inbound.customerName(),
                inbound.phoneNumberId());
        conversations.save(conversation);
        return Optional.of(conversation);
    }

    /**
     * Sends a reply and records it, so the thread shows both halves of the exchange.
     *
     * <p>Recorded whether or not the provider took it. A merchant who typed a message and sees no
     * trace of it will type it again; showing it with the send failure attached is the honest
     * answer, and lets them try once rather than three times.
     */
    @Transactional
    public Reply reply(UUID conversationId, String merchantRef, String body) {
        Conversation conversation = conversations.findByIdAndMerchantRef(conversationId, merchantRef)
                .orElseThrow(() -> new UnknownConversationException("no such conversation"));

        OutboundSender.SendResult result = sender.send(
                conversation.getPhoneNumberId(), conversation.getCustomerWaId(), body);

        WhatsAppMessage message = WhatsAppMessage.outbound(conversation.getId(), body);
        if (result.accepted() && result.providerMessageId() != null) {
            message.acceptedAs(result.providerMessageId());
        }
        messages.save(message);

        conversation.weReplied(message.getSentAt());
        conversations.save(conversation);
        return new Reply(message, result.accepted(), result.detail());
    }

    /** A reply, and whether it actually left the building. */
    public record Reply(WhatsAppMessage message, boolean sent, String failureDetail) {
    }

    /** Thrown when a merchant names a conversation that is not theirs, or is not there. */
    public static class UnknownConversationException extends RuntimeException {
        public UnknownConversationException(String message) {
            super(message);
        }
    }

    @Transactional(readOnly = true)
    public List<Conversation> inbox(String merchantRef, boolean archived) {
        return conversations.findByMerchantRefAndArchivedOrderByLastMessageAtDesc(
                merchantRef, archived);
    }

    @Transactional(readOnly = true)
    public List<WhatsAppMessage> thread(UUID conversationId) {
        return messages.findByConversationIdOrderBySentAtAsc(conversationId);
    }

    /**
     * A conversation this merchant is allowed to see.
     *
     * <p>Scoped by merchant in the query rather than fetched and then checked, so there is no path
     * where the row is loaded before the ownership test — the shape of bug that leaks one shop's
     * customers to another.
     */
    @Transactional(readOnly = true)
    public Optional<Conversation> find(UUID id, String merchantRef) {
        return conversations.findByIdAndMerchantRef(id, merchantRef);
    }

    @Transactional
    public Optional<Conversation> markRead(UUID id, String merchantRef) {
        return conversations.findByIdAndMerchantRef(id, merchantRef).map(conversation -> {
            conversation.markRead();
            return conversations.save(conversation);
        });
    }

    @Transactional
    public Optional<Conversation> archive(UUID id, String merchantRef) {
        return conversations.findByIdAndMerchantRef(id, merchantRef).map(conversation -> {
            conversation.archive();
            return conversations.save(conversation);
        });
    }
}
