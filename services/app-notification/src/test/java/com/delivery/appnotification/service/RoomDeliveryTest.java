package com.delivery.appnotification.service;

import java.time.Instant;
import java.util.ArrayList;
import java.util.Collection;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.messaging.simp.user.SimpSession;
import org.springframework.messaging.simp.user.SimpSubscription;
import org.springframework.messaging.simp.user.SimpSubscriptionMatcher;
import org.springframework.messaging.simp.user.SimpUser;
import org.springframework.messaging.simp.user.SimpUserRegistry;

import com.delivery.appnotification.domain.ChatRoomMember;
import com.delivery.appnotification.domain.ChatRoomMemberRepository;
import com.delivery.appnotification.domain.ChatRoomMessage;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyCollection;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

/**
 * Who a live room frame reaches: people listening to that room who are still in it — not everyone
 * holding a subscription.
 */
class RoomDeliveryTest {

    private static final UUID ROOM = UUID.randomUUID();
    private static final String DESTINATION = RoomDelivery.ROOM_DESTINATION_PREFIX + ROOM;

    private SimpMessagingTemplate websocket;
    private SimpUserRegistry registry;
    private ChatRoomMemberRepository members;
    private RoomDelivery delivery;

    private final List<SimpSubscription> subscriptions = new ArrayList<>();
    private ChatRoomMessage message;

    @BeforeEach
    void setUp() {
        websocket = mock(SimpMessagingTemplate.class);
        registry = mock(SimpUserRegistry.class);
        members = mock(ChatRoomMemberRepository.class);
        delivery = new RoomDelivery(websocket, registry, members);

        when(registry.findSubscriptions(any())).thenAnswer(call -> {
            SimpSubscriptionMatcher matcher = call.getArgument(0);
            return subscriptions.stream().filter(matcher::match).collect(Collectors.toSet());
        });

        ChatRoomMember author = new ChatRoomMember(ROOM, "author-sub", "Tania K.", Instant.now());
        message = new ChatRoomMessage(ROOM, 5L, author, "Hallab is open late tonight", null, Instant.now());
    }

    private void listening(String user, String destination) {
        SimpUser simpUser = mock(SimpUser.class);
        when(simpUser.getName()).thenReturn(user);
        SimpSession session = mock(SimpSession.class);
        when(session.getUser()).thenReturn(simpUser);
        SimpSubscription subscription = mock(SimpSubscription.class);
        when(subscription.getDestination()).thenReturn(destination);
        when(subscription.getSession()).thenReturn(session);
        subscriptions.add(subscription);
    }

    @Test
    @DisplayName("reaches current members listening to the room, each told whether it is theirs")
    @SuppressWarnings("unchecked")
    void reaches_current_members_only() {
        listening("author-sub", "/user" + DESTINATION);
        listening("neighbour-sub", "/user" + DESTINATION);
        // Subscribed while a member, moved neighbourhood since.
        listening("moved-away-sub", "/user" + DESTINATION);
        // Listening to a different room entirely.
        listening("elsewhere-sub", "/user" + RoomDelivery.ROOM_DESTINATION_PREFIX + UUID.randomUUID());

        ArgumentCaptor<Collection<String>> asked = ArgumentCaptor.forClass(Collection.class);
        when(members.currentAmong(eq(ROOM), asked.capture())).thenReturn(List.of("author-sub", "neighbour-sub"));

        delivery.broadcast(message);

        assertThat(asked.getValue()).containsExactlyInAnyOrder("author-sub", "neighbour-sub", "moved-away-sub");
        ArgumentCaptor<RoomMessageView> toAuthor = ArgumentCaptor.forClass(RoomMessageView.class);
        ArgumentCaptor<RoomMessageView> toNeighbour = ArgumentCaptor.forClass(RoomMessageView.class);
        verify(websocket).convertAndSendToUser(eq("author-sub"), eq(DESTINATION), toAuthor.capture());
        verify(websocket).convertAndSendToUser(eq("neighbour-sub"), eq(DESTINATION), toNeighbour.capture());
        verify(websocket, never()).convertAndSendToUser(eq("moved-away-sub"), any(), any());
        verify(websocket, never()).convertAndSendToUser(eq("elsewhere-sub"), any(), any());
        assertThat(toAuthor.getValue().mine()).isTrue();
        assertThat(toNeighbour.getValue().mine()).isFalse();
        assertThat(toNeighbour.getValue().text()).isEqualTo("Hallab is open late tonight");
    }

    @Test
    @DisplayName("asks nothing of the database when nobody is listening")
    void nobody_listening_costs_nothing() {
        listening("rider-sub", "/user/queue/chat");

        delivery.broadcast(message);

        verifyNoInteractions(members);
        verify(websocket, never()).convertAndSendToUser(any(), any(), any());
    }

    @Test
    @DisplayName("keeps going when one neighbour's socket fails")
    void one_failure_does_not_stop_the_rest() {
        listening("first-sub", "/user" + DESTINATION);
        listening("second-sub", "/user" + DESTINATION);
        when(members.currentAmong(eq(ROOM), anyCollection())).thenReturn(List.of("first-sub", "second-sub"));
        doThrow(new IllegalStateException("socket gone"))
                .when(websocket).convertAndSendToUser(eq("first-sub"), eq(DESTINATION), any());

        delivery.broadcast(message);

        verify(websocket).convertAndSendToUser(eq("second-sub"), eq(DESTINATION), any());
    }

    @Test
    @DisplayName("subscription and delivery agree on the destination name")
    void destinations_agree() {
        assertThat(RoomDelivery.ROOM_SUBSCRIPTION_PREFIX + ROOM).isEqualTo("/user" + DESTINATION);
        assertThat(Set.of(RoomSubscriptionGuard.ROOM_FAMILY + "."))
                .containsExactly(RoomDelivery.ROOM_SUBSCRIPTION_PREFIX);
    }
}
