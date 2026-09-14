package com.delivery.appnotification.service;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.transaction.annotation.Transactional;

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

    /** The service's "now" unless a test moves it; every instant in these tests is counted from it. */
    private static final Instant NOW = Instant.parse("2026-09-15T09:00:00Z");
    /** The order chat window's default. */
    private static final Duration WEEK = Duration.ofDays(7);

    private ChatShopThreadRepository threads;
    private ChatShopMessageRepository messages;
    private ProductDirectory directory;
    private OrderReferences orders;
    private ShopOwnership ownership;
    private ShopDelivery delivery;
    private ShopChatProperties properties;
    private TransactionsWithoutADatabase transactions;
    private MovableClock clock;
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
        transactions = new TransactionsWithoutADatabase();
        clock = new MovableClock(NOW);
        service = new ShopChatService(threads, messages, directory, orders, ownership, delivery, properties,
                new ChatProperties(), transactions, clock);

        thread = new ChatShopThread(STORE, CUSTOMER, "Tania K.", "Abu Hassan Mini Market",
                NOW.plus(Duration.ofDays(3)));
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
            when(threads.lockByStoreIdAndCustomerId(STORE, CUSTOMER)).thenReturn(Optional.of(thread));

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
            when(threads.lockByStoreIdAndCustomerId(STORE, CUSTOMER)).thenReturn(Optional.of(thread));

            service.openForCustomer(STORE, CUSTOMER, "Tania K.", null);
            ShopChatService.ThreadState again = service.openForCustomer(STORE, CUSTOMER, "Tania K.", null);

            assertThat(again.thread()).isSameAs(thread);
            assertThat(thread.getClosesAt()).isEqualTo(NOW.plus(Duration.ofDays(14)));
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
            when(threads.lockByStoreIdAndCustomerId(STORE, CUSTOMER)).thenReturn(Optional.of(thread));
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
                    "Abu Hassan Print", CUSTOMER, "CATALOG", "PLACED", NOW.minus(Duration.ofHours(1)), null,
                    null, null, null)));

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
            when(threads.lockByStoreIdAndCustomerId(STORE, CUSTOMER)).thenReturn(Optional.of(thread));
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
        @DisplayName("six days after an on-time delivery a quiet thread opens, until seven days after delivery")
        void within_the_window_after_delivery() {
            Instant delivered = NOW.minus(Duration.ofDays(6));
            when(orders.visibleToCaller(orderId)).thenReturn(Optional.of(ended(orderId, "DELIVERED", delivered)));
            ChatShopThread quiet = new ChatShopThread(STORE, CUSTOMER, "Tania K.", "Abu Hassan Print",
                    NOW.minus(Duration.ofDays(1)));
            when(threads.lockByStoreIdAndCustomerId(STORE, CUSTOMER)).thenReturn(Optional.of(quiet));

            ShopChatService.ThreadState state = service.openForOrder(orderId, MERCHANT);

            assertThat(state.thread()).isSameAs(quiet);
            assertThat(quiet.getClosesAt()).isEqualTo(delivered.plus(WEEK));
            assertThat(quiet.isOpenAt(NOW)).isTrue();
        }

        @Test
        @DisplayName("six days after a cancellation it still opens")
        void within_the_window_after_cancellation() {
            Instant cancelled = NOW.minus(Duration.ofDays(6));
            when(orders.visibleToCaller(orderId)).thenReturn(Optional.of(ended(orderId, "CANCELLED", cancelled)));

            assertThat(service.openForOrder(orderId, MERCHANT).thread().getOrderId()).isEqualTo(orderId);
        }

        @Test
        @DisplayName("seven days after delivery or cancellation it is refused with when it closed, and opens nothing")
        void past_the_window() {
            Instant delivered = NOW.minus(Duration.ofDays(8));
            when(orders.visibleToCaller(orderId)).thenReturn(Optional.of(ended(orderId, "DELIVERED", delivered)));
            UUID cancelledOrder = UUID.randomUUID();
            Instant cancelled = NOW.minus(WEEK).minusSeconds(60);
            when(orders.visibleToCaller(cancelledOrder))
                    .thenReturn(Optional.of(ended(cancelledOrder, "CANCELLED", cancelled)));

            assertThatThrownBy(() -> service.openForOrder(orderId, MERCHANT))
                    .isInstanceOfSatisfying(OrderChatClosedException.class, refused ->
                            assertThat(refused.getClosedAt()).isEqualTo(delivered.plus(WEEK)));
            assertThatThrownBy(() -> service.openForOrder(cancelledOrder, MERCHANT))
                    .isInstanceOfSatisfying(OrderChatClosedException.class, refused ->
                            assertThat(refused.getClosedAt()).isEqualTo(cancelled.plus(WEEK)));
            verify(threads, never()).insertIfAbsent(any(), any(), any(), any(), any(), any());
            assertThat(thread.getOrderId()).isNull();
        }

        @Test
        @DisplayName("the window is a setting")
        void the_window_is_a_setting() {
            properties.setOrderChatWindow(Duration.ofDays(2));
            Instant delivered = NOW.minus(Duration.ofDays(3));
            when(orders.visibleToCaller(orderId)).thenReturn(Optional.of(ended(orderId, "DELIVERED", delivered)));

            assertThatThrownBy(() -> service.openForOrder(orderId, MERCHANT))
                    .isInstanceOf(OrderChatClosedException.class);
        }

        @Test
        @DisplayName("an ended order with no recorded end is refused, not read as open")
        void an_ended_order_without_an_end() {
            when(orders.visibleToCaller(orderId)).thenReturn(Optional.of(new OrderReference(orderId, STORE,
                    "Abu Hassan Print", CUSTOMER, "SERVICE", "DELIVERED", NOW.minus(Duration.ofDays(3)),
                    NOW.minus(Duration.ofDays(1)), null, null, "Tania K.")));

            assertThatThrownBy(() -> service.openForOrder(orderId, MERCHANT))
                    .isInstanceOf(OrderChatClosedException.class);
            verify(threads, never()).insertIfAbsent(any(), any(), any(), any(), any(), any());
        }

        @Test
        @DisplayName("never keeps the thread open past the customer idle window, and never shortens what the customer keeps open")
        void bounded_both_ways() {
            when(orders.visibleToCaller(orderId)).thenReturn(Optional.of(openOrder(orderId, STORE, CUSTOMER)));
            ChatShopThread quiet = new ChatShopThread(STORE, CUSTOMER, "Tania K.", "Abu Hassan Print",
                    NOW.minus(Duration.ofDays(1)));
            when(threads.lockByStoreIdAndCustomerId(STORE, CUSTOMER)).thenReturn(Optional.of(quiet));
            properties.setIdleCloseAfter(Duration.ofDays(2));

            service.openForOrder(orderId, MERCHANT);
            assertThat(quiet.getClosesAt())
                    .as("two idle days are shorter than the seven-day order window, so they bound it")
                    .isEqualTo(NOW.plus(Duration.ofDays(2)));

            ChatShopThread busy = new ChatShopThread(STORE, CUSTOMER, "Tania K.", "Abu Hassan Print",
                    NOW.plus(Duration.ofDays(14)));
            when(threads.lockByStoreIdAndCustomerId(STORE, CUSTOMER)).thenReturn(Optional.of(busy));
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

    /**
     * The window runs from facts the shop cannot stretch: the earlier of when the order ended (now,
     * while it has not) and when it was due. Each edge is pinned a second before it and on it.
     */
    @Nested
    @DisplayName("how long a shop may open the thread for an order")
    class OrderWindow {

        private final Instant placed = NOW.minus(Duration.ofDays(30));
        private final Instant due = placed.plus(Duration.ofDays(3));

        @Test
        @DisplayName("an open order before its due time: a week from now, which stops moving once it falls due")
        void an_open_order_before_it_is_due() {
            OrderReference preparing = serviceOrder("PREPARING", null);

            opensUntil(preparing, due.minusSeconds(1), due.minusSeconds(1).plus(WEEK));
            opensUntil(preparing, due, due.plus(WEEK));
            opensUntil(preparing, due.plusSeconds(1), due.plus(WEEK));
        }

        /** Nothing expires an order and its customer can no longer cancel it: what the due time is for. */
        @Test
        @DisplayName("an order left READY long after it was due: a week after it was due, however often the shop opens it")
        void an_order_stuck_after_it_was_due() {
            OrderReference ready = serviceOrder("READY", null);

            opensUntil(ready, due.plus(Duration.ofDays(2)), due.plus(WEEK));
            opensUntil(ready, due.plus(WEEK).minusSeconds(1), due.plus(WEEK));
            refusedClosedAt(ready, due.plus(WEEK), due.plus(WEEK));
        }

        @Test
        @DisplayName("an order delivered late: a week after it was due, not a week after it was delivered")
        void an_order_completed_late() {
            OrderReference late = serviceOrder("DELIVERED", due.plus(Duration.ofDays(4)));

            opensUntil(late, due.plus(WEEK).minusSeconds(1), due.plus(WEEK));
            refusedClosedAt(late, due.plus(WEEK), due.plus(WEEK));
        }

        @Test
        @DisplayName("an order delivered early: a week after it was delivered")
        void an_order_completed_early() {
            Instant delivered = due.minus(Duration.ofDays(2));
            OrderReference early = serviceOrder("DELIVERED", delivered);

            opensUntil(early, delivered.plus(WEEK).minusSeconds(1), delivered.plus(WEEK));
            refusedClosedAt(early, delivered.plus(WEEK), delivered.plus(WEEK));
        }

        @Test
        @DisplayName("a goods order, which promises no ready time: a week after it was placed, open or delivered")
        void a_goods_order_without_an_estimate() {
            OrderReference preparing = goodsOrder("PREPARING", null);
            OrderReference delivered = goodsOrder("DELIVERED", placed.plus(Duration.ofDays(1)));

            for (OrderReference goods : List.of(preparing, delivered)) {
                opensUntil(goods, placed.plus(WEEK).minusSeconds(1), placed.plus(WEEK));
                refusedClosedAt(goods, placed.plus(WEEK), placed.plus(WEEK));
            }
        }

        /** At {@code moment} the shop may open it, and a quiet thread then accepts messages until {@code until}. */
        private void opensUntil(OrderReference order, Instant moment, Instant until) {
            clock.set(moment);
            ChatShopThread quiet = new ChatShopThread(STORE, CUSTOMER, "Tania K.", "Abu Hassan Print", placed);
            when(threads.lockByStoreIdAndCustomerId(STORE, CUSTOMER)).thenReturn(Optional.of(quiet));
            when(orders.visibleToCaller(order.id())).thenReturn(Optional.of(order));

            service.openForOrder(order.id(), MERCHANT);

            assertThat(quiet.getClosesAt()).as("opened at %s", moment).isEqualTo(until);
        }

        /** At {@code moment} the shop may not, and is told the chat closed at {@code closedAt}. */
        private void refusedClosedAt(OrderReference order, Instant moment, Instant closedAt) {
            clock.set(moment);
            when(orders.visibleToCaller(order.id())).thenReturn(Optional.of(order));

            assertThatThrownBy(() -> service.openForOrder(order.id(), MERCHANT))
                    .as("opened at %s", moment)
                    .isInstanceOfSatisfying(OrderChatClosedException.class, refused ->
                            assertThat(refused.getClosedAt()).isEqualTo(closedAt));
        }

        /** A service order of this shop, promised for {@code due}, delivered at {@code deliveredAt} if it was. */
        private OrderReference serviceOrder(String status, Instant deliveredAt) {
            return new OrderReference(UUID.randomUUID(), STORE, "Abu Hassan Print", CUSTOMER, "SERVICE", status,
                    placed, due, deliveredAt, null, "Tania K.");
        }

        /** A goods order of this shop; Order Manager promises no ready time for one. */
        private OrderReference goodsOrder(String status, Instant deliveredAt) {
            return new OrderReference(UUID.randomUUID(), STORE, "Abu Hassan Print", CUSTOMER, "CATALOG", status,
                    placed, null, deliveredAt, null, "Tania K.");
        }
    }

    /**
     * Each open reads other services, then changes the thread. A transaction around those reads would
     * hold a pooled connection for as long as the slowest took to answer, and a change made without the
     * row lock would fail on the version another open, or a post, had just written.
     */
    @Nested
    @DisplayName("what an open holds while it works")
    class WhatAnOpenHolds {

        private final List<String> calls = new ArrayList<>();

        @BeforeEach
        void recordWhereTheThreadIsTouched() {
            when(threads.insertIfAbsent(any(), any(), any(), any(), any(), any())).thenAnswer(call -> {
                calls.add(TransactionsWithoutADatabase.where("the upsert"));
                return 0;
            });
            when(threads.lockByStoreIdAndCustomerId(STORE, CUSTOMER)).thenAnswer(call -> {
                calls.add(TransactionsWithoutADatabase.where("the row lock"));
                return Optional.of(thread);
            });
        }

        @Test
        @DisplayName("a customer's open asks Product Service and Order Manager outside a transaction, then locks the thread in one")
        void a_customer_open() {
            UUID orderId = UUID.randomUUID();
            when(directory.storefront(STORE)).thenAnswer(call -> {
                calls.add(TransactionsWithoutADatabase.where("Product Service"));
                return Optional.of(new ProductDirectory.Storefront(STORE, "Abu Hassan Print"));
            });
            when(orders.visibleToCaller(orderId)).thenAnswer(call -> {
                calls.add(TransactionsWithoutADatabase.where("Order Manager"));
                return Optional.of(openOrder(orderId, STORE, CUSTOMER));
            });

            service.openForCustomer(STORE, CUSTOMER, "Tania K.", orderId);

            assertThat(calls).containsExactly(
                    "Product Service outside a transaction",
                    "Order Manager outside a transaction",
                    "the upsert inside a transaction",
                    "the row lock inside a transaction");
            assertThat(transactions.begun()).isEqualTo(1);
        }

        @Test
        @DisplayName("a merchant's open asks Order Manager and who owns the shop outside a transaction, then locks the thread in one")
        void a_merchant_open() {
            UUID orderId = UUID.randomUUID();
            when(orders.visibleToCaller(orderId)).thenAnswer(call -> {
                calls.add(TransactionsWithoutADatabase.where("Order Manager"));
                return Optional.of(openOrder(orderId, STORE, CUSTOMER));
            });
            when(ownership.owns(MERCHANT, STORE)).thenAnswer(call -> {
                calls.add(TransactionsWithoutADatabase.where("the ownership check"));
                return true;
            });

            service.openForOrder(orderId, MERCHANT);

            assertThat(calls).containsExactly(
                    "Order Manager outside a transaction",
                    "the ownership check outside a transaction",
                    "the upsert inside a transaction",
                    "the row lock inside a transaction");
            assertThat(transactions.begun()).isEqualTo(1);
        }

        @Test
        @DisplayName("an open its checks refuse begins no transaction at all")
        void a_refused_open_begins_nothing() {
            UUID orderId = UUID.randomUUID();
            when(orders.visibleToCaller(orderId))
                    .thenReturn(Optional.of(ended(orderId, "DELIVERED", NOW.minus(Duration.ofDays(8)))));

            assertThatThrownBy(() -> service.openForOrder(orderId, MERCHANT))
                    .isInstanceOf(OrderChatClosedException.class);
            assertThat(transactions.begun()).isZero();
            assertThat(calls).isEmpty();
        }

        /** The recording above cannot see an annotation, and its proxy would begin the transaction first. */
        @Test
        @DisplayName("neither open is declared transactional, so no transaction can wrap its reads")
        void the_opens_are_not_declared_transactional() throws NoSuchMethodException {
            assertThat(ShopChatService.class.getAnnotation(Transactional.class)).isNull();
            assertThat(ShopChatService.class
                    .getMethod("openForCustomer", UUID.class, String.class, String.class, UUID.class)
                    .getAnnotation(Transactional.class)).isNull();
            assertThat(ShopChatService.class.getMethod("openForOrder", UUID.class, String.class)
                    .getAnnotation(Transactional.class)).isNull();
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
            assertThat(thread.getClosesAt()).isEqualTo(NOW.plus(Duration.ofDays(14)));
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
                    NOW.minus(Duration.ofDays(1)));
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
                    "Do you have halloumi?", "c-1", NOW);
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
                    "Can you set one aside?", null, NOW);
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

    /** A service order in production, placed yesterday and promised in two days: open, with {@code storeId}, by {@code customerId}. */
    private static OrderReference openOrder(UUID id, UUID storeId, String customerId) {
        return new OrderReference(id, storeId, "Abu Hassan Print", customerId, "SERVICE", "PREPARING",
                NOW.minus(Duration.ofDays(1)), NOW.plus(Duration.ofDays(2)), null, null, "Tania K.");
    }

    /** This shop's customer's service order, delivered or cancelled at {@code at}, which is when it was due. */
    private static OrderReference ended(UUID id, String status, Instant at) {
        return new OrderReference(id, STORE, "Abu Hassan Print", CUSTOMER, "SERVICE", status,
                at.minus(Duration.ofDays(3)), at,
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

    /** A clock a test sets to the exact moment it is about. */
    private static final class MovableClock extends Clock {
        private Instant now;

        MovableClock(Instant now) {
            this.now = now;
        }

        void set(Instant moment) {
            now = moment;
        }

        @Override
        public ZoneId getZone() {
            return ZoneOffset.UTC;
        }

        @Override
        public Clock withZone(ZoneId zone) {
            return this;
        }

        @Override
        public Instant instant() {
            return now;
        }
    }
}
