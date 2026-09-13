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

import com.delivery.appnotification.client.ProductDirectory;
import com.delivery.appnotification.domain.ChatShopMessage;
import com.delivery.appnotification.domain.ChatShopMessageRepository;
import com.delivery.appnotification.domain.ChatShopThread;
import com.delivery.appnotification.domain.ChatShopThreadRepository;
import com.delivery.appnotification.domain.ShopThreadSide;
import com.delivery.appnotification.service.RoomExceptions.RoomNotFoundException;
import com.delivery.appnotification.service.RoomExceptions.SendRateLimitedException;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.assertj.core.api.Assertions.within;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

/**
 * A customer's conversation with a shop: exactly that customer on one side, exactly the shop's
 * confirmed owner on the other, and a line that goes quiet when the customer does.
 */
class ShopChatServiceTest {

    private static final UUID STORE = UUID.randomUUID();
    private static final String CUSTOMER = "customer-sub";
    private static final String OTHER_CUSTOMER = "other-customer-sub";
    private static final String MERCHANT = "merchant-sub";
    private static final String OTHER_MERCHANT = "other-shop-merchant-sub";

    private ChatShopThreadRepository threads;
    private ChatShopMessageRepository messages;
    private ProductDirectory directory;
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
        ownership = mock(ShopOwnership.class);
        delivery = mock(ShopDelivery.class);
        properties = new ShopChatProperties();
        service = new ShopChatService(threads, messages, directory, ownership, delivery, properties,
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

            ShopChatService.ThreadState state = service.openForCustomer(STORE, CUSTOMER, "Tania K.");

            assertThat(state.thread()).isSameAs(thread);
            assertThat(state.side()).isEqualTo(ShopThreadSide.CUSTOMER);
            verify(threads).insertIfAbsent(any(UUID.class), eq(STORE), eq(CUSTOMER), eq("Tania K."),
                    eq("Abu Hassan Mini Market"), any(Instant.class));
        }

        @Test
        @DisplayName("opening it again is the same conversation, with its idle clock restarted")
        void opening_again_is_the_same_thread() {
            when(directory.storefront(STORE))
                    .thenReturn(Optional.of(new ProductDirectory.Storefront(STORE, "Abu Hassan Mini Market")));
            when(threads.findByStoreIdAndCustomerId(STORE, CUSTOMER)).thenReturn(Optional.of(thread));

            service.openForCustomer(STORE, CUSTOMER, "Tania K.");
            ShopChatService.ThreadState again = service.openForCustomer(STORE, CUSTOMER, "Tania K.");

            assertThat(again.thread()).isSameAs(thread);
            assertThat(thread.getClosesAt())
                    .isCloseTo(Instant.now().plus(Duration.ofDays(14)), within(Duration.ofSeconds(5)));
        }

        @Test
        @DisplayName("a shop the customer cannot see has no conversation to open")
        void an_invisible_shop_has_no_thread() {
            when(directory.storefront(STORE)).thenReturn(Optional.empty());

            assertThatThrownBy(() -> service.openForCustomer(STORE, CUSTOMER, "Tania K."))
                    .isInstanceOf(RoomNotFoundException.class);
            verify(threads, never()).insertIfAbsent(any(), any(), any(), any(), any(), any());
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
