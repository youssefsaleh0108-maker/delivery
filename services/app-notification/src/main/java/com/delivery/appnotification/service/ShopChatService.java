package com.delivery.appnotification.service;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import java.util.function.Function;
import java.util.stream.Collectors;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

import com.delivery.appnotification.client.OrderReferences;
import com.delivery.appnotification.client.OrderReferences.OrderReference;
import com.delivery.appnotification.client.ProductDirectory;
import com.delivery.appnotification.domain.ChatShopMessage;
import com.delivery.appnotification.domain.ChatShopMessageRepository;
import com.delivery.appnotification.domain.ChatShopThread;
import com.delivery.appnotification.domain.ChatShopThreadRepository;
import com.delivery.appnotification.domain.ShopThreadSide;
import com.delivery.appnotification.service.RoomExceptions.OrderChatClosedException;
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
 * <p><strong>Which order a thread is about.</strong> A thread carries at most one order reference:
 * the latest one Order Manager confirmed, never anything a client typed. A customer attaches one of
 * their own orders with the shop by opening the thread from it; a merchant opens the thread for an
 * order of a shop they answer for, which creates it if the customer never wrote. Order Manager is
 * asked with the caller's own token ({@link OrderReferences}), so neither side can attach an order
 * they could not open in their own app, and the shop's side is still never told the customer's user
 * id.
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
    private final OrderReferences orders;
    private final ShopOwnership ownership;
    private final ShopDelivery delivery;
    private final ShopChatProperties properties;
    private final ChatProperties chatProperties;
    private final Clock clock;

    @Autowired
    public ShopChatService(ChatShopThreadRepository threads,
                           ChatShopMessageRepository messages,
                           ProductDirectory directory,
                           OrderReferences orders,
                           ShopOwnership ownership,
                           ShopDelivery delivery,
                           ShopChatProperties properties,
                           ChatProperties chatProperties) {
        this(threads, messages, directory, orders, ownership, delivery, properties, chatProperties,
                Clock.systemUTC());
    }

    /** For tests, which stand "now" exactly on the edge of an order's window. */
    ShopChatService(ChatShopThreadRepository threads,
                    ChatShopMessageRepository messages,
                    ProductDirectory directory,
                    OrderReferences orders,
                    ShopOwnership ownership,
                    ShopDelivery delivery,
                    ShopChatProperties properties,
                    ChatProperties chatProperties,
                    Clock clock) {
        this.threads = threads;
        this.messages = messages;
        this.directory = directory;
        this.orders = orders;
        this.ownership = ownership;
        this.delivery = delivery;
        this.properties = properties;
        this.chatProperties = chatProperties;
        this.clock = clock;
    }

    /**
     * The customer's conversation with a shop, opened if it is not already — idempotent, so the
     * chat button can simply call this every time it is tapped.
     *
     * <p>The shop must be one Product Service shows this customer. Opening also restarts the idle
     * window: tapping "chat with the shop" is the customer saying they are interested again.
     *
     * <p><strong>From an order.</strong> With {@code orderId}, the thread is also labelled with that
     * order once Order Manager confirms it is this customer's and was placed with this shop. That is
     * checked before anything is written, and every other answer — somebody else's order, another
     * shop's, one that does not exist — is the very 404 an unknown shop gets, message and all, so this
     * cannot be used to learn which orders exist or whose they are. When Order Manager cannot be asked
     * the open is refused, rather than done without the order it was opened from. An open without an
     * order never asks Order Manager and works exactly as before; it also leaves an earlier label be.
     *
     * @param orderId the order the customer opened the chat from, or null from the shop page
     */
    @Transactional
    public ThreadState openForCustomer(UUID storeId, String customerId, String customerName, UUID orderId) {
        ProductDirectory.Storefront store = directory.storefront(storeId)
                .orElseThrow(() -> new RoomNotFoundException(storeId));
        OrderReference order = orderId == null ? null : orders.visibleToCaller(orderId)
                .filter(found -> customerId.equals(found.customerId()) && storeId.equals(found.storeId()))
                .orElseThrow(() -> new RoomNotFoundException(storeId));

        String storeName = store.name() == null ? "" : store.name();
        Instant closes = clock.instant().plus(properties.getIdleCloseAfter());

        threads.insertIfAbsent(UUID.randomUUID(), storeId, customerId, customerName, storeName, closes);
        ChatShopThread thread = threads.findByStoreIdAndCustomerId(storeId, customerId)
                .orElseThrow(() -> new IllegalStateException("A shop thread vanished right after it was opened"));
        thread.keepOpenUntil(closes);
        thread.refresh(storeName, customerName);
        if (order != null) {
            thread.attachOrder(order.id(), order.kind());
        }

        return state(thread, ShopThreadSide.CUSTOMER);
    }

    /**
     * The conversation between an order's shop and the customer who placed it, opened if the customer
     * never wrote, and labelled with that order: a provider's "chat with the customer". Idempotent.
     *
     * <p><strong>Only an order of a shop the caller answers for.</strong> Order Manager must show the
     * order to the caller, and Product Service must confirm they own the shop it was placed with — the
     * {@link ShopOwnership} rule the inbox and every thread read use. Any other order, or one with no
     * shop, is the 404 of an order that does not exist, before anything about its state is looked at.
     *
     * <p><strong>Only within the order's window.</strong> The window starts at the earlier of when the
     * order ended — delivered or cancelled, or now while it has not — and when it was due
     * ({@link OrderReference#dueAt()}), and lasts {@link ShopChatProperties#getOrderChatWindow()}. From
     * its end, a 409 with when that was. Within it, opening keeps the thread accepting messages until
     * the earlier of the window's end and the customer idle window from now.
     *
     * <p>That is the one way a shop moves a thread's closing time, and it is bounded by facts the shop
     * cannot stretch ({@code shopMaySpeakUntil}): the idle rule in {@link ChatShopThread} still stops a
     * shop keeping a line open to a customer with no order inside its window, the shop's replies still
     * never move it, and it never shortens a thread the customer is keeping open. What is said
     * afterwards is rate limited as ever.
     *
     * <p>A thread the merchant creates names the customer as the order's card does; one that already
     * exists keeps the name its customer's own sign-in gave it.
     */
    @Transactional
    public ThreadState openForOrder(UUID orderId, String merchantId) {
        OrderReference order = orders.visibleToCaller(orderId)
                .filter(found -> found.storeId() != null && ownership.owns(merchantId, found.storeId()))
                .orElseThrow(() -> new RoomNotFoundException(orderId));
        Instant until = shopMaySpeakUntil(order, clock.instant());

        String storeName = order.storeName() == null ? "" : order.storeName();
        threads.insertIfAbsent(UUID.randomUUID(), order.storeId(), order.customerId(),
                order.customerDisplayName(), storeName, until);
        ChatShopThread thread = threads.findByStoreIdAndCustomerId(order.storeId(), order.customerId())
                .orElseThrow(() -> new IllegalStateException("A shop thread vanished right after it was opened"));
        thread.keepOpenUntil(until);
        thread.attachOrder(order.id(), order.kind());

        return state(thread, ShopThreadSide.SHOP);
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

        Instant now = clock.instant();
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
        return messages.markReadUpTo(threadId, side.other(), upToSequence, clock.instant());
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

    /**
     * Until when a shop opening the thread for this order may speak on it: the earlier of the order
     * window's end and the customer idle window from now. Refused once the order window has passed.
     *
     * <p><strong>The window is counted from facts the shop cannot stretch:</strong> the earlier of
     * when the order ended (now, while it has not) and when it was due. Counted from the end alone it
     * was the shop's to hold open. A customer can cancel only a PLACED order and nothing expires one,
     * so a shop that left an order ACCEPTED, PREPARING or READY renewed a week's line to its customer
     * with every open, for as long as it liked — and a shop thread gives the customer no block or
     * report. The due time ends that: an order still open past it, or finished after it, closes a
     * window after it was due, whatever the shop marks and however often it opens. An order finished
     * before it was due closes a window after it finished.
     *
     * <p>An ended order with no recorded end cannot be placed in its window, and is refused rather
     * than read as open.
     */
    private Instant shopMaySpeakUntil(OrderReference order, Instant now) {
        Duration window = properties.getOrderChatWindow();
        Instant endedOrNow = now;
        if (order.hasEnded()) {
            endedOrNow = order.endedAt();
            if (endedOrNow == null) {
                throw new OrderChatClosedException(order.id(), null);
            }
        }
        Instant due = order.dueAt();
        Instant windowFrom = endedOrNow.isBefore(due) ? endedOrNow : due;
        Instant closedAt = windowFrom.plus(window);
        if (!now.isBefore(closedAt)) {
            throw new OrderChatClosedException(order.id(), closedAt);
        }
        Instant byIdle = now.plus(properties.getIdleCloseAfter());
        return closedAt.isBefore(byIdle) ? closedAt : byIdle;
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
