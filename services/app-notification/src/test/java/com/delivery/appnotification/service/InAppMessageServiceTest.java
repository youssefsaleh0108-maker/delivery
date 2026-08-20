package com.delivery.appnotification.service;

import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.data.domain.Pageable;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

import com.delivery.appnotification.domain.InAppMessage;
import com.delivery.appnotification.domain.InAppMessageRepository;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * The in-app inbox: the row is the delivery, the WebSocket frame only saves a poll.
 *
 * <p>That ordering is the whole design and it is worth pinning, because the tempting version —
 * push first, it feels faster — puts a message on screen that vanishes on refresh if the commit
 * then fails. Persist-then-push means a failed frame costs latency, not a notification, and lets
 * the REST fallback be a genuine fallback rather than a second, divergent path.
 */
class InAppMessageServiceTest {

    private static final UUID NOTIFICATION = UUID.randomUUID();
    private static final UUID ORDER = UUID.randomUUID();
    private static final String USER = "customer-sub";

    private InAppMessageRepository messages;
    private SimpMessagingTemplate websocket;
    private InAppMessageService service;

    @BeforeEach
    void setUp() {
        messages = mock(InAppMessageRepository.class);
        websocket = mock(SimpMessagingTemplate.class);
        service = new InAppMessageService(messages, websocket);

        when(messages.existsByNotificationId(any(UUID.class))).thenReturn(false);
        when(messages.save(any(InAppMessage.class))).thenAnswer(call -> call.getArgument(0));
    }

    @AfterEach
    void tearDown() {
        if (TransactionSynchronizationManager.isSynchronizationActive()) {
            TransactionSynchronizationManager.clearSynchronization();
        }
    }

    private static void commit() {
        List.copyOf(TransactionSynchronizationManager.getSynchronizations())
                .forEach(TransactionSynchronization::afterCommit);
    }

    private boolean record() {
        return service.record(NOTIFICATION, USER, ORDER, "order.status_changed",
                "On its way", "Your order has left the shop", Map.of("orderId", ORDER.toString()));
    }

    @Nested
    @DisplayName("recording a message")
    class Recording {

        @Test
        void persists_it_and_reports_that_it_was_new() {
            assertThat(record()).isTrue();

            verify(messages).save(any(InAppMessage.class));
        }

        /** Bus delivery is at-least-once; one status change must not fill an inbox with copies. */
        @Test
        void a_redelivery_is_ignored_rather_than_duplicated() {
            when(messages.existsByNotificationId(NOTIFICATION)).thenReturn(true);

            assertThat(record()).isFalse();

            verify(messages, never()).save(any(InAppMessage.class));
            verify(websocket, never()).convertAndSendToUser(anyString(), anyString(), any());
        }

        /** Deduped on the notification id, which is the platform-wide key for one notification. */
        @Test
        void the_dedupe_key_is_the_notification_id() {
            record();

            verify(messages).existsByNotificationId(NOTIFICATION);
        }
    }

    @Nested
    @DisplayName("pushing over the WebSocket")
    class Pushing {

        @Test
        void happens_only_after_the_row_is_committed() {
            TransactionSynchronizationManager.initSynchronization();

            record();
            verify(websocket, never()).convertAndSendToUser(anyString(), anyString(), any());

            commit();
            verify(websocket).convertAndSendToUser(eq(USER), anyString(), any());
        }

        /** A caller outside a transaction still gets the frame, rather than silently nothing. */
        @Test
        void happens_immediately_when_there_is_no_transaction_to_wait_for() {
            record();

            verify(websocket).convertAndSendToUser(eq(USER), anyString(), any());
        }

        /** Addressed to the owner, on the destination the clients subscribe to. */
        @Test
        void goes_to_the_owning_user_on_the_agreed_destination() {
            record();

            verify(websocket).convertAndSendToUser(eq(USER),
                    eq(InAppMessageService.USER_DESTINATION), any());
        }

        /**
         * The frame is an optimisation. Losing it costs a poll interval, not a notification, which
         * is exactly what persist-then-push buys.
         */
        @Test
        void a_failed_push_does_not_undo_the_recorded_message() {
            doThrow(new IllegalStateException("no session"))
                    .when(websocket).convertAndSendToUser(anyString(), anyString(), any());

            assertThat(record()).isTrue();

            verify(messages).save(any(InAppMessage.class));
        }

        /** An order-less message — an account notice — must not blow up building the payload. */
        @Test
        void a_message_with_no_order_still_pushes() {
            assertThat(service.record(NOTIFICATION, USER, null, "account.updated",
                    "Updated", "Your details changed", Map.of())).isTrue();

            verify(websocket).convertAndSendToUser(eq(USER), anyString(), any());
        }
    }

    @Nested
    @DisplayName("reading the inbox")
    class Inbox {

        @Test
        void returns_the_users_own_messages_newest_first() {
            when(messages.findByUserIdOrderByCreatedAtDesc(eq(USER), any(Pageable.class)))
                    .thenReturn(List.of());

            service.inbox(USER, 20);

            verify(messages).findByUserIdOrderByCreatedAtDesc(eq(USER), any(Pageable.class));
        }

        @Test
        void the_unread_count_is_scoped_to_the_user() {
            when(messages.countByUserIdAndReadAtIsNull(USER)).thenReturn(3L);

            assertThat(service.unreadCount(USER)).isEqualTo(3L);
        }
    }

    @Nested
    @DisplayName("marking read")
    class MarkingRead {

        private InAppMessage owned() {
            return new InAppMessage(USER, NOTIFICATION, ORDER, "order.status_changed",
                    "t", "b", Map.of());
        }

        @Test
        void marks_the_users_own_message() {
            InAppMessage message = owned();
            when(messages.findByIdAndUserId(any(UUID.class), eq(USER)))
                    .thenReturn(Optional.of(message));

            assertThat(service.markRead(message.getId(), USER)).isTrue();
            assertThat(message.getReadAt()).isNotNull();
        }

        /**
         * The lookup is scoped by user, so somebody else's message id is indistinguishable from one
         * that does not exist — which is what stops this being a way to probe for ids.
         */
        @Test
        void another_users_message_is_indistinguishable_from_a_missing_one() {
            when(messages.findByIdAndUserId(any(UUID.class), anyString()))
                    .thenReturn(Optional.empty());

            assertThat(service.markRead(UUID.randomUUID(), "someone-else")).isFalse();
        }

        @Test
        void marking_all_read_is_scoped_to_the_user() {
            when(messages.markAllRead(USER)).thenReturn(4);

            assertThat(service.markAllRead(USER)).isEqualTo(4);
            verify(messages).markAllRead(USER);
        }
    }
}
