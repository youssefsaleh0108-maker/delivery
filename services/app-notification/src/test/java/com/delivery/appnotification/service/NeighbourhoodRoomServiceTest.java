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
import org.mockito.InOrder;
import org.springframework.data.domain.PageRequest;

import com.delivery.appnotification.client.ProductDirectory;
import com.delivery.appnotification.domain.ChatRoom;
import com.delivery.appnotification.domain.ChatRoomMember;
import com.delivery.appnotification.domain.ChatRoomMemberRepository;
import com.delivery.appnotification.domain.ChatRoomMessage;
import com.delivery.appnotification.domain.ChatRoomMessageRepository;
import com.delivery.appnotification.domain.ChatRoomRepository;
import com.delivery.appnotification.service.RoomExceptions.MemberMutedException;
import com.delivery.appnotification.service.RoomExceptions.NoNeighbourhoodException;
import com.delivery.appnotification.service.RoomExceptions.NoRoomReason;
import com.delivery.appnotification.service.RoomExceptions.RoomNotFoundException;
import com.delivery.appnotification.service.RoomExceptions.SendRateLimitedException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.json.JsonMapper;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.assertj.core.api.Assertions.within;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.inOrder;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

/**
 * Neighbourhood rooms: a customer is placed by their own delivery area, reads and posts only where
 * they are placed, and cannot talk their way into anybody else's room.
 */
class NeighbourhoodRoomServiceTest {

    private static final String CUSTOMER = "customer-sub";
    private static final String STRANGER = "other-zone-sub";
    private static final UUID ZONE = UUID.randomUUID();
    private static final UUID OTHER_ZONE = UUID.randomUUID();

    private ChatRoomRepository rooms;
    private ChatRoomMemberRepository members;
    private ChatRoomMessageRepository messages;
    private ProductDirectory directory;
    private RoomDelivery delivery;
    private RoomChatProperties properties;
    private NeighbourhoodRoomService service;

    private ChatRoom room;

    @BeforeEach
    void setUp() {
        rooms = mock(ChatRoomRepository.class);
        members = mock(ChatRoomMemberRepository.class);
        messages = mock(ChatRoomMessageRepository.class);
        directory = mock(ProductDirectory.class);
        delivery = mock(RoomDelivery.class);
        properties = new RoomChatProperties();
        service = new NeighbourhoodRoomService(rooms, members, messages, directory, delivery,
                properties, new ChatProperties());

        room = new ChatRoom(ZONE, "Mar Mikhael");
        when(rooms.findById(room.getId())).thenReturn(Optional.of(room));
        when(rooms.findByZoneId(ZONE)).thenReturn(Optional.of(room));
        when(rooms.lockById(room.getId())).thenReturn(Optional.of(room));
        when(members.findByUserIdAndLeftAtIsNull(anyString())).thenReturn(Optional.empty());
        when(members.findByRoomIdAndUserId(any(UUID.class), anyString())).thenReturn(Optional.empty());
        when(members.save(any(ChatRoomMember.class))).thenAnswer(call -> call.getArgument(0));
        when(messages.save(any(ChatRoomMessage.class))).thenAnswer(call -> call.getArgument(0));
        when(messages.findByRoomIdAndSenderIdAndClientMessageId(any(), anyString(), anyString()))
                .thenReturn(Optional.empty());
    }

    private ChatRoomMember memberOf(ChatRoom where, String userId, Instant joinedAt) {
        ChatRoomMember member = new ChatRoomMember(where.getId(), userId, "Tania K.", joinedAt);
        when(members.findByUserIdAndLeftAtIsNull(userId)).thenReturn(Optional.of(member));
        when(members.findByRoomIdAndUserIdAndLeftAtIsNull(where.getId(), userId))
                .thenReturn(Optional.of(member));
        return member;
    }

    private void zoneIsOffered(UUID zoneId, String name) {
        when(directory.activeZone(zoneId))
                .thenReturn(Optional.of(new ProductDirectory.Zone(zoneId, name, "Beirut", true)));
    }

    @Nested
    @DisplayName("placing a customer")
    class Placing {

        @Test
        @DisplayName("with no room and an address that names no area tells them to choose one")
        void no_area_and_no_room_asks_for_an_area() {
            assertThatThrownBy(() -> service.place(CUSTOMER, null, "Tania K."))
                    .isInstanceOfSatisfying(NoNeighbourhoodException.class,
                            e -> assertThat(e.getReason()).isEqualTo(NoRoomReason.NO_ZONE));
            verifyNoInteractions(directory);
        }

        @Test
        @DisplayName("puts them in their area's room, opening it on the first arrival")
        void places_them_in_their_areas_room() {
            zoneIsOffered(ZONE, "Mar Mikhael");
            when(members.countByRoomIdAndLeftAtIsNull(room.getId())).thenReturn(1L);

            NeighbourhoodRoomService.Placement placement = service.place(CUSTOMER, ZONE, "Tania K.");

            assertThat(placement.room()).isSameAs(room);
            assertThat(placement.member().getUserId()).isEqualTo(CUSTOMER);
            assertThat(placement.member().isCurrent()).isTrue();
            assertThat(placement.memberCount()).isEqualTo(1L);
            assertThat(placement.moveBlockedUntil()).isNull();
            // Named from Product Service's zone, never from anything the client sent.
            verify(rooms).insertIfAbsent(any(UUID.class), eq(ZONE), eq("Mar Mikhael"));
        }

        /** The client names an area, never a room: a made-up area reaches no room at all. */
        @Test
        @DisplayName("places nobody anywhere when the area is not one Product Service offers")
        void an_unknown_area_places_nobody() {
            when(directory.activeZone(ZONE)).thenReturn(Optional.empty());

            assertThatThrownBy(() -> service.place(CUSTOMER, ZONE, "Tania K."))
                    .isInstanceOfSatisfying(NoNeighbourhoodException.class,
                            e -> assertThat(e.getReason()).isEqualTo(NoRoomReason.UNKNOWN_ZONE));
            verify(rooms, never()).insertIfAbsent(any(), any(), any());
            verify(members, never()).save(any());
        }

        @Test
        @DisplayName("keeps a member in their room when they come back through the same area")
        void the_same_area_keeps_them_where_they_are() {
            ChatRoomMember member = memberOf(room, CUSTOMER, Instant.now().minus(Duration.ofDays(30)));

            NeighbourhoodRoomService.Placement placement = service.place(CUSTOMER, ZONE, "Tania K.");

            assertThat(placement.member()).isSameAs(member);
            verifyNoInteractions(directory);
        }

        @Test
        @DisplayName("keeps a member in the room they are in when the app sends no area")
        void no_area_keeps_an_existing_member() {
            ChatRoomMember member = memberOf(room, CUSTOMER, Instant.now().minus(Duration.ofDays(1)));

            assertThat(service.place(CUSTOMER, null, "Tania K.").member()).isSameAs(member);
        }

        /**
         * The address is the customer's own claim. What stops one account touring every room in the
         * city is that a claim can only move them once a week.
         */
        @Test
        @DisplayName("inside the cooldown, keeps a member where they are and says when they may move")
        void inside_the_cooldown_a_move_is_deferred() {
            Instant joined = Instant.now().minus(Duration.ofDays(1));
            ChatRoomMember member = memberOf(room, CUSTOMER, joined);

            NeighbourhoodRoomService.Placement placement = service.place(CUSTOMER, OTHER_ZONE, "Tania K.");

            assertThat(placement.room()).isSameAs(room);
            assertThat(placement.moveBlockedUntil()).isEqualTo(joined.plus(Duration.ofDays(7)));
            assertThat(member.isCurrent()).isTrue();
            verifyNoInteractions(directory);
        }

        @Test
        @DisplayName("after the cooldown, closes the old membership before opening the new one")
        void after_the_cooldown_a_member_moves() {
            ChatRoomMember old = memberOf(room, CUSTOMER, Instant.now().minus(Duration.ofDays(8)));
            ChatRoom elsewhere = new ChatRoom(OTHER_ZONE, "Hamra");
            zoneIsOffered(OTHER_ZONE, "Hamra");
            when(rooms.findByZoneId(OTHER_ZONE)).thenReturn(Optional.of(elsewhere));

            NeighbourhoodRoomService.Placement placement = service.place(CUSTOMER, OTHER_ZONE, "Tania K.");

            assertThat(placement.room()).isSameAs(elsewhere);
            assertThat(old.isCurrent()).isFalse();
            InOrder order = inOrder(members);
            order.verify(members).saveAndFlush(old);
            order.verify(members).save(any(ChatRoomMember.class));
        }

        @Test
        @DisplayName("leaves a member where they were when the area they moved to does not exist")
        void a_move_to_an_unknown_area_changes_nothing() {
            ChatRoomMember old = memberOf(room, CUSTOMER, Instant.now().minus(Duration.ofDays(8)));
            when(directory.activeZone(OTHER_ZONE)).thenReturn(Optional.empty());

            assertThatThrownBy(() -> service.place(CUSTOMER, OTHER_ZONE, "Tania K."))
                    .isInstanceOf(NoNeighbourhoodException.class);
            assertThat(old.isCurrent()).isTrue();
            verify(members, never()).saveAndFlush(any());
        }

        /** Moving away and back must not shed a mute or mint a fresh handle neighbours' blocks miss. */
        @Test
        @DisplayName("gives a returning neighbour their old membership back, mute and handle included")
        void a_returning_neighbour_keeps_their_mute_and_handle() {
            ChatRoomMember former = new ChatRoomMember(room.getId(), CUSTOMER, "Tania K.",
                    Instant.now().minus(Duration.ofDays(40)));
            Instant muteEnds = Instant.now().plus(Duration.ofDays(3));
            former.muteUntil(muteEnds);
            former.leave(Instant.now().minus(Duration.ofDays(20)));
            UUID handle = former.getHandle();
            zoneIsOffered(ZONE, "Mar Mikhael");
            when(members.findByRoomIdAndUserId(room.getId(), CUSTOMER)).thenReturn(Optional.of(former));

            ChatRoomMember member = service.place(CUSTOMER, ZONE, "Tania K.").member();

            assertThat(member).isSameAs(former);
            assertThat(member.isCurrent()).isTrue();
            assertThat(member.getHandle()).isEqualTo(handle);
            assertThat(member.getMutedUntil()).isEqualTo(muteEnds);
            assertThat(member.getJoinedAt()).isCloseTo(Instant.now(), within(Duration.ofSeconds(5)));
        }
    }

    @Nested
    @DisplayName("reading a room")
    class Reading {

        @Test
        @DisplayName("is refused to somebody from another neighbourhood, who learns nothing")
        void a_stranger_cannot_read() {
            when(members.findByRoomIdAndUserIdAndLeftAtIsNull(room.getId(), STRANGER))
                    .thenReturn(Optional.empty());

            assertThatThrownBy(() -> service.history(room.getId(), STRANGER, null, null))
                    .isInstanceOf(RoomNotFoundException.class);
            verifyNoInteractions(messages);
        }

        @Test
        @DisplayName("returns the newest page oldest first, and says whether older messages exist")
        void newest_page_reads_top_to_bottom() {
            ChatRoomMember member = memberOf(room, CUSTOMER, Instant.now());
            properties.setHistoryPageSize(2);
            ChatRoomMessage m1 = said(member, 1);
            ChatRoomMessage m2 = said(member, 2);
            ChatRoomMessage m3 = said(member, 3);
            // Asked AS the viewer: that is what lets the query itself leave out authors they blocked.
            when(messages.newestBefore(room.getId(), Long.MAX_VALUE, CUSTOMER, PageRequest.of(0, 3)))
                    .thenReturn(List.of(m3, m2, m1));

            NeighbourhoodRoomService.HistoryPage page = service.history(room.getId(), CUSTOMER, null, null);

            assertThat(page.messages()).containsExactly(m2, m3);
            assertThat(page.more()).isTrue();
        }

        @Test
        @DisplayName("after a reconnect, returns exactly what was missed, in order")
        void reconnect_returns_what_was_missed() {
            ChatRoomMember member = memberOf(room, CUSTOMER, Instant.now());
            ChatRoomMessage m4 = said(member, 4);
            when(messages.oldestAfter(eq(room.getId()), eq(3L), eq(CUSTOMER), any())).thenReturn(List.of(m4));

            NeighbourhoodRoomService.HistoryPage page = service.history(room.getId(), CUSTOMER, 2L, 3L);

            assertThat(page.messages()).containsExactly(m4);
            assertThat(page.more()).isFalse();
            verify(messages, never()).newestBefore(any(), anyLong(), any(), any());
        }
    }

    @Nested
    @DisplayName("posting")
    class Posting {

        @Test
        @DisplayName("stores the message with the room's next number and sends it to the room")
        void stores_and_broadcasts() {
            memberOf(room, CUSTOMER, Instant.now());

            ChatRoomMessage message = service.post(room.getId(), CUSTOMER, "Anyone know a good knefeh place?",
                    "client-1", "corr-1");

            assertThat(message.getSequenceNo()).isEqualTo(1L);
            assertThat(message.getBody()).isEqualTo("Anyone know a good knefeh place?");
            verify(delivery).broadcast(message);
        }

        @Test
        @DisplayName("is refused to somebody who is not in the room, before any lock or write")
        void a_stranger_cannot_post() {
            assertThatThrownBy(() -> service.post(room.getId(), STRANGER, "hello", null, null))
                    .isInstanceOf(RoomNotFoundException.class);
            verify(rooms, never()).lockById(any());
            verify(messages, never()).save(any());
        }

        @Test
        @DisplayName("refuses empty text before looking anything up")
        void refused_text_takes_no_lock() {
            assertThatThrownBy(() -> service.post(room.getId(), CUSTOMER, "   ", null, null))
                    .isInstanceOf(MessageRejectedException.class);
            verifyNoInteractions(members);
            verify(rooms, never()).lockById(any());
        }

        @Test
        @DisplayName("refuses a muted member, saying when the mute ends")
        void a_muted_member_is_refused() {
            ChatRoomMember member = memberOf(room, CUSTOMER, Instant.now());
            Instant until = Instant.now().plus(Duration.ofHours(24));
            member.muteUntil(until);

            assertThatThrownBy(() -> service.post(room.getId(), CUSTOMER, "hello", null, null))
                    .isInstanceOfSatisfying(MemberMutedException.class,
                            e -> assertThat(e.getMutedUntil()).isEqualTo(until));
            verify(messages, never()).save(any());
            verifyNoInteractions(delivery);
        }

        @Test
        @DisplayName("lets a mute that has run out lapse without anyone lifting it")
        void an_expired_mute_lapses() {
            ChatRoomMember member = memberOf(room, CUSTOMER, Instant.now());
            member.muteUntil(Instant.now().minus(Duration.ofMinutes(1)));

            assertThat(service.post(room.getId(), CUSTOMER, "back again", null, null)).isNotNull();
        }

        @Test
        @DisplayName("answers a retry of an accepted message with that message, even if a mute landed since")
        void a_retry_is_idempotent_even_after_a_mute() {
            ChatRoomMember member = memberOf(room, CUSTOMER, Instant.now());
            ChatRoomMessage accepted = said(member, 1);
            when(messages.findByRoomIdAndSenderIdAndClientMessageId(room.getId(), CUSTOMER, "client-1"))
                    .thenReturn(Optional.of(accepted));
            member.muteUntil(Instant.now().plus(Duration.ofHours(1)));

            assertThat(service.post(room.getId(), CUSTOMER, "hello", "client-1", null)).isSameAs(accepted);
            verify(messages, never()).save(any());
        }

        @Test
        @DisplayName("refuses somebody sending faster than the limit")
        void rate_limited() {
            memberOf(room, CUSTOMER, Instant.now());
            when(messages.countBySenderIdAndCreatedAtAfter(eq(CUSTOMER), any(Instant.class))).thenReturn(8L);

            assertThatThrownBy(() -> service.post(room.getId(), CUSTOMER, "buy now", null, null))
                    .isInstanceOfSatisfying(SendRateLimitedException.class,
                            e -> assertThat(e.getRetryAfter()).isEqualTo(Duration.ofMinutes(1)));
            verify(messages, never()).save(any());
        }

        /** The whole reason the view exists: neighbours see a handle and a name, never the account. */
        @Test
        @DisplayName("never puts the author's account id in what neighbours receive")
        void the_view_carries_no_account_id() throws Exception {
            memberOf(room, CUSTOMER, Instant.now());
            ChatRoomMessage message = service.post(room.getId(), CUSTOMER, "hi all", null, null);

            ObjectMapper json = JsonMapper.builder().addModule(new JavaTimeModule()).build();
            String seenByNeighbour = json.writeValueAsString(RoomMessageView.of(message, STRANGER));

            assertThat(seenByNeighbour)
                    .doesNotContain(CUSTOMER)
                    .contains(message.getSenderHandle().toString())
                    .contains("Tania K.");
            assertThat(RoomMessageView.of(message, STRANGER).mine()).isFalse();
            assertThat(RoomMessageView.of(message, CUSTOMER).mine()).isTrue();
        }
    }

    private ChatRoomMessage said(ChatRoomMember member, long sequence) {
        return new ChatRoomMessage(room.getId(), sequence, member, "message " + sequence, null, Instant.now());
    }
}
