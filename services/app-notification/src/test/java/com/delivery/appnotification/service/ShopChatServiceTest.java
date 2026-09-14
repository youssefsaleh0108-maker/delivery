package com.delivery.appnotification.service;

import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import com.delivery.appnotification.client.OrderReferences;
import com.delivery.appnotification.client.OrderReferences.OrderReference;
import com.delivery.appnotification.client.ProductDirectory;
import com.delivery.appnotification.domain.ChatShopMessage;
import com.delivery.appnotification.domain.ChatShopMessageRepository;
import com.delivery.appnotification.domain.ChatShopThread;
import com.delivery.appnotification.domain.ChatShopThreadRepository;
import com.delivery.appnotification.domain.ShopThreadSide;
import com.delivery.appnotification.service.RoomExceptions.OrderChatClosedException;
import com.delivery.appnotification.service.RoomExceptions.OrderUnavailableException;
import com.delivery.appnotification.service.RoomExceptions.RoomNotFoundException;
import com.delivery.appnotification.service.RoomExceptions.SendRateLimitedException;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.assertj.core.api.Assertions.catchThrowable;
import static org.assertj.core.api.Assertions.within;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

/**
 * A customer's conversation with a shop: exactly that customer on one side, exactly the shop's
 * confirmed owner on the other, a line that goes quiet when the customer does, and an order on it only
 * when Order Manager has confirmed that order to whoever opened it.
 */
class ShopChatServiceTest {

    private static final UUID STORE = UUID.randomUUID();
    private static final UUID OTHER_STORE = UUID.randomUUID();
    private static final String CUSTOMER = "customer-sub";
    private static final String OTHER_CUSTOMER = "other-customer-sub";
    private static final String MERCHANT = "merchant-sub";
    private static final String OTHER_MERCHANT = "other-shop-merchant-sub";

    private ChatShopThreadRepository threads;
    private ChatShopMessageRepository messages;
    private ProductDirectory directory;
    private OrderReferences orders;
    private ShopOwnership ownership;
    private ShopDelivery delivery;
    private ShopChatProperties properties;
    private ShopChatService service;

    private ChatShopThread thread;

    @BeforeEach
    void setUp() {
        threads = mock(ChatShopThreadRepository.class);
        messages = mock(ChatShopMessageRepository.class);
        directory = mock(ProductDirectory.class);
        orders = mock(OrderReferences.class);
        ownership = mock(ShopOwnership.class);
        delivery = mock(ShopDelivery.class);
        properties = new ShopChatProperties();
        service = new ShopChatService(threads, messages, directory, orders, ownership, delivery, properties,
                new ChatProperties());

        thread = new ChatShopThread(STORE, CUSTOMER, "Tania K.", "Abu Hassan Mini Market",
                Instant.now().plus(Duration.ofDays(3)));
        when(threads.findById(thread.getId())).thenReturn(Optional.of(thread));
        when(threads.lockById(thread.getId())).thenReturn(Optional.of(thread));
        when(threads.partiesOf(thread.getId())).thenReturn(Optional.of(parties(STORE, CUSTOMER)));
        when(messages.save(any(ChatShopMessage.class))).thenAnswer(call -> call.getArgument(0));
        when(messages.findByThreadIdAndSenderIdAndClientMessageId(any(), anyString(), anyString()))
                .thenReturn(Optional.empty());
        when(ownership.owns(MERCHANT, STORE)).thenReturn(true);
    }

    @Nested
    @DisplayName("opening a conversation with a shop")
    class Opening {

        @Test
        @DisplayName("opens it for a shop Product Service shows the customer, named as Product Service names it")
        void opens_for_a_visible_shop() {
            when(directory.storefront(STORE))
                    .thenReturn(Optional.of(new ProductDirectory.Storefront(STORE, "Abu Hassan Mini Market")));
            when(threads.findByStoreIdAndCustomerId(STORE, CUSTOMER)).thenReturn(Optional.of(thread));

            ShopChatService.ThreadState state = service.openForCustomer(STORE, CUSTOMER, "Tania K.", null);

            assertThat(state.thread()).isSameAs(thread);
            assertThat(state.side()).isEqualTo(ShopThreadSide.CUSTOMER);
            assertThat(state.thread().getOrderId()).isNull();
            verify(threads).insertIfAbsent(any(UUID.class), eq(STORE), eq(CUSTOMER), eq("Tania K."),
                    eq("Abu Hassan Mini Market"), any(Instant.class));
            // Without an order, opening never depends on Order Manager.
            verifyNoInteractions(orders);
        }

        @Test
        @DisplayName("opening it again is the same conversation, with its idle clock restarted")
        void opening_again_is_the_same_thread() {
            when(directory.storefront(STORE))
                    .thenReturn(Optional.of(new ProductDirectory.Storefront(STORE, "Abu Hassan Mini Market")));
            when(threads.findByStoreIdAndCustomerId(STORE, CUSTOMER)).thenReturn(Optional.of(thread));

            service.openForCustomer(STORE, CUSTOMER, "Tania K.", null);
            ShopChatService.ThreadState again = service.openForCustomer(STORE, CUSTOMER, "Tania K.", null);

            assertThat(again.thread()).isSameAs(thread);
            assertThat(thread.getClosesAt())
                    .isCloseTo(Instant.now().plus(Duration.ofDays(14)), within(Duration.ofSeconds(5)));
        }

        @Test
        @DisplayName("a shop the customer cannot see has no conversation to open")
        void an_invisible_shop_has_no_thread() {
            when(directory.storefront(STORE)).thenReturn(Optional.empty());

            assertThatThrownBy(() -> service.openForCustomer(STORE, CUSTOMER, "Tania K.", null))
                    .isInstanceOf(RoomNotFoundException.class);
            verify(threads, never()).insertIfAbsent(any(), any(), any(), any(), any(), any());
        }
    }

    @Nested
    @DisplayName("a customer opening the thread from one of their orders")
    class CustomerOpensFromAnOrder {

        private final UUID orderId = UUID.randomUUID();

        @BeforeEach
        void aVisibleShopAndItsThread() {
            when(directory.storefront(STORE))
                    .thenReturn(Optional.of(new ProductDirectory.Storefront(STORE, "Abu Hassan Print")));
            when(threads.findByStoreIdAndCustomerId(STORE, CUSTOMER)).thenReturn(Optional.of(thread));
        }

        @Test
        @DisplayName("labels the thread with the order once Order Manager confirms it is theirs and this shop's")
        void labels_a_confirmed_order() {
            when(orders.visibleToCaller(orderId)).thenReturn(Optional.of(openOrder(orderId, STORE, CUSTOMER)));

            ShopChatService.ThreadState state = service.openForCustomer(STORE, CUSTOMER, "Tania K.", orderId);

            assertThat(state.side()).isEqualTo(ShopThreadSide.CUSTOMER);
            assertThat(state.thread().getOrderId()).isEqualTo(orderId);
            assertThat(state.thread().getOrderKind()).isEqualTo("SERVICE");
        }

        @Test
        @DisplayName("an order Order Manager does not show the customer is refused exactly as an unknown shop")
        void an_order_not_shown_to_them() {
            when(orders.visibleToCaller(orderId)).thenReturn(Optional.empty());

            assertRefusedExactlyAsAnUnknownShop();
        }

        /** Order Manager shows an order to its rider too; being able to see it is not owning it. */
        @Test
        @DisplayName("somebody else's order, even one Order Manager shows the caller, is refused exactly as an unknown shop")
        void somebody_elses_order() {
            when(orders.visibleToCaller(orderId)).thenReturn(Optional.of(openOrder(orderId, STORE, OTHER_CUSTOMER)));

            assertRefusedExactlyAsAnUnknownShop();
        }

        @Test
        @DisplayName("their own order with another shop is refused exactly as an unknown shop")
        void an_order_of_another_shop() {
            when(orders.visibleToCaller(orderId))
                    .thenReturn(Optional.of(openOrder(orderId, OTHER_STORE, CUSTOMER)));

            assertRefusedExactlyAsAnUnknownShop();
        }

        @Test
        @DisplayName("with Order Manager down the linked open is refused cleanly, and an open without an order still works")
        void order_manager_down() {
            when(orders.visibleToCaller(orderId))
                    .thenThrow(new OrderUnavailableException("Orders cannot be checked right now", null));

            assertThatThrownBy(() -> service.openForCustomer(STORE, CUSTOMER, "Tania K.", orderId))
                    .isInstanceOf(OrderUnavailableException.class);
            verify(threads, never()).insertIfAbsent(any(), any(), any(), any(), any(), any());

            ShopChatService.ThreadState unlinked = service.openForCustomer(STORE, CUSTOMER, "Tania K.", null);

            assertThat(unlinked.thread()).isSameAs(thread);
            assertThat(unlinked.thread().getOrderId()).isNull();
            verify(orders, times(1)).visibleToCaller(any());
        }

        @Test
        @DisplayName("opening again from the same order changes nothing, a later order replaces it, and the shop page keeps it")
        void reopening_and_the_latest_order() {
            UUID later = UUID.randomUUID();
            when(orders.visibleToCaller(orderId)).thenReturn(Optional.of(openOrder(orderId, STORE, CUSTOMER)));
            when(orders.visibleToCaller(later)).thenReturn(Optional.of(new OrderReference(later, STORE,
                    "Abu Hassan Print", CUSTOMER, "CATALOG", "PLACED", null, null, null)));

            ShopChatService.ThreadState first = service.openForCustomer(STORE, CUSTOMER, "Tania K.", orderId);
            ShopChatService.ThreadState again = service.openForCustomer(STORE, CUSTOMER, "Tania K.", orderId);

            assertThat(again.thread()).isSameAs(first.thread());
            assertThat(again.thread().getOrderId()).isEqualTo(orderId);

            service.openForCustomer(STORE, CUSTOMER, "Tania K.", later);
            assertThat(thread.getOrderId()).isEqualTo(later);
            assertThat(thread.getOrderKind()).isEqualTo("CATALOG");

            service.openForCustomer(STORE, CUSTOMER, "Tania K.", null);
            assertThat(thread.getOrderId()).as("an open without an order confirms nothing new").isEqualTo(later);
        }

        /** The same exception with the same message, and nothing written, as a shop that is not there. */
        private void assertRefusedExactlyAsAnUnknownShop() {
            Throwable fromTheOrder = catchThrowable(
                    () -> service.openForCustomer(STORE, CUSTOMER, "Tania K.", orderId));
            when(directory.storefront(STORE)).thenReturn(Optional.empty());
            Throwable fromAnUnknownShop = catchThrowable(
                    () -> service.openForCustomer(STORE, CUSTOMER, "Tania K.", null));

            assertThat(fromAnUnknownShop).isInstanceOf(RoomNotFoundException.class);
            assertThat(fromTheOrder).isInstanceOf(RoomNotFoundException.class)
                    .hasMessage(fromAnUnknownShop.getMessage());
            verify(threads, never()).insertIfAbsent(any(), any(), any(), any(), any(), any());
            assertThat(thread.getOrderId()).isNull();
        }
    }

    @Nested
    @DisplayName("a merchant opening the thread for an order")
    class MerchantOpensForAnOrder {

        private final UUID orderId = UUID.randomUUID();

        @BeforeEach
        void theThreadTheOrderLeadsTo() {
            when(threads.findByStoreIdAndCustomerId(STORE, CUSTOMER)).thenReturn(Optional.of(thread));
        }

        @Test
        @DisplayName("opens it with the order's customer, named as the order's card names them, as the shop")
        void opens_from_the_order() {
            when(orders.visibleToCaller(orderId)).thenReturn(Optional.of(openOrder(orderId, STORE, CUSTOMER)));

            ShopChatService.ThreadState state = service.openForOrder(orderId, MERCHANT);

            verify(threads).insertIfAbsent(any(UUID.class), eq(STORE), eq(CUSTOMER), eq("Tania K."),
                    eq("Abu Hassan Print"), any(Instant.class));
            assertThat(state.side()).isEqualTo(ShopThreadSide.SHOP);
            assertThat(state.thread().getOrderId()).isEqualTo(orderId);
            assertThat(state.thread().getOrderKind()).isEqualTo("SERVICE");
        }

        @Test
        @DisplayName("an order Order Manager does not show the merchant is a 404, and opens nothing")
        void an_order_not_shown_to_them() {
            when(orders.visibleToCaller(orderId)).thenReturn(Optional.empty());

            assertThatThrownBy(() -> service.openForOrder(orderId, OTHER_MERCHANT))
                    .isInstanceOf(RoomNotFoundException.class);
            verify(threads, never()).insertIfAbsent(any(), any(), any(), any(), any(), any());
        }

        /** Order Manager shows an order to its customer and rider too; a merchant of another shop may be either. */
        @Test
        @DisplayName("an order of a shop the merchant does not answer for is a 404, even when Order Manager shows it to them")
        void a_merchant_of_another_shop() {
            when(orders.visibleToCaller(orderId)).thenReturn(Optional.of(openOrder(orderId, STORE, CUSTOMER)));

            assertThatThrownBy(() -> service.openForOrder(orderId, OTHER_MERCHANT))
                    .isInstanceOf(RoomNotFoundException.class);
            verify(threads, never()).insertIfAbsent(any(), any(), any(), any(), any(), any());
        }

        @Test
        @DisplayName("an order with no shop is a 404, without asking who owns what")
        void an_errand() {
            when(orders.visibleToCaller(orderId)).thenReturn(Optional.of(openOrder(orderId, null, CUSTOMER)));

            assertThatThrownBy(() -> service.openForOrder(orderId, MERCHANT))
                    .isInstanceOf(RoomNotFoundException.class);
            verifyNoInteractions(ownership);
        }

        @Test
        @DisplayName("while the order is open, the shop may speak for a window from now")
        void an_open_order() {
            when(orders.visibleToCaller(orderId)).thenReturn(Optional.of(openOrder(orderId, STORE, CUSTOMER)));

            ShopChatService.ThreadState state = service.openForOrder(orderId, MERCHANT);

            assertThat(state.thread().getClosesAt())
                    .isCloseTo(Instant.now().plus(Duration.ofDays(7)), within(Duration.ofSeconds(5)));
        }

        @Test
        @DisplayName("six days after delivery a quiet thread opens, until seven days after delivery")
        void within_the_window_after_delivery() {
            Instant delivered = Instant.now().minus(Duration.ofDays(6));
            when(orders.visibleToCaller(orderId)).thenReturn(Optional.of(ended(orderId, "DELIVERED", delivered)));
            ChatShopThread quiet = new ChatShopThread(STORE, CUSTOMER, "Tania K.", "Abu Hassan Print",
                    Instant.now().minus(Duration.ofDays(1)));
            when(threads.findByStoreIdAndCustomerId(STORE, CUSTOMER)).thenReturn(Optional.of(quiet));

            ShopChatService.ThreadState state = service.openForOrder(orderId, MERCHANT);

            assertThat(state.thread()).isSameAs(quiet);
            assertThat(quiet.getClosesAt()).isEqualTo(delivered.plus(Duration.ofDays(7)));
            assertThat(quiet.isOpenAt(Instant.now())).isTrue();
        }

        @Test
        @DisplayName("six days after a cancellation it still opens")
        void within_the_window_after_cancellation() {
            Instant cancelled = Instant.now().minus(Duration.ofDays(6));
            when(orders.visibleToCaller(orderId)).thenReturn(Optional.of(ended(orderId, "CANCELLED", cancelled)));

            assertThat(service.openForOrder(orderId, MERCHANT).thread().getOrderId()).isEqualTo(orderId);
        }

        @Test
        @DisplayName("seven days after delivery or cancellation it is refused with when it closed, and opens nothing")
        void past_the_window() {
            Instant delivered = Instant.now().minus(Duration.ofDays(8));
            when(orders.visibleToCaller(orderId)).thenReturn(Optional.of(ended(orderId, "DELIVERED", delivered)));
            UUID cancelledOrder = UUID.randomUUID();
            Instant cancelled = Instant.now().minus(Duration.ofDays(7)).minusSeconds(60);
            when(orders.visibleToCaller(cancelledOrder))
                    .thenReturn(Optional.of(ended(cancelledOrder, "CANCELLED", cancelled)));

            assertThatThrownBy(() -> service.openForOrder(orderId, MERCHANT))
                    .isInstanceOfSatisfying(OrderChatClosedException.class, refused ->
                            assertThat(refused.getClosedAt()).isEqualTo(delivered.plus(Duration.ofDays(7))));
            assertThatThrownBy(() -> service.openForOrder(cancelledOrder, MERCHANT))
                    .isInstanceOfSatisfying(OrderChatClosedException.class, refused ->
                            assertThat(refused.getClosedAt()).isEqualTo(cancelled.plus(Duration.ofDays(7))));
            verify(threads, never()).insertIfAbsent(any(), any(), any(), any(), any(), any());
            assertThat(thread.getOrderId()).isNull();
        }

        @Test
        @DisplayName("the window is a setting")
        void the_window_is_a_setting() {
            properties.setOrderChatWindow(Duration.ofDays(2));
            Instant delivered = Instant.now().minus(Duration.ofDays(3));
            when(orders.visibleToCaller(orderId)).thenReturn(Optional.of(ended(orderId, "DELIVERED", delivered)));

            assertThatThrownBy(() -> service.openForOrder(orderId, MERCHANT))
                    .isInstanceOf(OrderChatClosedException.class);
        }

        @Test
        @DisplayName("an ended order with no recorded end is refused, not read as open")
        void an_ended_order_without_an_end() {
            when(orders.visibleToCaller(orderId)).thenReturn(Optional.of(new OrderReference(orderId, STORE,
                    "Abu Hassan Print", CUSTOMER, "SERVICE", "DELIVERED", null, null, "Tania K.")));

            assertThatThrownBy(() -> service.openForOrder(orderId, MERCHANT))
                    .isInstanceOf(OrderChatClosedException.class);
            verify(threads, never()).insertIfAbsent(any(), any(), any(), any(), any(), any());
        }

        @Test
        @DisplayName("never keeps the thread open past the customer idle window, and never shortens what the customer keeps open")
        void bounded_both_ways() {
            when(orders.visibleToCaller(orderId)).thenReturn(Optional.of(openOrder(orderId, STORE, CUSTOMER)));
            ChatShopThread quiet = new ChatShopThread(STORE, CUSTOMER, "Tania K.", "Abu Hassan Print",
                    Instant.now().minus(Duration.ofDays(1)));
            when(threads.findByStoreIdAndCustomerId(STORE, CUSTOMER)).thenReturn(Optional.of(quiet));
            properties.setIdleCloseAfter(Duration.ofDays(2));

            service.openForOrder(orderId, MERCHANT);
            assertThat(quiet.getClosesAt())
                    .as("two idle days are shorter than the seven-day order window, so they bound it")
                    .isCloseTo(Instant.now().plus(Duration.ofDays(2)), within(Duration.ofSeconds(5)));

            ChatShopThread busy = new ChatShopThread(STORE, CUSTOMER, "Tania K.", "Abu Hassan Print",
                    Instant.now().plus(Duration.ofDays(14)));
            when(threads.findByStoreIdAndCustomerId(STORE, CUSTOMER)).thenReturn(Optional.of(busy));
            Instant customersOwn = busy.getClosesAt();

            service.openForOrder(orderId, MERCHANT);
            assertThat(busy.getClosesAt()).isEqualTo(customersOwn);
        }

        @Test
        @DisplayName("with Order Manager down it is refused cleanly, and nothing is opened")
        void order_manager_down() {
            when(orders.visibleToCaller(orderId))
                    .thenThrow(new OrderUnavailableException("Orders cannot be checked right now", null));

            assertThatThrownBy(() -> service.openForOrder(orderId, MERCHANT))
                    .isInstanceOf(OrderUnavailableException.class);
            verify(threads, never()).insertIfAbsent(any(), any(), any(), any(), any(), any());
            verifyNoInteractions(ownership);
        }

        @Test
        @DisplayName("opening again is the same thread with the same order")
        void reopening() {
            when(orders.visibleToCaller(orderId)).thenReturn(Optional.of(openOrder(orderId, STORE, CUSTOMER)));

            ShopChatService.ThreadState first = service.openForOrder(orderId, MERCHANT);
            ShopChatService.ThreadState again = service.openForOrder(orderId, MERCHANT);

            assertThat(again.thread()).isSameAs(first.thread());
            assertThat(again.thread().getOrderId()).isEqualTo(orderId);
        }
    }

    @Nested
    @DisplayName("who can read a thread")
    class Reading {

        @Test
        @DisplayName("its customer, as the customer")
        void the_customer() {
            assertThat(service.history(thread.getId(), CUSTOMER, false, 0L).state().side())
                    .isEqualTo(ShopThreadSide.CUSTOMER);
        }

        @Test
        @DisplayName("the shop's confirmed owner, as the shop")
        void the_shops_owner() {
            assertThat(service.history(thread.getId(), MERCHANT, true, 0L).state().side())
                    .isEqualTo(ShopThreadSide.SHOP);
        }

        @Test
        @DisplayName("not another customer, who is told the thread does not exist")
        void not_another_customer() {
            assertThatThrownBy(() -> service.history(thread.getId(), OTHER_CUSTOMER, false, 0L))
                    .isInstanceOf(RoomNotFoundException.class);
            verifyNoInteractions(messages);
        }

        @Test
        @DisplayName("not a merchant of a different shop")
        void not_another_shops_merchant() {
            assertThatThrownBy(() -> service.history(thread.getId(), OTHER_MERCHANT, true, 0L))
                    .isInstanceOf(RoomNotFoundException.class);
            verifyNoInteractions(messages);
        }

        @Test
        @DisplayName("marking read clears what the other side said, for the caller's side")
        void mark_read_is_by_side() {
            service.markRead(thread.getId(), MERCHANT, true, 5L);

            verify(messages).markReadUpTo(eq(thread.getId()), eq(ShopThreadSide.CUSTOMER), eq(5L), any());
        }
    }

    @Nested
    @DisplayName("posting")
    class Posting {

        @Test
        @DisplayName("the customer's message is stored, keeps the thread open longer, and goes to the shop")
        void the_customer_posts() {
            ShopChatService.Posted posted = service.post(thread.getId(), CUSTOMER, false,
                    "Do you have halloumi?", "c-1", null);
            ChatShopMessage message = posted.message();

            assertThat(posted.storeId()).isEqualTo(STORE);

            assertThat(message.getSenderSide()).isEqualTo(ShopThreadSide.CUSTOMER);
            assertThat(message.getSequenceNo()).isEqualTo(1L);
            assertThat(thread.getClosesAt())
                    .isCloseTo(Instant.now().plus(Duration.ofDays(14)), within(Duration.ofSeconds(5)));
            verify(delivery).deliver(message, STORE, CUSTOMER);
        }

        /** Otherwise a shop could keep a private line to a customer open indefinitely. */
        @Test
        @DisplayName("the shop replies as the shop, and its replies do not keep the thread open")
        void the_shop_replies_without_extending() {
            Instant closes = thread.getClosesAt();

            ChatShopMessage reply = service.post(thread.getId(), MERCHANT, true, "Yes, fresh today", null, null)
                    .message();

            assertThat(reply.getSenderSide()).isEqualTo(ShopThreadSide.SHOP);
            assertThat(thread.getClosesAt()).isEqualTo(closes);
        }

        @Test
        @DisplayName("a stranger cannot post, and takes no lock trying")
        void a_stranger_cannot_post() {
            assertThatThrownBy(() -> service.post(thread.getId(), OTHER_CUSTOMER, false, "hi", null, null))
                    .isInstanceOf(RoomNotFoundException.class);
            verify(threads, never()).lockById(any());
            verify(messages, never()).save(any());
        }

        @Test
        @DisplayName("once idle and closed, the shop cannot revive the thread")
        void the_shop_cannot_post_into_a_closed_thread() {
            ChatShopThread idle = new ChatShopThread(STORE, CUSTOMER, "Tania K.", "Abu Hassan Mini Market",
                    Instant.now().minus(Duration.ofDays(1)));
            when(threads.partiesOf(idle.getId())).thenReturn(Optional.of(parties(STORE, CUSTOMER)));
            when(threads.lockById(idle.getId())).thenReturn(Optional.of(idle));

            assertThatThrownBy(() -> service.post(idle.getId(), MERCHANT, true, "Special offer!", null, null))
                    .isInstanceOf(ConversationClosedException.class);
            verify(messages, never()).save(any());
        }

        @Test
        @DisplayName("a retry returns the message already stored")
        void a_retry_is_idempotent() {
            ChatShopMessage stored = new ChatShopMessage(thread.getId(), 1L, CUSTOMER, ShopThreadSide.CUSTOMER,
                    "Do you have halloumi?", "c-1", Instant.now());
            when(messages.findByThreadIdAndSenderIdAndClientMessageId(thread.getId(), CUSTOMER, "c-1"))
                    .thenReturn(Optional.of(stored));

            assertThat(service.post(thread.getId(), CUSTOMER, false, "Do you have halloumi?", "c-1", null)
                    .message()).isSameAs(stored);
            verify(messages, never()).save(any());
        }

        @Test
        @DisplayName("a sender over the rate limit is refused")
        void rate_limited() {
            when(messages.countBySenderIdAndCreatedAtAfter(eq(MERCHANT), any(Instant.class))).thenReturn(20L);

            assertThatThrownBy(() -> service.post(thread.getId(), MERCHANT, true, "hello", null, null))
                    .isInstanceOf(SendRateLimitedException.class);
        }
    }

    @Nested
    @DisplayName("the merchant inbox")
    class Inbox {

        @Test
        @DisplayName("holds threads only for the shops Product Service says the merchant owns")
        void only_owned_shops() {
            when(ownership.storesOf(MERCHANT)).thenReturn(Set.of(STORE));
            when(threads.inboxFor(eq(Set.of(STORE)), any())).thenReturn(List.of(thread));
            ChatShopMessage latest = new ChatShopMessage(thread.getId(), 2L, CUSTOMER, ShopThreadSide.CUSTOMER,
                    "Can you set one aside?", null, Instant.now());
            when(messages.latestIn(List.of(thread.getId()))).thenReturn(List.of(latest));
            when(messages.unreadFrom(List.of(thread.getId()), ShopThreadSide.CUSTOMER))
                    .thenReturn(List.of(tally(thread.getId(), 2L)));

            List<ShopChatService.ThreadState> inbox = service.inbox(MERCHANT);

            assertThat(inbox).hasSize(1);
            assertThat(inbox.get(0).side()).isEqualTo(ShopThreadSide.SHOP);
            assertThat(inbox.get(0).unread()).isEqualTo(2L);
            assertThat(inbox.get(0).latestPreview()).isEqualTo("Can you set one aside?");
        }

        @Test
        @DisplayName("is empty, without a query, for a merchant who owns no shop")
        void empty_for_no_shops() {
            when(ownership.storesOf(MERCHANT)).thenReturn(Set.of());

            assertThat(service.inbox(MERCHANT)).isEmpty();
            verify(threads, never()).inboxFor(any(), any());
        }
    }

    /** A service order in production: open, placed with {@code storeId} by {@code customerId}. */
    private static OrderReference openOrder(UUID id, UUID storeId, String customerId) {
        return new OrderReference(id, storeId, "Abu Hassan Print", customerId, "SERVICE", "PREPARING",
                null, null, "Tania K.");
    }

    /** This shop's customer's service order, delivered or cancelled at {@code at}. */
    private static OrderReference ended(UUID id, String status, Instant at) {
        return new OrderReference(id, STORE, "Abu Hassan Print", CUSTOMER, "SERVICE", status,
                "DELIVERED".equals(status) ? at : null, "CANCELLED".equals(status) ? at : null, "Tania K.");
    }

    private static ChatShopThreadRepository.Parties parties(UUID storeId, String customerId) {
        return new ChatShopThreadRepository.Parties() {
            @Override
            public UUID getStoreId() {
                return storeId;
            }

            @Override
            public String getCustomerId() {
                return customerId;
            }
        };
    }

    private static ChatShopMessageRepository.UnreadTally tally(UUID threadId, long unread) {
        return new ChatShopMessageRepository.UnreadTally() {
            @Override
            public UUID getThreadId() {
                return threadId;
            }

            @Override
            public long getUnread() {
                return unread;
            }
        };
    }
}
