package com.delivery.appnotification.service;

import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.stream.Collectors;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

import com.delivery.appnotification.domain.ChatConversation;
import com.delivery.appnotification.domain.ChatConversationRepository;
import com.delivery.appnotification.domain.ChatMessage;
import com.delivery.appnotification.domain.ChatMessageRepository;
import com.delivery.appnotification.domain.ChatParticipantRole;
import com.delivery.appnotification.domain.TranscriptAccess;
import com.delivery.appnotification.domain.TranscriptAccessRepository;

/**
 * Order chat: who may talk to whom, when the line is open, and what gets stored.
 *
 * <p><strong>Every method that touches a conversation takes the caller's user id and resolves
 * membership from the row.</strong> There is no "trusted" variant that skips the check and no way
 * to name a participant other than yourself, which is what makes reading somebody else's
 * conversation unexpressible rather than merely forbidden — the same shape as
 * {@code InAppNotificationController}'s inbox. The one exception is the support read, which is
 * separate, gated and audited; see {@link #transcriptForSupport}.
 *
 * <p>The persist-then-deliver order from {@code InAppMessageService} carries over unchanged: the
 * row is the message, the frame only saves a fetch. Delivery is registered for after commit so a
 * rolled-back transaction cannot leave a message on somebody's screen that vanishes when they
 * refresh.
 */
@Service
public class ChatService {

    private static final Logger log = LoggerFactory.getLogger(ChatService.class);

    private final ChatConversationRepository conversations;
    private final ChatMessageRepository messages;
    private final TranscriptAccessRepository transcriptAccess;
    private final ChatDelivery delivery;
    private final ChatProperties properties;

    public ChatService(ChatConversationRepository conversations,
                       ChatMessageRepository messages,
                       TranscriptAccessRepository transcriptAccess,
                       ChatDelivery delivery,
                       ChatProperties properties) {
        this.conversations = conversations;
        this.messages = messages;
        this.transcriptAccess = transcriptAccess;
        this.delivery = delivery;
        this.properties = properties;
    }

    // ---------------------------------------------------------------- lifecycle, driven by the bus

    /**
     * Opens the conversation for an order, or returns the one that is already open.
     *
     * <p>Called when a rider is assigned, which is the earliest moment there is a second person to
     * talk to. Before that the order has a customer and no counterpart, and a chat with one
     * participant is a notes field.
     *
     * <p><strong>A reassignment closes the old thread and opens a new one</strong> rather than
     * rewriting {@code rider_id}. Rewriting would hand the incoming rider every word the previous
     * rider exchanged with the customer — a private conversation with a third party, silently
     * disclosed — and would also let the outgoing rider keep reading a thread that carries on
     * without them. Two threads means each rider sees exactly the part they were in. The customer
     * sees both, which is correct: they were in both.
     *
     * @return the live conversation, or empty if the order does not describe two distinct people
     */
    @Transactional
    public Optional<ChatConversation> openForRider(UUID orderId, String customerId, String riderId) {
        if (customerId == null || customerId.isBlank() || riderId == null || riderId.isBlank()) {
            return Optional.empty();
        }
        if (customerId.equals(riderId)) {
            // The database CHECK would refuse this anyway; catching it here keeps a malformed event
            // from becoming a constraint violation in a listener, which is a redelivery loop.
            log.warn("Order {} names the same person as customer and rider; no chat opened", orderId);
            return Optional.empty();
        }

        Optional<ChatConversation> live = conversations.findLiveByOrderId(orderId);
        if (live.isPresent()) {
            ChatConversation existing = live.get();
            if (existing.getRiderId().equals(riderId)) {
                // A redelivered order.rider_assigned. Normal, not exceptional.
                return live;
            }
            existing.closeAt(Instant.now());
            // Flushed before the insert on purpose: uq_chat_open_per_order allows one row per order
            // with a null closes_at, and without the flush the insert races the pending update
            // inside the same transaction and trips the constraint.
            conversations.saveAndFlush(existing);
            log.info("Order {} was reassigned; previous chat closed and a new one opened", orderId);
        }

        return Optional.of(conversations.save(new ChatConversation(orderId, customerId, riderId)));
    }

    /**
     * Starts the clock on a conversation whose order has ended.
     *
     * <p>Does not close it now — see {@link ChatProperties#getCloseAfterDelivery()} for why a
     * delivered order keeps a window open, and why a cancelled one does not.
     */
    @Transactional
    public void closeAfter(UUID orderId, java.time.Duration window) {
        conversations.findLiveByOrderId(orderId)
                .ifPresent(conversation -> conversation.closeAt(Instant.now().plus(window)));
    }

    // ------------------------------------------------------------------------------- participants

    /**
     * Posts a message.
     *
     * <p>The order of the checks is deliberate. Text is validated first, before any lock is taken,
     * so a message that was never going to be accepted does not serialise the thread. The
     * membership check comes before the open check, so a stranger learns nothing about whether a
     * conversation is still running.
     *
     * @param clientMessageId the sender's own id for this message, or null. When supplied, a repeat
     *                        returns the message already stored instead of posting a second one —
     *                        a phone that loses signal mid-POST retries, and the customer should not
     *                        end up having said it twice
     */
    @Transactional
    public ChatMessage post(UUID conversationId, String senderId, String text,
                            String clientMessageId, String correlationId) {

        String body = ChatMessageText.normalise(text, properties.getMaxMessageLength());

        ChatConversation conversation = conversations.lockById(conversationId)
                .filter(candidate -> candidate.isParticipant(senderId))
                .orElseThrow(() -> new ConversationNotFoundException(conversationId));

        if (clientMessageId != null && !clientMessageId.isBlank()) {
            Optional<ChatMessage> already =
                    messages.findByConversationIdAndClientMessageId(conversationId, clientMessageId);
            if (already.isPresent()) {
                // Checked BEFORE the closed check: a retry of something accepted while the line was
                // open must still succeed after it shuts, or a customer's last message is lost to
                // the exact network failure the retry exists to survive.
                return already.get();
            }
        }

        Instant now = Instant.now();
        if (!conversation.isOpenAt(now)) {
            throw new ConversationClosedException(conversationId, conversation.getClosesAt());
        }

        ChatParticipantRole senderRole = conversation.roleOf(senderId).orElseThrow();
        String recipientId = conversation.counterpartOf(senderId).orElseThrow();

        ChatMessage message = messages.save(new ChatMessage(
                conversationId, conversation.claimSequence(now), senderId, senderRole, body,
                blankToNull(clientMessageId), now));

        deliverAfterCommit(new ChatDelivery.Deliverable(
                message.getId(), conversationId, conversation.getOrderId(), message.getSequenceNo(),
                recipientId, other(senderRole), senderRole, body, now, correlationId));

        return message;
    }

    /**
     * The thread, from a cursor.
     *
     * <p>This is the reconnect path as well as the first-open path, and it is what makes a message
     * survive a dropped socket: the row was committed before any frame was attempted, so a client
     * that comes back and asks for everything after the last number it holds gets whatever it
     * missed, in order, whether or not a frame was ever sent.
     *
     * @param afterSequence 0 for the whole thread, or the last sequence the client already has
     */
    @Transactional
    public List<ChatMessage> thread(UUID conversationId, String userId, long afterSequence) {
        requireParticipant(conversationId, userId);

        List<ChatMessage> page =
                messages.findByConversationIdAndSequenceNoGreaterThanOrderBySequenceNoAsc(
                        conversationId, afterSequence,
                        PageRequest.of(0, properties.getHistoryPageSize()));

        // Fetching IS delivery for a client whose socket was down. Marked on the loaded entities
        // rather than with a bulk statement because the bulk form clears the persistence context,
        // which would detach the very rows about to be returned - and because it only writes for
        // messages that actually changed, so the common case (a refetch of an already-delivered
        // thread) writes nothing at all.
        Instant now = Instant.now();
        page.stream()
                .filter(message -> !message.getSenderId().equals(userId))
                .forEach(message -> message.markDelivered(now));

        return page;
    }

    /**
     * Marks everything the other person said, up to a cursor, as read.
     *
     * <p>A cursor rather than a message id because that is what the client knows: it has the thread
     * on screen and has scrolled to the bottom.
     *
     * @return how many messages this actually changed
     */
    @Transactional
    public int markRead(UUID conversationId, String userId, long upToSequence) {
        requireParticipant(conversationId, userId);
        return messages.markReadUpTo(conversationId, userId, upToSequence, Instant.now());
    }

    /** Every conversation this person is in, with the badge the design shows on each. */
    @Transactional(readOnly = true)
    public List<ConversationView> conversationsFor(String userId) {
        List<ChatConversation> mine = conversations.findAllForParticipant(userId);
        if (mine.isEmpty()) {
            return List.of();
        }

        Map<UUID, Long> unread = unreadByConversation(mine, userId);
        Instant now = Instant.now();

        return mine.stream()
                .map(conversation -> toView(conversation, userId, now,
                        unread.getOrDefault(conversation.getId(), 0L)))
                .toList();
    }

    /**
     * The badge on the app icon: every unread chat message across every conversation, plus the
     * per-conversation breakdown the list screen needs.
     *
     * <p>Both in one response because the client needs both at the same moment and a second round
     * trip to derive one from the other would be the same query twice.
     */
    @Transactional(readOnly = true)
    public UnreadSummary unreadSummary(String userId) {
        List<ChatConversation> mine = conversations.findAllForParticipant(userId);
        if (mine.isEmpty()) {
            return new UnreadSummary(0L, Map.of());
        }

        Map<UUID, Long> byConversation = unreadByConversation(mine, userId);
        long total = byConversation.values().stream().mapToLong(Long::longValue).sum();
        return new UnreadSummary(total, byConversation);
    }

    /** The conversation currently attached to an order, for a client that only holds the order id. */
    @Transactional(readOnly = true)
    public ConversationView conversationForOrder(UUID orderId, String userId) {
        Instant now = Instant.now();
        return conversations.findByOrderIdOrderByOpenedAtDesc(orderId).stream()
                // A reassigned order has more than one thread and the caller may be in only some of
                // them. Newest-first plus this filter gives a rider their own and nobody else's.
                .filter(conversation -> conversation.isParticipant(userId))
                .findFirst()
                .map(conversation -> toView(conversation, userId, now,
                        messages.countByConversationIdAndSenderIdNotAndReadAtIsNull(
                                conversation.getId(), userId)))
                .orElseThrow(() -> new ConversationNotFoundException(orderId));
    }

    // ------------------------------------------------------------------------------- support read

    /**
     * The transcript, for a support agent settling a dispute.
     *
     * <p>Deliberately not a widening of the participant check — it is a separate method reached from
     * a separate, role-gated endpoint, so no ordinary read can drift into granting it. Three things
     * make it defensible:
     *
     * <ul>
     *   <li>It is read-only. There is no support path that posts, because a transcript has to stay a
     *       record of what the two people actually said to each other.</li>
     *   <li>It writes an audit row first, in the same transaction. If the audit cannot be written
     *       the transcript is not returned — an unaudited read is precisely what this is designed
     *       to prevent.</li>
     *   <li>It requires a stated reason, so the audit trail says why and not merely that.</li>
     * </ul>
     *
     * <p>The alternative — refusing support any access — does not remove the read. It relocates it
     * to whoever holds a database password, where none of the three properties above apply.
     */
    @Transactional
    public List<ChatMessage> transcriptForSupport(UUID conversationId, String actorId, String reason,
                                                  String correlationId) {
        if (!properties.isBackofficeTranscriptAccess()) {
            // Indistinguishable from "no such conversation", so a disabled deployment does not
            // advertise which conversations exist to the staff who cannot read them.
            throw new ConversationNotFoundException(conversationId);
        }

        ChatConversation conversation = conversations.findById(conversationId)
                .orElseThrow(() -> new ConversationNotFoundException(conversationId));

        transcriptAccess.save(new TranscriptAccess(
                conversation.getId(), actorId, reason, correlationId));

        // The conversation id, never its contents: this line is read by anyone with log access,
        // which is a much larger group than the one allowed to call this endpoint.
        log.info("Backoffice {} read the transcript of conversation {}", actorId, conversationId);

        return messages.findByConversationIdAndSequenceNoGreaterThanOrderBySequenceNoAsc(
                conversationId, 0L, PageRequest.of(0, properties.getHistoryPageSize()));
    }

    // ------------------------------------------------------------------------------------ internals

    private ChatConversation requireParticipant(UUID conversationId, String userId) {
        return conversations.findById(conversationId)
                .filter(conversation -> conversation.isParticipant(userId))
                .orElseThrow(() -> new ConversationNotFoundException(conversationId));
    }

    private Map<UUID, Long> unreadByConversation(List<ChatConversation> mine, String userId) {
        List<UUID> ids = mine.stream().map(ChatConversation::getId).toList();
        return messages.countUnreadByConversation(ids, userId).stream()
                .collect(Collectors.toMap(
                        ChatMessageRepository.UnreadTally::getConversationId,
                        ChatMessageRepository.UnreadTally::getUnread,
                        (first, second) -> first,
                        LinkedHashMap::new));
    }

    private static ConversationView toView(ChatConversation conversation, String userId,
                                           Instant now, long unread) {
        return new ConversationView(
                conversation.getId(),
                conversation.getOrderId(),
                conversation.roleOf(userId).orElse(null),
                conversation.isOpenAt(now),
                conversation.getOpenedAt(),
                conversation.getClosesAt(),
                conversation.getLastMessageAt(),
                // next_sequence counts the message that has not been written yet.
                conversation.getNextSequence() - 1,
                unread);
    }

    private static ChatParticipantRole other(ChatParticipantRole role) {
        return role == ChatParticipantRole.CUSTOMER
                ? ChatParticipantRole.RIDER
                : ChatParticipantRole.CUSTOMER;
    }

    private static String blankToNull(String value) {
        return value == null || value.isBlank() ? null : value;
    }

    /**
     * Hands the message to {@link ChatDelivery} once the row is safely committed.
     *
     * <p>The no-transaction branch is not dead code: it is what lets this be exercised from a plain
     * unit test, and it means a future caller outside a transaction gets delivery rather than
     * silence.
     */
    private void deliverAfterCommit(ChatDelivery.Deliverable deliverable) {
        if (!TransactionSynchronizationManager.isSynchronizationActive()) {
            delivery.deliver(deliverable);
            return;
        }
        TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
            @Override
            public void afterCommit() {
                delivery.deliver(deliverable);
            }
        });
    }

    /**
     * One conversation as a participant sees it.
     *
     * @param yourRole which side the caller is on — the client draws the thread from this
     * @param open     whether the composer should be enabled
     * @param unread   the badge
     */
    public record ConversationView(
            UUID id,
            UUID orderId,
            ChatParticipantRole yourRole,
            boolean open,
            Instant openedAt,
            Instant closesAt,
            Instant lastMessageAt,
            long lastSequence,
            long unread) {
    }

    /** @param byConversation conversation id to unread count; conversations with none are absent */
    public record UnreadSummary(long total, Map<UUID, Long> byConversation) {
    }
}
