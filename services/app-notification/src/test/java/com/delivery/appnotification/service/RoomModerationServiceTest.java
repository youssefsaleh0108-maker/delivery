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

import com.delivery.appnotification.domain.ChatBlock;
import com.delivery.appnotification.domain.ChatBlockRepository;
import com.delivery.appnotification.domain.ChatModerationAction;
import com.delivery.appnotification.domain.ChatModerationActionRepository;
import com.delivery.appnotification.domain.ChatRoom;
import com.delivery.appnotification.domain.ChatRoomMember;
import com.delivery.appnotification.domain.ChatRoomMemberRepository;
import com.delivery.appnotification.domain.ChatRoomMessage;
import com.delivery.appnotification.domain.ChatRoomMessageRepository;
import com.delivery.appnotification.domain.ChatRoomReport;
import com.delivery.appnotification.domain.ChatRoomReportRepository;
import com.delivery.appnotification.domain.ChatRoomRepository;
import com.delivery.appnotification.service.RoomExceptions.RoomNotFoundException;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
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
 * Report, block, hide, dismiss, mute: each one enforced here rather than trusted to a client, and each
 * moderator action on the record before it takes effect.
 */
class RoomModerationServiceTest {

    private static final String NEIGHBOUR = "neighbour-sub";
    private static final String AUTHOR = "author-sub";
    private static final String STRANGER = "other-zone-sub";
    private static final String MODERATOR = "backoffice-sub";

    private ChatRoomRepository rooms;
    private ChatRoomMemberRepository members;
    private ChatRoomMessageRepository messages;
    private ChatRoomReportRepository reports;
    private ChatBlockRepository blocks;
    private ChatModerationActionRepository actions;
    private RoomDelivery delivery;
    private RoomModerationService service;

    private ChatRoom room;
    private ChatRoomMember author;
    private ChatRoomMessage message;

    @BeforeEach
    void setUp() {
        rooms = mock(ChatRoomRepository.class);
        members = mock(ChatRoomMemberRepository.class);
        messages = mock(ChatRoomMessageRepository.class);
        reports = mock(ChatRoomReportRepository.class);
        blocks = mock(ChatBlockRepository.class);
        actions = mock(ChatModerationActionRepository.class);
        delivery = mock(RoomDelivery.class);
        service = new RoomModerationService(rooms, members, messages, reports, blocks, actions, delivery);

        room = new ChatRoom(UUID.randomUUID(), "Mar Mikhael");
        author = new ChatRoomMember(room.getId(), AUTHOR, "Hadi S.", Instant.now());
        message = new ChatRoomMessage(room.getId(), 7L, author, "call me on 70 123 456", null, Instant.now());

        when(messages.findById(message.getId())).thenReturn(Optional.of(message));
        when(members.existsByRoomIdAndUserIdAndLeftAtIsNull(room.getId(), NEIGHBOUR)).thenReturn(true);
        when(members.existsByRoomIdAndUserIdAndLeftAtIsNull(room.getId(), AUTHOR)).thenReturn(true);
        when(members.findByRoomIdAndUserId(room.getId(), AUTHOR)).thenReturn(Optional.of(author));
        when(members.findByUserIdAndLeftAtIsNull(AUTHOR)).thenReturn(Optional.of(author));
        when(members.findByUserId(AUTHOR)).thenReturn(List.of(author));
        when(actions.save(any(ChatModerationAction.class))).thenAnswer(call -> call.getArgument(0));
    }

    private ChatModerationAction audited() {
        ArgumentCaptor<ChatModerationAction> saved = ArgumentCaptor.forClass(ChatModerationAction.class);
        verify(actions).save(saved.capture());
        return saved.getValue();
    }

    @Nested
    @DisplayName("a neighbour")
    class ANeighbour {

        @Test
        @DisplayName("reports a message in their own room")
        void reports_a_message() {
            service.report(message.getId(), NEIGHBOUR, ChatRoomReport.Reason.PERSONAL_INFO);

            verify(reports).insertIfAbsent(any(UUID.class), eq(message.getId()), eq(room.getId()),
                    eq(NEIGHBOUR), eq("PERSONAL_INFO"));
        }

        @Test
        @DisplayName("cannot report a message from a room they are not in, and learns nothing about it")
        void cannot_report_elsewhere() {
            assertThatThrownBy(() -> service.report(message.getId(), STRANGER, ChatRoomReport.Reason.SPAM))
                    .isInstanceOf(RoomNotFoundException.class);
            verifyNoInteractions(reports);
        }

        @Test
        @DisplayName("cannot report their own message")
        void cannot_report_themselves() {
            assertThatThrownBy(() -> service.report(message.getId(), AUTHOR, ChatRoomReport.Reason.SPAM))
                    .isInstanceOf(MessageRejectedException.class);
            verifyNoInteractions(reports);
        }

        @Test
        @DisplayName("files nothing against a message a moderator already removed")
        void nothing_to_report_once_removed() {
            message.hide(MODERATOR, Instant.now());

            service.report(message.getId(), NEIGHBOUR, ChatRoomReport.Reason.ABUSE);

            verifyNoInteractions(reports);
        }

        @Test
        @DisplayName("blocks the author through the message, and the block names them without identifying them")
        void blocks_the_author() {
            when(blocks.findByBlockerIdAndBlockedId(NEIGHBOUR, AUTHOR))
                    .thenReturn(Optional.of(new ChatBlock(NEIGHBOUR, AUTHOR, "Hadi S.", Instant.now())));

            ChatBlock block = service.blockAuthor(message.getId(), NEIGHBOUR);

            assertThat(block.getBlockedName()).isEqualTo("Hadi S.");
            verify(blocks).insertIfAbsent(any(UUID.class), eq(NEIGHBOUR), eq(AUTHOR), eq("Hadi S."));
        }

        @Test
        @DisplayName("cannot block themselves")
        void cannot_block_themselves() {
            assertThatThrownBy(() -> service.blockAuthor(message.getId(), AUTHOR))
                    .isInstanceOf(MessageRejectedException.class);
            verify(blocks, never()).insertIfAbsent(any(), anyString(), anyString(), any());
        }

        @Test
        @DisplayName("cannot block through a message from a room they are not in")
        void cannot_block_from_elsewhere() {
            assertThatThrownBy(() -> service.blockAuthor(message.getId(), STRANGER))
                    .isInstanceOf(RoomNotFoundException.class);
            verifyNoInteractions(blocks);
        }

        @Test
        @DisplayName("can lift only a block they made")
        void lifts_only_their_own_block() {
            UUID someoneElses = UUID.randomUUID();
            when(blocks.findByIdAndBlockerId(someoneElses, NEIGHBOUR)).thenReturn(Optional.empty());

            assertThatThrownBy(() -> service.unblock(someoneElses, NEIGHBOUR))
                    .isInstanceOf(RoomNotFoundException.class);
            verify(blocks, never()).delete(any());
        }
    }

    @Nested
    @DisplayName("a moderator")
    class AModerator {

        @Test
        @DisplayName("hides a message: tombstoned for everyone, reports closed, action audited, watchers told")
        void hides_a_message() {
            ChatRoomReport open = new ChatRoomReport(message, NEIGHBOUR, ChatRoomReport.Reason.PERSONAL_INFO,
                    Instant.now());
            when(reports.findByMessageIdAndResolvedAtIsNull(message.getId())).thenReturn(List.of(open));

            service.hide(message.getId(), MODERATOR, "posted a phone number", "corr-9");

            assertThat(message.isHidden()).isTrue();
            assertThat(message.getHiddenBy()).isEqualTo(MODERATOR);
            assertThat(open.getResolution()).isEqualTo(ChatRoomReport.Resolution.HIDDEN);
            assertThat(open.getResolvedBy()).isEqualTo(MODERATOR);
            ChatModerationAction action = audited();
            assertThat(action.getAction()).isEqualTo(ChatModerationAction.Type.HIDE_MESSAGE);
            assertThat(action.getActorId()).isEqualTo(MODERATOR);
            assertThat(action.getReason()).isEqualTo("posted a phone number");
            assertThat(action.getRoomId()).isEqualTo(room.getId());
            assertThat(action.getMessageId()).isEqualTo(message.getId());
            assertThat(action.getCorrelationId()).isEqualTo("corr-9");
            verify(delivery).broadcast(message);
        }

        @Test
        @DisplayName("hiding twice tells watchers once and records both clicks")
        void hiding_twice() {
            service.hide(message.getId(), MODERATOR, "spam", null);
            service.hide(message.getId(), "second-moderator", "spam", null);

            verify(delivery, times(1)).broadcast(message);
            verify(actions, times(2)).save(any(ChatModerationAction.class));
            assertThat(message.getHiddenBy()).isEqualTo(MODERATOR);
        }

        /** An unaudited moderator action is exactly what the trail exists to rule out. */
        @Test
        @DisplayName("does not hide anything when the audit row cannot be written")
        void no_audit_no_action() {
            when(actions.save(any(ChatModerationAction.class))).thenThrow(new IllegalStateException("db down"));

            assertThatThrownBy(() -> service.hide(message.getId(), MODERATOR, "spam", null))
                    .isInstanceOf(IllegalStateException.class);
            assertThat(message.isHidden()).isFalse();
            verifyNoInteractions(delivery);
        }

        @Test
        @DisplayName("dismisses reports and leaves the message where it was")
        void dismisses() {
            ChatRoomReport open = new ChatRoomReport(message, NEIGHBOUR, ChatRoomReport.Reason.OTHER, Instant.now());
            when(reports.findByMessageIdAndResolvedAtIsNull(message.getId())).thenReturn(List.of(open));

            service.dismiss(message.getId(), MODERATOR, "not a violation", null);

            assertThat(message.isHidden()).isFalse();
            assertThat(open.getResolution()).isEqualTo(ChatRoomReport.Resolution.DISMISSED);
            assertThat(audited().getAction()).isEqualTo(ChatModerationAction.Type.DISMISS_REPORTS);
            verifyNoInteractions(delivery);
        }

        @Test
        @DisplayName("mutes the author in that room for a while, recording whom and until when")
        void mutes_the_author() {
            Instant until = service.muteAuthor(message.getId(), MODERATOR, Duration.ofHours(24),
                    "repeated spam", null);

            assertThat(until).isCloseTo(Instant.now().plus(Duration.ofHours(24)), within(Duration.ofSeconds(5)));
            assertThat(author.getMutedUntil()).isEqualTo(until);
            assertThat(author.isMutedAt(Instant.now())).isTrue();
            ChatModerationAction action = audited();
            assertThat(action.getAction()).isEqualTo(ChatModerationAction.Type.MUTE_MEMBER);
            assertThat(action.getTargetUserId()).isEqualTo(AUTHOR);
            assertThat(action.getMutedUntil()).isEqualTo(until);
        }

        @Test
        @DisplayName("lifts a mute early, on the record")
        void unmutes_the_author() {
            author.muteUntil(Instant.now().plus(Duration.ofDays(7)));

            service.unmuteAuthor(message.getId(), MODERATOR, "appeal upheld", null);

            assertThat(author.getMutedUntil()).isNull();
            assertThat(audited().getAction()).isEqualTo(ChatModerationAction.Type.UNMUTE_MEMBER);
        }

        /** Reports are read late. By then the author may live, and post, somewhere else. */
        @Test
        @DisplayName("mutes the author where they are now, even when the reported message is from a room they left")
        void mutes_the_author_in_the_room_they_are_in_now() {
            ChatRoomMember nowIn = new ChatRoomMember(UUID.randomUUID(), AUTHOR, "Hadi S.", Instant.now());
            author.leave(Instant.now().minus(Duration.ofDays(1)));
            when(members.findByUserIdAndLeftAtIsNull(AUTHOR)).thenReturn(Optional.of(nowIn));

            Instant until = service.muteAuthor(message.getId(), MODERATOR, Duration.ofDays(30),
                    "harassment", null);

            assertThat(nowIn.getMutedUntil()).isEqualTo(until);
            assertThat(nowIn.isMutedAt(Instant.now())).isTrue();
            ChatModerationAction action = audited();
            assertThat(action.getTargetUserId()).isEqualTo(AUTHOR);
            // The trail keeps the room the message was said in: that is where the reason lives.
            assertThat(action.getRoomId()).isEqualTo(room.getId());
        }

        @Test
        @DisplayName("lifting a mute clears it from every room the author has been in")
        void unmuting_clears_every_membership() {
            ChatRoomMember elsewhere = new ChatRoomMember(UUID.randomUUID(), AUTHOR, "Hadi S.", Instant.now());
            author.muteUntil(Instant.now().plus(Duration.ofDays(7)));
            elsewhere.muteUntil(Instant.now().plus(Duration.ofDays(7)));
            when(members.findByUserId(AUTHOR)).thenReturn(List.of(author, elsewhere));

            service.unmuteAuthor(message.getId(), MODERATOR, "appeal upheld", null);

            assertThat(author.getMutedUntil()).isNull();
            assertThat(elsewhere.getMutedUntil()).isNull();
            verify(actions, times(1)).save(any(ChatModerationAction.class));
        }

        @Test
        @DisplayName("sees the queue with the room, the words, the reasons and whether the author is muted")
        void reads_the_queue() {
            Instant first = Instant.now().minus(Duration.ofHours(2));
            Instant last = Instant.now().minus(Duration.ofMinutes(5));
            when(reports.openTallies(any())).thenReturn(List.of(tally(message.getId(), 2L, first, last)));
            when(messages.findAllById(List.of(message.getId()))).thenReturn(List.of(message));
            when(rooms.findAllById(any())).thenReturn(List.of(room));
            when(reports.findByMessageIdInAndResolvedAtIsNull(List.of(message.getId()))).thenReturn(List.of(
                    new ChatRoomReport(message, NEIGHBOUR, ChatRoomReport.Reason.SPAM, first),
                    new ChatRoomReport(message, "another-sub", ChatRoomReport.Reason.PERSONAL_INFO, last)));
            // Muted in the room they moved to, not the one the report came from: the queue shows it.
            ChatRoomMember nowIn = new ChatRoomMember(UUID.randomUUID(), AUTHOR, "Hadi S.", Instant.now());
            nowIn.muteUntil(Instant.now().plus(Duration.ofDays(1)));
            when(members.findByUserIdIn(any())).thenReturn(List.of(author, nowIn));

            List<RoomModerationService.ReportedMessage> queue = service.openQueue();

            assertThat(queue).hasSize(1);
            RoomModerationService.ReportedMessage line = queue.get(0);
            assertThat(line.roomName()).isEqualTo("Mar Mikhael");
            assertThat(line.text()).isEqualTo("call me on 70 123 456");
            assertThat(line.authorName()).isEqualTo("Hadi S.");
            assertThat(line.reportCount()).isEqualTo(2L);
            assertThat(line.reasons()).containsExactly("PERSONAL_INFO", "SPAM");
            assertThat(line.authorMutedUntil()).isEqualTo(nowIn.getMutedUntil());
        }
    }

    @Test
    @DisplayName("a removed message reaches neighbours as a tombstone with no words and no name")
    void a_hidden_message_is_a_tombstone() {
        message.hide(MODERATOR, Instant.now());

        RoomMessageView view = RoomMessageView.of(message, NEIGHBOUR);

        assertThat(view.kind()).isEqualTo(RoomMessageView.HIDDEN);
        assertThat(view.text()).isNull();
        assertThat(view.authorName()).isNull();
        assertThat(view.sequence()).isEqualTo(7L);
    }

    private static ChatRoomReportRepository.OpenTally tally(UUID messageId, long count, Instant first, Instant last) {
        return new ChatRoomReportRepository.OpenTally() {
            @Override
            public UUID getMessageId() {
                return messageId;
            }

            @Override
            public long getReports() {
                return count;
            }

            @Override
            public Instant getFirstReportedAt() {
                return first;
            }

            @Override
            public Instant getLastReportedAt() {
                return last;
            }
        };
    }
}
