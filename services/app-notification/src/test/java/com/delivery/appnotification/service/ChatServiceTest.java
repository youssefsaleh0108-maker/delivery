package com.delivery.appnotification.service;

import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.InOrder;
import org.springframework.data.domain.Pageable;

import com.delivery.appnotification.domain.ChatConversation;
import com.delivery.appnotification.domain.ChatConversationRepository;
import com.delivery.appnotification.domain.ChatMessage;
import com.delivery.appnotification.domain.ChatMessageRepository;
import com.delivery.appnotification.domain.ChatParticipantRole;
import com.delivery.appnotification.domain.TranscriptAccess;
import com.delivery.appnotification.domain.TranscriptAccessRepository;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.inOrder;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Order chat: two people, a window of time, and nobody else.
 *
 * <p>Almost everything below is a statement about who is allowed to see or say something, because
 * that is what this feature mostly is. The rest — the sequence numbers, the cursor, the refusal to
 * truncate — exists so that a phone which loses signal halfway through a delivery ends up with the
 * same conversation as one that did not.
 */
class ChatServiceTest {

    private static final UUID ORDER = UUID.randomUUID();
    private static final String CUSTOMER = "customer-sub";
    private static final String RIDER = "rider-sub";
    /** Another perfectly legitimate rider, on somebody else's order. */
    private static final String STRANGER = "other-rider-sub";

    private ChatConversationRepository conversations;
    private ChatMessageRepository messages;
    private TranscriptAccessRepository transcriptAccess;
    private ChatDelivery delivery;
    private ChatProperties properties;
    private ChatService service;

    private ChatConversation conversation;

    @BeforeEach
    void setUp() {
        conversations = mock(ChatConversationRepository.class);
        messages = mock(ChatMessageRepository.class);
        transcriptAccess = mock(TranscriptAccessRepository.class);
        delivery = mock(ChatDelivery.class);
        properties = new ChatProperties();
        service = new ChatService(conversations, messages, transcriptAccess, delivery, properties);

        conversation = new ChatConversation(ORDER, CUSTOMER, RIDER);

        when(conversations.lockById(conversation.getId())).thenReturn(Optional.of(conversation));
        when(conversations.findById(conversation.getId())).thenReturn(Optional.of(conversation));
        when(conversations.findLiveByOrderId(ORDER)).thenReturn(Optional.of(conversation));
        when(messages.save(any(ChatMessage.class))).thenAnswer(call -> call.getArgument(0));
        when(messages.findByConversationIdAndClientMessageId(any(UUID.class), anyString()))
                .thenReturn(Optional.empty());
    }

    private ChatMessage post(String sender, String text) {
        return service.post(conversation.getId(), sender, text, null, "corr-1");
    }

    /**
     * A real implementation rather than a mock, because the projection is only two getters and
     * because building a mock inside the argument list of another {@code when(...)} is the classic
     * way to get Mockito's "unfinished stubbing" error rather than the test you meant to write.
     */
    private static ChatMessageRepository.UnreadTally tally(UUID conversationId, long unread) {
        return new ChatMessageRepository.UnreadTally() {
            @Override
            public UUID getConversationId() {
                return conversationId;
            }

            @Override
            public long getUnread() {
                return unread;
            }
        };
    }

    @Nested
    @DisplayName("posting a message")
    class Posting {

        @Test
        @DisplayName("stores what the sender typed and hands it to the other participant")
        void stores_it_and_addresses_it_to_the_counterpart() {
            ChatMessage message = post(CUSTOMER, "I'm at the gate");

            assertThat(message.getBody()).isEqualTo("I'm at the gate");
            assertThat(message.getSenderRole()).isEqualTo(ChatParticipantRole.CUSTOMER);

            ArgumentCaptor<ChatDelivery.Deliverable> sent =
                    ArgumentCaptor.forClass(ChatDelivery.Deliverable.class);
            verify(delivery).deliver(sent.capture());
            assertThat(sent.getValue().recipientId()).isEqualTo(RIDER);
            assertThat(sent.getValue().recipientRole()).isEqualTo(ChatParticipantRole.RIDER);
        }

        /** The cursor a reconnecting client asks from has to come from somewhere. */
        @Test
        @DisplayName("numbers messages consecutively within the conversation")
        void numbers_messages_within_the_conversation() {
            assertThat(post(CUSTOMER, "first").getSequenceNo()).isEqualTo(1L);
            assertThat(post(RIDER, "second").getSequenceNo()).isEqualTo(2L);
        }

        /**
         * A phone that loses signal mid-POST retries, and the customer must not end up having said
         * it twice.
         */
        @Test
        @DisplayName("a retry carrying the same client id returns the first message instead of posting a second")
        void a_retry_with_the_same_client_id_does_not_post_twice() {
            ChatMessage first = service.post(conversation.getId(), CUSTOMER, "on my way", "abc", null);
            when(messages.findByConversationIdAndClientMessageId(conversation.getId(), "abc"))
                    .thenReturn(Optional.of(first));

            ChatMessage retry = service.post(conversation.getId(), CUSTOMER, "on my way", "abc", null);

            assertThat(retry).isSameAs(first);
            verify(messages).save(any(ChatMessage.class));
        }

        @Test
        @DisplayName("records which side said it, so the thread can be drawn without exposing user ids")
        void records_the_senders_role() {
            assertThat(post(RIDER, "outside").getSenderRole()).isEqualTo(ChatParticipantRole.RIDER);
        }
    }

    @Nested
    @DisplayName("somebody who is not in the conversation")
    class ThirdParty {

        @Test
        @DisplayName("cannot post to it, and is told only that there is no such conversation")
        void cannot_post() {
            assertThatThrownBy(() -> post(STRANGER, "hello"))
                    .isInstanceOf(ConversationNotFoundException.class);

            verify(messages, never()).save(any(ChatMessage.class));
            verify(delivery, never()).deliver(any());
        }

        @Test
        @DisplayName("cannot read it, and is told only that there is no such conversation")
        void cannot_read() {
            assertThatThrownBy(() -> service.thread(conversation.getId(), STRANGER, 0L))
                    .isInstanceOf(ConversationNotFoundException.class);

            verify(messages, never())
                    .findByConversationIdAndSequenceNoGreaterThanOrderBySequenceNoAsc(
                            any(UUID.class), anyLong(), any(Pageable.class));
        }

        @Test
        @DisplayName("cannot mark it read, so it cannot clear somebody else's badge")
        void cannot_mark_read() {
            assertThatThrownBy(() -> service.markRead(conversation.getId(), STRANGER, 5L))
                    .isInstanceOf(ConversationNotFoundException.class);

            verify(messages, never())
                    .markReadUpTo(any(UUID.class), anyString(), anyLong(), any(Instant.class));
        }

        /**
         * The refusal for "exists but not yours" is the same as for "does not exist". Telling them
         * apart would let a rider walk order ids and learn which ones have a live chat.
         */
        @Test
        @DisplayName("gets the same answer for a conversation that is real and one that never existed")
        void cannot_tell_a_real_conversation_from_an_imaginary_one() {
            UUID imaginary = UUID.randomUUID();
            when(conversations.findById(imaginary)).thenReturn(Optional.empty());

            assertThatThrownBy(() -> service.thread(conversation.getId(), STRANGER, 0L))
                    .isInstanceOf(ConversationNotFoundException.class);
            assertThatThrownBy(() -> service.thread(imaginary, CUSTOMER, 0L))
                    .isInstanceOf(ConversationNotFoundException.class);
        }
    }

    @Nested
    @DisplayName("a message that is too long")
    class TooLong {

        @BeforeEach
        void tighten() {
            properties.setMaxMessageLength(10);
        }

        /**
         * Not truncated. Cutting a message changes what the sender said, and they would have no way
         * of knowing the rider read something else.
         */
        @Test
        @DisplayName("is refused rather than silently shortened, and nothing is stored")
        void is_refused_and_nothing_is_stored() {
            assertThatThrownBy(() -> post(CUSTOMER, "this is far longer than ten characters"))
                    .isInstanceOf(MessageRejectedException.class);

            verify(messages, never()).save(any(ChatMessage.class));
            verify(delivery, never()).deliver(any());
        }

        /** Validating before the lock means a rejected message never serialises the thread. */
        @Test
        @DisplayName("is rejected before the conversation row is locked")
        void is_rejected_before_taking_the_row_lock() {
            assertThatThrownBy(() -> post(CUSTOMER, "this is far longer than ten characters"))
                    .isInstanceOf(MessageRejectedException.class);

            verify(conversations, never()).lockById(any(UUID.class));
        }
    }

    @Nested
    @DisplayName("a conversation that has closed")
    class Closed {

        @BeforeEach
        void close() {
            conversation.closeAt(Instant.now().minusSeconds(60));
        }

        @Test
        @DisplayName("refuses a new message, and says when it closed rather than just failing")
        void refuses_a_new_message() {
            assertThatThrownBy(() -> post(CUSTOMER, "are you still there"))
                    .isInstanceOf(ConversationClosedException.class);

            verify(messages, never()).save(any(ChatMessage.class));
            verify(delivery, never()).deliver(any());
        }

        /** The thread does not disappear when it closes; it only stops growing. */
        @Test
        @DisplayName("is still readable by its participants")
        void is_still_readable() {
            when(messages.findByConversationIdAndSequenceNoGreaterThanOrderBySequenceNoAsc(
                    eq(conversation.getId()), eq(0L), any(Pageable.class)))
                    .thenReturn(List.of());

            assertThat(service.thread(conversation.getId(), CUSTOMER, 0L)).isEmpty();
        }

        /**
         * The retry exists to survive exactly the network failure that could straddle the closing
         * instant. Refusing it there would lose the customer's last message to the very problem it
         * was meant to solve.
         */
        @Test
        @DisplayName("still honours a retry of a message that was accepted while it was open")
        void still_honours_a_retry_of_something_accepted_while_open() {
            ChatMessage accepted = new ChatMessage(conversation.getId(), 1L, CUSTOMER,
                    ChatParticipantRole.CUSTOMER, "at the door", "abc", Instant.now());
            when(messages.findByConversationIdAndClientMessageId(conversation.getId(), "abc"))
                    .thenReturn(Optional.of(accepted));

            assertThat(service.post(conversation.getId(), CUSTOMER, "at the door", "abc", null))
                    .isSameAs(accepted);
        }
    }

    @Nested
    @DisplayName("reading the thread")
    class Reading {

        /**
         * The guarantee behind persist-then-deliver. The row was committed before any frame was
         * attempted, so a recipient whose socket was down while the message was sent gets it back
         * from the cursor read — and that read is what records the delivery the frame never did.
         */
        @Test
        @DisplayName("returns a message the recipient was offline for, and counts that as its delivery")
        void a_message_survives_the_recipient_being_disconnected() {
            ChatMessage sent = post(CUSTOMER, "left it with your neighbour");
            assertThat(sent.getDeliveredAt()).isNull();

            when(messages.findByConversationIdAndSequenceNoGreaterThanOrderBySequenceNoAsc(
                    eq(conversation.getId()), eq(0L), any(Pageable.class)))
                    .thenReturn(List.of(sent));

            List<ChatMessage> afterReconnect = service.thread(conversation.getId(), RIDER, 0L);

            assertThat(afterReconnect).containsExactly(sent);
            assertThat(sent.getBody()).isEqualTo("left it with your neighbour");
            assertThat(sent.getDeliveredAt()).isNotNull();
        }

        /** The cursor is what keeps a reconnect cheap: only what was missed comes back. */
        @Test
        @DisplayName("asks only for what the client does not already have")
        void asks_from_the_clients_cursor() {
            when(messages.findByConversationIdAndSequenceNoGreaterThanOrderBySequenceNoAsc(
                    eq(conversation.getId()), eq(41L), any(Pageable.class)))
                    .thenReturn(List.of());

            service.thread(conversation.getId(), RIDER, 41L);

            verify(messages).findByConversationIdAndSequenceNoGreaterThanOrderBySequenceNoAsc(
                    eq(conversation.getId()), eq(41L), any(Pageable.class));
        }

        /** "Delivered" means it reached the other person, not that its author reloaded the screen. */
        @Test
        @DisplayName("refetching your own message does not mark it delivered to yourself")
        void your_own_message_is_not_delivered_to_you_by_reading_it() {
            ChatMessage mine = post(CUSTOMER, "coming down");
            when(messages.findByConversationIdAndSequenceNoGreaterThanOrderBySequenceNoAsc(
                    eq(conversation.getId()), eq(0L), any(Pageable.class)))
                    .thenReturn(List.of(mine));

            service.thread(conversation.getId(), CUSTOMER, 0L);

            assertThat(mine.getDeliveredAt()).isNull();
        }
    }

    @Nested
    @DisplayName("unread counts")
    class Unread {

        @Test
        @DisplayName("are reported per conversation and as one total, so the badge needs a single call")
        void are_reported_per_conversation_and_in_total() {
            when(conversations.findAllForParticipant(RIDER)).thenReturn(List.of(conversation));
            when(messages.countUnreadByConversation(List.of(conversation.getId()), RIDER))
                    .thenReturn(List.of(tally(conversation.getId(), 3L)));

            ChatService.UnreadSummary summary = service.unreadSummary(RIDER);

            assertThat(summary.total()).isEqualTo(3L);
            assertThat(summary.byConversation()).containsEntry(conversation.getId(), 3L);
        }

        @Test
        @DisplayName("come back as zero rather than as an error when there is nothing to show")
        void are_zero_when_there_is_nothing() {
            when(conversations.findAllForParticipant(RIDER)).thenReturn(List.of());

            assertThat(service.unreadSummary(RIDER).total()).isZero();
        }

        @Test
        @DisplayName("appear on the conversation list without a count query per row")
        void are_attached_to_the_conversation_list_in_one_query() {
            when(conversations.findAllForParticipant(CUSTOMER)).thenReturn(List.of(conversation));
            when(messages.countUnreadByConversation(List.of(conversation.getId()), CUSTOMER))
                    .thenReturn(List.of(tally(conversation.getId(), 2L)));

            List<ChatService.ConversationView> views = service.conversationsFor(CUSTOMER);

            assertThat(views).singleElement().satisfies(view -> {
                assertThat(view.unread()).isEqualTo(2L);
                assertThat(view.yourRole()).isEqualTo(ChatParticipantRole.CUSTOMER);
                assertThat(view.open()).isTrue();
            });
            verify(messages, never())
                    .countByConversationIdAndSenderIdNotAndReadAtIsNull(any(UUID.class), anyString());
        }

        @Test
        @DisplayName("are marked read up to the cursor the client has actually seen")
        void are_cleared_up_to_the_clients_cursor() {
            when(messages.markReadUpTo(eq(conversation.getId()), eq(RIDER), eq(7L), any(Instant.class)))
                    .thenReturn(4);

            assertThat(service.markRead(conversation.getId(), RIDER, 7L)).isEqualTo(4);
        }

    }

    @Nested
    @DisplayName("the conversation's lifetime")
    class Lifetime {

        @Test
        @DisplayName("opens when a rider is assigned, with that order's two people in it")
        void opens_when_a_rider_is_assigned() {
            when(conversations.findLiveByOrderId(ORDER)).thenReturn(Optional.empty());
            when(conversations.save(any(ChatConversation.class)))
                    .thenAnswer(call -> call.getArgument(0));

            ChatConversation opened = service.openForRider(ORDER, CUSTOMER, RIDER).orElseThrow();

            assertThat(opened.isParticipant(CUSTOMER)).isTrue();
            assertThat(opened.isParticipant(RIDER)).isTrue();
            assertThat(opened.isParticipant(STRANGER)).isFalse();
        }

        /** Bus delivery is at-least-once; one assignment must not produce two threads. */
        @Test
        @DisplayName("a redelivered assignment returns the conversation that already exists")
        void a_redelivered_assignment_does_not_open_a_second_conversation() {
            assertThat(service.openForRider(ORDER, CUSTOMER, RIDER))
                    .containsSame(conversation);

            verify(conversations, never()).save(any(ChatConversation.class));
        }

        /**
         * Rewriting rider_id would hand the incoming rider every word the previous one exchanged
         * with the customer, and leave the outgoing rider reading a thread that carries on without
         * them.
         */
        @Test
        @DisplayName("a reassignment closes the outgoing rider's thread before opening the new one")
        void a_reassignment_closes_the_old_thread_and_opens_a_new_one() {
            when(conversations.saveAndFlush(any(ChatConversation.class)))
                    .thenAnswer(call -> call.getArgument(0));
            when(conversations.save(any(ChatConversation.class)))
                    .thenAnswer(call -> call.getArgument(0));

            ChatConversation replacement =
                    service.openForRider(ORDER, CUSTOMER, "replacement-rider").orElseThrow();

            assertThat(conversation.isOpenAt(Instant.now().plusSeconds(1))).isFalse();
            assertThat(replacement.isParticipant("replacement-rider")).isTrue();
            assertThat(replacement.isParticipant(RIDER)).isFalse();

            // Flushed first, or the insert races the pending update and trips the one-live-thread
            // index inside the same transaction.
            InOrder order = inOrder(conversations);
            order.verify(conversations).saveAndFlush(any(ChatConversation.class));
            order.verify(conversations).save(any(ChatConversation.class));
        }

        @Test
        @DisplayName("refuses to open a chat whose two participants are the same person")
        void refuses_a_conversation_with_one_participant() {
            when(conversations.findLiveByOrderId(ORDER)).thenReturn(Optional.empty());

            assertThat(service.openForRider(ORDER, CUSTOMER, CUSTOMER)).isEmpty();

            verify(conversations, never()).save(any(ChatConversation.class));
        }

        @Test
        @DisplayName("keeps accepting messages for the configured window after the order is delivered")
        void stays_open_for_a_window_after_delivery() {
            service.closeAfter(ORDER, Duration.ofHours(2));

            assertThat(conversation.isOpenAt(Instant.now().plus(Duration.ofMinutes(90)))).isTrue();
            assertThat(conversation.isOpenAt(Instant.now().plus(Duration.ofHours(3)))).isFalse();
        }

        /** A redelivery an hour later must not give the customer another two hours. */
        @Test
        @DisplayName("a redelivered close does not push the window further out")
        void a_redelivered_close_does_not_extend_the_window() {
            service.closeAfter(ORDER, Duration.ofHours(2));
            Instant first = conversation.getClosesAt();

            service.closeAfter(ORDER, Duration.ofHours(24));

            assertThat(conversation.getClosesAt()).isEqualTo(first);
        }

        @Test
        @DisplayName("shuts immediately when the order is cancelled, since there is nothing to ask about")
        void shuts_at_once_on_cancellation() {
            service.closeAfter(ORDER, ChatProperties.CLOSE_ON_CANCEL);

            assertThat(conversation.isOpenAt(Instant.now().plusSeconds(1))).isFalse();
        }
    }

    @Nested
    @DisplayName("the support read")
    class SupportRead {

        @Test
        @DisplayName("records who read the transcript, and why, before any of it is returned")
        void records_the_access_before_returning_anything() {
            when(messages.findByConversationIdAndSequenceNoGreaterThanOrderBySequenceNoAsc(
                    eq(conversation.getId()), eq(0L), any(Pageable.class)))
                    .thenReturn(List.of());

            service.transcriptForSupport(conversation.getId(), "agent-sub", "ticket-4821", "corr-9");

            ArgumentCaptor<TranscriptAccess> audit = ArgumentCaptor.forClass(TranscriptAccess.class);
            verify(transcriptAccess).save(audit.capture());
            assertThat(audit.getValue().getActorId()).isEqualTo("agent-sub");
            assertThat(audit.getValue().getReason()).isEqualTo("ticket-4821");
            assertThat(audit.getValue().getConversationId()).isEqualTo(conversation.getId());

            InOrder order = inOrder(transcriptAccess, messages);
            order.verify(transcriptAccess).save(any(TranscriptAccess.class));
            order.verify(messages).findByConversationIdAndSequenceNoGreaterThanOrderBySequenceNoAsc(
                    any(UUID.class), anyLong(), any(Pageable.class));
        }

        /**
         * A deployment that has turned this off should not have staff able to confirm which
         * conversations exist, so the refusal is the same one a stranger gets.
         */
        @Test
        @DisplayName("is indistinguishable from a missing conversation when the deployment disables it")
        void is_indistinguishable_from_a_missing_conversation_when_disabled() {
            properties.setBackofficeTranscriptAccess(false);

            assertThatThrownBy(() -> service.transcriptForSupport(
                    conversation.getId(), "agent-sub", "ticket-4821", null))
                    .isInstanceOf(ConversationNotFoundException.class);

            verify(transcriptAccess, never()).save(any(TranscriptAccess.class));
        }
    }
}
