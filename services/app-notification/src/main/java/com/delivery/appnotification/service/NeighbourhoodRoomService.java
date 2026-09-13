package com.delivery.appnotification.service;

import java.time.Instant;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

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

/**
 * Neighbourhood rooms: who is placed where, what they may read, and what gets said.
 *
 * <p><strong>Where a customer's room comes from.</strong> The platform keeps no customer address on
 * the server — addresses live on the phone, and an order does not record its delivery zone — so the
 * only source is the zone of the delivery address the customer has selected, which the app sends
 * exactly as it sends it at checkout. What the server does with that claim is what makes it a
 * membership rather than a room picker:
 * <ul>
 *   <li>the client never names a room. It names its delivery area; the room is derived from it, and
 *       every later read, post and subscription is checked against the membership row this writes;</li>
 *   <li>the area must be one Product Service offers in the address picker today, so a made-up or
 *       retired id places nobody anywhere;</li>
 *   <li>a person is in one room at a time (a partial unique index, not a convention), and may move to
 *       another only after {@link RoomChatProperties#getMoveCooldown()} — see there for why.</li>
 * </ul>
 * A customer whose address names no area is placed nowhere and told to choose one
 * ({@link NoRoomReason#NO_ZONE}); somebody already in a room who opens the chat without an area keeps
 * the room they are in.
 *
 * <p>Posting follows {@code ChatService}'s pattern: text validated before any lock, a gapless
 * sequence claimed under the room's row lock, idempotent retries, and delivery after commit.
 */
@Service
public class NeighbourhoodRoomService {

    private static final Logger log = LoggerFactory.getLogger(NeighbourhoodRoomService.class);

    private final ChatRoomRepository rooms;
    private final ChatRoomMemberRepository members;
    private final ChatRoomMessageRepository messages;
    private final ProductDirectory directory;
    private final RoomDelivery delivery;
    private final RoomChatProperties properties;
    private final ChatProperties chatProperties;

    public NeighbourhoodRoomService(ChatRoomRepository rooms,
                                    ChatRoomMemberRepository members,
                                    ChatRoomMessageRepository messages,
                                    ProductDirectory directory,
                                    RoomDelivery delivery,
                                    RoomChatProperties properties,
                                    ChatProperties chatProperties) {
        this.rooms = rooms;
        this.members = members;
        this.messages = messages;
        this.directory = directory;
        this.delivery = delivery;
        this.properties = properties;
        this.chatProperties = chatProperties;
    }

    // ---------------------------------------------------------------------------------- placement

    /**
     * The caller's room, placing them in it if they have none or may move.
     *
     * @param zoneId      the delivery area of the caller's selected address, or null if it has none
     * @param displayName from {@link ChatDisplayName}; refreshed on every visit so a renamed account
     *                    reads correctly from its next message on
     */
    @Transactional
    public Placement place(String userId, UUID zoneId, String displayName) {
        Instant now = Instant.now();
        Optional<ChatRoomMember> current = members.findByUserIdAndLeftAtIsNull(userId);

        if (current.isPresent()) {
            ChatRoomMember member = current.get();
            ChatRoom room = rooms.findById(member.getRoomId())
                    .orElseThrow(() -> new RoomNotFoundException(member.getRoomId()));

            if (zoneId == null || room.getZoneId().equals(zoneId)) {
                member.arrive(now, displayName);
                return placement(room, member, null);
            }

            Instant movableAt = member.getJoinedAt().plus(properties.getMoveCooldown());
            if (now.isBefore(movableAt)) {
                // Not an error. The caller still has a neighbourhood — the one they are in — and the
                // app says when they can move rather than showing nothing.
                member.arrive(now, displayName);
                return placement(room, member, movableAt);
            }
        } else if (zoneId == null) {
            throw new NoNeighbourhoodException(NoRoomReason.NO_ZONE);
        }

        // Validated BEFORE leaving the current room: a move to an area that turns out not to exist
        // must leave the caller where they were, not nowhere.
        ProductDirectory.Zone zone = directory.activeZone(zoneId)
                .orElseThrow(() -> new NoNeighbourhoodException(NoRoomReason.UNKNOWN_ZONE));

        current.ifPresent(leaving -> {
            leaving.leave(now);
            // Flushed before the arrival below: uq_chat_room_current_member allows one row per person
            // with a null left_at, and the pending update would otherwise race the insert.
            members.saveAndFlush(leaving);
            log.info("A member moved out of room {}", leaving.getRoomId());
        });

        rooms.insertIfAbsent(UUID.randomUUID(), zone.id(), zone.name());
        ChatRoom room = rooms.findByZoneId(zone.id())
                .orElseThrow(() -> new IllegalStateException("Room for zone " + zone.id() + " vanished"));
        room.rename(zone.name());

        ChatRoomMember member = members.findByRoomIdAndUserId(room.getId(), userId)
                .map(returning -> {
                    returning.arrive(now, displayName);
                    return returning;
                })
                .orElseGet(() -> members.save(new ChatRoomMember(room.getId(), userId, displayName, now)));

        return placement(room, member, null);
    }

    // ------------------------------------------------------------------------------------ reading

    /**
     * A page of the room's history.
     *
     * <p>Without cursors: the newest page, for opening the room. With {@code beforeSequence}: the page
     * before it, for scrolling up. With {@code afterSequence}: everything after it, for a reconnect —
     * which wins if both are given, because a client that has just reconnected must not skip what it
     * missed. Pages are returned oldest first in every mode, so the client appends or prepends them
     * unchanged.
     *
     * @return the page, and whether more exist in the direction asked
     */
    @Transactional(readOnly = true)
    public HistoryPage history(UUID roomId, String userId, Long beforeSequence, Long afterSequence) {
        requireMember(roomId, userId);
        int size = properties.getHistoryPageSize();
        PageRequest onePastAPage = PageRequest.of(0, size + 1);

        if (afterSequence != null) {
            List<ChatRoomMessage> newer = messages.oldestAfter(roomId, afterSequence, onePastAPage);
            boolean more = newer.size() > size;
            return new HistoryPage(more ? newer.subList(0, size) : newer, more);
        }

        long before = beforeSequence == null ? Long.MAX_VALUE : beforeSequence;
        List<ChatRoomMessage> older = messages.newestBefore(roomId, before, onePastAPage);
        boolean more = older.size() > size;
        List<ChatRoomMessage> page = new ArrayList<>(more ? older.subList(0, size) : older);
        Collections.reverse(page);
        return new HistoryPage(page, more);
    }

    // ------------------------------------------------------------------------------------ posting

    /**
     * Says something in the room.
     *
     * <p>The order of checks is the policy. Text first, so a message that was never going to be
     * accepted takes no lock. Membership next, so a stranger learns nothing — not whether the room is
     * busy, not whether they would be muted. Then, under the lock, a retry of something already
     * accepted is answered before the mute and the rate limit: a message that got through before a
     * moderator acted must not turn into an error on the retry the network forced.
     */
    @Transactional
    public ChatRoomMessage post(UUID roomId, String userId, String text, String clientMessageId,
                                String correlationId) {
        String body = ChatMessageText.normalise(text, chatProperties.getMaxMessageLength());

        ChatRoomMember member = requireMember(roomId, userId);
        ChatRoom room = rooms.lockById(roomId).orElseThrow(() -> new RoomNotFoundException(roomId));

        String clientId = blankToNull(clientMessageId);
        if (clientId != null) {
            Optional<ChatRoomMessage> already =
                    messages.findByRoomIdAndSenderIdAndClientMessageId(roomId, userId, clientId);
            if (already.isPresent()) {
                return already.get();
            }
        }

        Instant now = Instant.now();
        if (member.isMutedAt(now)) {
            throw new MemberMutedException(member.getMutedUntil());
        }

        long recent = messages.countBySenderIdAndCreatedAtAfter(userId, now.minus(properties.getSendWindow()));
        if (recent >= properties.getMaxMessagesPerWindow()) {
            throw new SendRateLimitedException(properties.getSendWindow());
        }

        ChatRoomMessage message = messages.save(new ChatRoomMessage(
                roomId, room.claimSequence(now), member, body, clientId, now));

        // The room id and sequence only; the words belong to the room, not to the log.
        log.debug("Room {} message {} stored (correlation {})", roomId, message.getSequenceNo(), correlationId);

        broadcastAfterCommit(message);
        return message;
    }

    // ---------------------------------------------------------------------------------- internals

    private ChatRoomMember requireMember(UUID roomId, String userId) {
        return members.findByRoomIdAndUserIdAndLeftAtIsNull(roomId, userId)
                .orElseThrow(() -> new RoomNotFoundException(roomId));
    }

    private Placement placement(ChatRoom room, ChatRoomMember member, Instant moveBlockedUntil) {
        return new Placement(room, member, members.countByRoomIdAndLeftAtIsNull(room.getId()),
                moveBlockedUntil);
    }

    private void broadcastAfterCommit(ChatRoomMessage message) {
        if (!TransactionSynchronizationManager.isSynchronizationActive()) {
            delivery.broadcast(message);
            return;
        }
        TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
            @Override
            public void afterCommit() {
                delivery.broadcast(message);
            }
        });
    }

    private static String blankToNull(String value) {
        return value == null || value.isBlank() ? null : value;
    }

    /**
     * Where the caller is.
     *
     * @param memberCount      people currently in the room — a real count of rows, which is what the
     *                         header shows instead of the design's invented "active" figure
     * @param moveBlockedUntil set only when the caller asked for a different area and must stay put
     *                         until then
     */
    public record Placement(ChatRoom room, ChatRoomMember member, long memberCount,
                            Instant moveBlockedUntil) {
    }

    /** @param more whether further messages exist beyond this page, in the direction asked */
    public record HistoryPage(List<ChatRoomMessage> messages, boolean more) {
    }
}
