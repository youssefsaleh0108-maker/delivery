package com.delivery.appnotification.service;

import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import java.util.function.Function;
import java.util.stream.Collectors;

import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

import com.delivery.appnotification.client.ProductDirectory;
import com.delivery.appnotification.domain.ChatShopMessage;
import com.delivery.appnotification.domain.ChatShopMessageRepository;
import com.delivery.appnotification.domain.ChatShopThread;
import com.delivery.appnotification.domain.ChatShopThreadRepository;
import com.delivery.appnotification.domain.ShopThreadSide;
import com.delivery.appnotification.service.RoomExceptions.RoomNotFoundException;
import com.delivery.appnotification.service.RoomExceptions.SendRateLimitedException;

/**
 * Customers asking shops things, and shops answering.
 *
 * <p><strong>Who is on which side, decided per request.</strong> The customer side is the thread's
 * {@code customer_id}, compared with the caller's token subject. The shop side is a merchant whom
 * Product Service confirms owns the thread's shop ({@link ShopOwnership}). Anybody else — another
 * customer, a merchant of a different shop, a rider — gets the same 404 as a thread that does not
 * exist. No request can name a side or a participant.
 *
 * <p>Posting follows order chat's pattern: text refused before any lock, a gapless sequence under the
 * thread's row lock, idempotent retries, delivery after commit. See {@link ChatShopThread} for the
 * closing policy.
 */
@Service
public class ShopChatService {

    private final ChatShopThreadRepository threads;
    private final ChatShopMessageRepository messages;
    private final ProductDirectory directory;
    private final ShopOwnership ownership;
    private final ShopDelivery delivery;
    private final ShopChatProperties properties;
    private final ChatProperties chatProperties;

    public ShopChatService(ChatShopThreadRepository threads,
                           ChatShopMessageRepository messages,
                           ProductDirectory directory,
                           ShopOwnership ownership,
                           ShopDelivery delivery,
                           ShopChatProperties properties,
                           ChatProperties chatProperties) {
        this.threads = threads;
        this.messages = messages;
        this.directory = directory;
        this.ownership = ownership;
        this.delivery = delivery;
        this.properties = properties;
        this.chatProperties = chatProperties;
    }

    /**
     * The customer's conversation with a shop, opened if it is not already — idempotent, so the
     * chat button can simply call this every time it is tapped.
     *
     * <p>The shop must be one Product Service shows this customer. Opening also restarts the idle
     * window: tapping "chat with the shop" is the customer saying they are interested again.
     */
    @Transactional
    public ThreadState openForCustomer(UUID storeId, String customerId, String customerName) {
        ProductDirectory.Storefront store = directory.storefront(storeId)
                .orElseThrow(() -> new RoomNotFoundException(storeId));
        String storeName = store.name() == null ? "" : store.name();
        Instant closes = Instant.now().plus(properties.getIdleCloseAfter());

        threads.insertIfAbsent(UUID.randomUUID(), storeId, customerId, customerName, storeName, closes);
        ChatShopThread thread = threads.findByStoreIdAndCustomerId(storeId, customerId)
                .orElseThrow(() -> new IllegalStateException("A shop thread vanished right after it was opened"));
        thread.keepOpenUntil(closes);
        thread.refresh(storeName, customerName);

        return state(thread, ShopThreadSide.CUSTOMER);
    }

    /** The calling merchant's inbox: threads with messages, for the shops they own, newest first. */
    @Transactional
    public List<ThreadState> inbox(String merchantId) {
        Set<UUID> stores = ownership.storesOf(merchantId);
        if (stores.isEmpty()) {
            return List.of();
        }
        List<ChatShopThread> list = threads.inboxFor(stores, PageRequest.of(0, properties.getInboxPageSize()));
        if (list.isEmpty()) {
            return List.of();
        }

        List<UUID> ids = list.stream().map(ChatShopThread::getId).toList();
        Map<UUID, Long> unread = messages.unreadFrom(ids, ShopThreadSide.CUSTOMER).stream()
                .collect(Collectors.toMap(ChatShopMessageRepository.UnreadTally::getThreadId,
                        ChatShopMessageRepository.UnreadTally::getUnread));
        Map<UUID, ChatShopMessage> latest = messages.latestIn(ids).stream()
                .collect(Collectors.toMap(ChatShopMessage::getThreadId, Function.identity(),
                        (first, second) -> first));

        return list.stream()
                .map(thread -> new ThreadState(thread, ShopThreadSide.SHOP,
                        unread.getOrDefault(thread.getId(), 0L), latest.get(thread.getId())))
                .toList();
    }

    /** The thread from a cursor, for whichever side the caller is on. */
    @Transactional
    public ThreadPage history(UUID threadId, String userId, boolean callerIsMerchant, long afterSequence) {
        ChatShopThread thread = threads.findById(threadId)
                .orElseThrow(() -> new RoomNotFoundException(threadId));
        ShopThreadSide side = sideOf(threadId, thread.getStoreId(), thread.getCustomerId(), userId,
                callerIsMerchant);

        int size = properties.getHistoryPageSize();
        List<ChatShopMessage> page = messages.findByThreadIdAndSequenceNoGreaterThanOrderBySequenceNoAsc(
                threadId, afterSequence, PageRequest.of(0, size + 1));
        boolean more = page.size() > size;
        return new ThreadPage(state(thread, side), more ? page.subList(0, size) : page, more);
    }

    /**
     * Says something, as whichever side the caller is on.
     *
     * <p>409 once the thread has gone idle — for the shop especially, which cannot reopen it; the
     * customer reopens by opening the chat again.
     */
    @Transactional
    public Posted post(UUID threadId, String userId, boolean callerIsMerchant, String text,
                       String clientMessageId, String correlationId) {
        String body = ChatMessageText.normalise(text, chatProperties.getMaxMessageLength());

        ChatShopThreadRepository.Parties parties = threads.partiesOf(threadId)
                .orElseThrow(() -> new RoomNotFoundException(threadId));
        ShopThreadSide side = sideOf(threadId, parties.getStoreId(), parties.getCustomerId(), userId,
                callerIsMerchant);

        ChatShopThread thread = threads.lockById(threadId)
                .orElseThrow(() -> new RoomNotFoundException(threadId));

        String clientId = clientMessageId == null || clientMessageId.isBlank() ? null : clientMessageId;
        if (clientId != null) {
            Optional<ChatShopMessage> already =
                    messages.findByThreadIdAndSenderIdAndClientMessageId(threadId, userId, clientId);
            if (already.isPresent()) {
                return new Posted(already.get(), thread.getStoreId());
            }
        }

        Instant now = Instant.now();
        if (!thread.isOpenAt(now)) {
            throw new ConversationClosedException(threadId, thread.getClosesAt());
        }
        if (messages.countBySenderIdAndCreatedAtAfter(userId, now.minus(properties.getSendWindow()))
                >= properties.getMaxMessagesPerWindow()) {
            throw new SendRateLimitedException(properties.getSendWindow());
        }

        ChatShopMessage message = messages.save(new ChatShopMessage(
                threadId, thread.claimSequence(now), userId, side, body, clientId, now));
        if (side == ShopThreadSide.CUSTOMER) {
            thread.keepOpenUntil(now.plus(properties.getIdleCloseAfter()));
        }

        deliverAfterCommit(message, thread.getStoreId(), thread.getCustomerId());
        return new Posted(message, thread.getStoreId());
    }

    /** Marks what the other side said, up to a cursor, as read by the caller's side. */
    @Transactional
    public int markRead(UUID threadId, String userId, boolean callerIsMerchant, long upToSequence) {
        ChatShopThreadRepository.Parties parties = threads.partiesOf(threadId)
                .orElseThrow(() -> new RoomNotFoundException(threadId));
        ShopThreadSide side = sideOf(threadId, parties.getStoreId(), parties.getCustomerId(), userId,
                callerIsMerchant);
        return messages.markReadUpTo(threadId, side.other(), upToSequence, Instant.now());
    }

    // ---------------------------------------------------------------------------------- internals

    /**
     * The customer first: a merchant who opened a thread with somebody else's shop is that thread's
     * customer, and must not be mistaken for its shop.
     */
    private ShopThreadSide sideOf(UUID threadId, UUID storeId, String customerId, String userId,
                                  boolean callerIsMerchant) {
        if (customerId.equals(userId)) {
            return ShopThreadSide.CUSTOMER;
        }
        if (callerIsMerchant && ownership.owns(userId, storeId)) {
            return ShopThreadSide.SHOP;
        }
        throw new RoomNotFoundException(threadId);
    }

    private ThreadState state(ChatShopThread thread, ShopThreadSide side) {
        long unread = messages.unreadFrom(List.of(thread.getId()), side.other()).stream()
                .mapToLong(ChatShopMessageRepository.UnreadTally::getUnread)
                .sum();
        return new ThreadState(thread, side, unread, null);
    }

    private void deliverAfterCommit(ChatShopMessage message, UUID storeId, String customerId) {
        if (!TransactionSynchronizationManager.isSynchronizationActive()) {
            delivery.deliver(message, storeId, customerId);
            return;
        }
        TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
            @Override
            public void afterCommit() {
                delivery.deliver(message, storeId, customerId);
            }
        });
    }

    /**
     * A thread as one side sees it.
     *
     * @param unread what the other side said that this side has not read
     * @param latest the last message, for the inbox preview; null where it was not asked for
     */
    public record ThreadState(ChatShopThread thread, ShopThreadSide side, long unread, ChatShopMessage latest) {

        /** A lock-screen-sized cut of the last message; the full text is one tap away. */
        public String latestPreview() {
            return latest == null ? null : ChatMessageText.preview(latest.getBody(), 120);
        }
    }

    public record ThreadPage(ThreadState state, List<ChatShopMessage> messages, boolean more) {
    }

    /** A stored message and the shop its thread is with, so the reply can say so without a lookup. */
    public record Posted(ChatShopMessage message, UUID storeId) {
    }
}
