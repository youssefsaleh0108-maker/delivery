package com.delivery.appnotification.service;

import java.util.HashSet;
import java.util.Set;
import java.util.stream.Collectors;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.messaging.simp.user.SimpUserRegistry;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.appnotification.domain.ChatBlockRepository;
import com.delivery.appnotification.domain.ChatRoomMemberRepository;
import com.delivery.appnotification.domain.ChatRoomMessage;

/**
 * Puts a stored room message on the screens of the neighbours watching the room.
 *
 * <p><strong>Fanned out per member rather than published to one shared topic.</strong> A shared
 * {@code /topic/room} is the obvious design and it cannot keep two promises this feature makes. A
 * broker topic hands every frame to every subscription it holds, so it cannot leave out the
 * neighbours who blocked the author — the block would only be honoured by the history endpoint and
 * a well-behaved client. And a subscription outlives the membership it was checked against: somebody
 * who moved neighbourhood, or whose socket subscribed before a moderator acted, would keep receiving
 * the old room until they reconnected. So each room is a per-user destination,
 * {@code /user/queue/chat.rooms.{roomId}}: subscribing is still checked by the socket's interceptor
 * ({@code RoomSubscriptionGuard}), and at send time this class asks who is <em>still</em> a member,
 * and each frame goes only to them.
 *
 * <p>Never decides whether a message exists — the row is committed before this runs, and a client
 * that missed a frame fetches everything after its last sequence on reconnect. There is deliberately
 * no push notification for room messages: a neighbourhood of a thousand people each buzzed for every
 * "good morning" is how an app gets uninstalled.
 */
@Service
public class RoomDelivery {

    private static final Logger log = LoggerFactory.getLogger(RoomDelivery.class);

    /** What the server addresses; Spring's user prefix resolves it per session. */
    public static final String ROOM_DESTINATION_PREFIX = "/queue/chat.rooms.";

    /** What a client subscribes to, followed by the room id. */
    public static final String ROOM_SUBSCRIPTION_PREFIX = "/user" + ROOM_DESTINATION_PREFIX;

    private final SimpMessagingTemplate websocket;
    private final SimpUserRegistry connectedUsers;
    private final ChatRoomMemberRepository members;
    private final ChatBlockRepository blocks;

    public RoomDelivery(SimpMessagingTemplate websocket,
                        SimpUserRegistry connectedUsers,
                        ChatRoomMemberRepository members,
                        ChatBlockRepository blocks) {
        this.websocket = websocket;
        this.connectedUsers = connectedUsers;
        this.members = members;
        this.blocks = blocks;
    }

    /**
     * Sends one message, or its tombstone, to every current member who is listening.
     *
     * <p>{@code REQUIRES_NEW} for the reason {@code ChatDelivery.deliver} spells out: this runs from
     * an after-commit callback, where joining the finished transaction would silently lose the
     * membership read. The message itself is safe to read here although detached — it has no lazy
     * associations, only columns already loaded.
     */
    @Transactional(propagation = Propagation.REQUIRES_NEW, readOnly = true)
    public void broadcast(ChatRoomMessage message) {
        String destination = ROOM_DESTINATION_PREFIX + message.getRoomId();
        String subscribed = "/user" + destination;

        Set<String> listening = connectedUsers
                .findSubscriptions(subscription -> subscribed.equals(subscription.getDestination()))
                .stream()
                .map(subscription -> subscription.getSession().getUser().getName())
                .collect(Collectors.toSet());
        if (listening.isEmpty()) {
            return;
        }

        for (String recipient : recipientsAmong(message, listening)) {
            try {
                websocket.convertAndSendToUser(recipient, destination,
                        RoomMessageView.of(message, recipient));
            } catch (Exception e) {
                // One neighbour's dead socket must not cost everyone after them in the loop their
                // frame. They catch up from history on reconnect.
                log.warn("Live room frame for message {} could not be sent to one recipient",
                        message.getId(), e);
            }
        }
    }

    /** Listening is not enough: they must still be in the room, and must not have blocked the author. */
    Set<String> recipientsAmong(ChatRoomMessage message, Set<String> listening) {
        Set<String> recipients = new HashSet<>(members.currentAmong(message.getRoomId(), listening));
        if (!recipients.isEmpty()) {
            // The block is honoured on the wire, not only in history: a blocker's socket is simply
            // never sent the frame, whatever the client would have done with it.
            blocks.blockersAmong(message.getSenderId(), recipients).forEach(recipients::remove);
        }
        return recipients;
    }
}
