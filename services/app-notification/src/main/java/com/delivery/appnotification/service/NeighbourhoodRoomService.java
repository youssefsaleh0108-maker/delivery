package com.delivery.appnotification.service;

import java.time.Duration;
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

import com.delivery.appnotification.client.DeliveredAreas;
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
import com.delivery.appnotification.service.RoomExceptions.PostingLockedException;
import com.delivery.appnotification.service.RoomExceptions.ProofUnavailableException;
import com.delivery.appnotification.service.RoomExceptions.RoomNotFoundException;
import com.delivery.appnotification.service.RoomExceptions.SendRateLimitedException;

/**
 * Neighbourhood rooms: who is placed where, what they may read, who may speak, and what gets said.
 *
 * <p><strong>Where a customer's room comes from.</strong> The platform keeps no customer address on
 * the server — addresses live on the phone — so the room a customer reads is the one for the zone of
 * the delivery address they have selected, which the app sends exactly as it sends it at checkout.
 * What the server does with that claim is what makes it a membership rather than a room picker:
 * <ul>
 *   <li>the client never names a room. It names its delivery area; the room is derived from it, and
 *       every later read, post and subscription is checked against the membership row this writes;</li>
 *   <li>the area must be one Product Service offers in the address picker today, so a made-up or
 *       retired id places nobody anywhere;</li>
 *   <li>a person is in one room at a time (a partial unique index, not a convention), and may move to
 *       another only after {@link RoomChatProperties#getMoveCooldown()}, and never while muted.</li>
 * </ul>
 * A customer whose address names no area is placed nowhere and told to choose one
 * ({@link NoRoomReason#NO_ZONE}); somebody already in a room who opens the chat without an area keeps
 * the room they are in.
 *
 * <p><strong>Reading is the customer's choice; speaking needs proof.</strong> Any customer may read
 * the room of the area they choose — a neighbourhood's conversation is no secret from somebody
 * thinking of moving there, and the platform cannot tell a new resident from a visitor anyway.
 * Posting, and counting in the room's member count, need evidence the platform does have: an order
 * of the customer's delivered in that area within {@link RoomChatProperties#getDeliveryProofWindow()},
 * as Order Manager answers for the customer's own token ({@link DeliveredAreas}). The evidence is per
 * area, so moving to another area's room brings the right to speak there only with a delivery there.
 * When Order Manager cannot be asked, nobody posts on a guess: the room stays readable and the
 * composer waits ({@link PostingStatus#UNVERIFIED}).
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
    private final DeliveredAreas deliveredAreas;
    private final RoomDelivery delivery;
    private final RoomChatProperties properties;
    private final ChatProperties chatProperties;

    public NeighbourhoodRoomService(ChatRoomRepository rooms,
                                    ChatRoomMemberRepository members,
                                    ChatRoomMessageRepository messages,
                                    ProductDirectory directory,
                                    DeliveredAreas deliveredAreas,
                                    RoomDelivery delivery,
                                    RoomChatProperties properties,
                                    ChatProperties chatProperties) {
        this.rooms = rooms;
        this.members = members;
        this.messages = messages;
        this.directory = directory;
        this.deliveredAreas = deliveredAreas;
        this.delivery = delivery;
        this.properties = properties;
        this.chatProperties = chatProperties;
    }

    // ---------------------------------------------------------------------------------- placement

    /**
     * The caller's room, placing them in it if they have none or may move, and whether they may speak
     * there.
     *
     * <p>Order Manager being unreachable does not fail this: the caller still reads their room, with
     * posting {@link PostingStatus#UNVERIFIED}.
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
                return placement(room, member, null, now);
            }

            // A muted member stays where the mute found them until it ends, exactly as they stay
            // through the cooldown. A mute recorded on this room's membership is otherwise a mute
            // on a room they can walk out of: move, and the next room hears them.
            Instant movableAt = later(member.getJoinedAt().plus(properties.getMoveCooldown()),
                    members.activeMuteOf(userId, now));
            if (now.isBefore(movableAt)) {
                // Not an error. The caller still has a neighbourhood — the one they are in — and the
                // app says when they can move rather than showing nothing.
                member.arrive(now, displayName);
                return placement(room, member, movableAt, now);
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

        return placement(room, member, null, now);
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
     * <p>Membership is all reading needs; see the class doc for why no proof is asked here.
     *
     * @return the page, and whether more exist in the direction asked
     */
    @Transactional(readOnly = true)
    public HistoryPage history(UUID roomId, String userId, Long beforeSequence, Long afterSequence) {
        requireMember(roomId, userId);
        int size = properties.getHistoryPageSize();
        PageRequest onePastAPage = PageRequest.of(0, size + 1);

        // The caller's id goes into both queries: authors they blocked are excluded by the database.
        if (afterSequence != null) {
            List<ChatRoomMessage> newer = messages.oldestAfter(roomId, afterSequence, userId, onePastAPage);
            boolean more = newer.size() > size;
            return new HistoryPage(more ? newer.subList(0, size) : newer, more);
        }

        long before = beforeSequence == null ? Long.MAX_VALUE : beforeSequence;
        List<ChatRoomMessage> older = messages.newestBefore(roomId, before, userId, onePastAPage);
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
     * busy, not whether they would be muted. Then a retry of something already accepted is answered
     * before anything that could refuse it: a message that got through before a moderator acted, or
     * while Order Manager still answered, must not turn into an error on the retry the network
     * forced. Then the mute, then the proof of living in the area — both before the room's lock,
     * because the proof may be a network call and a lock held across one would queue every
     * neighbour's message behind it. Under the lock: the retry again, and the rate limit.
     */
    @Transactional
    public ChatRoomMessage post(UUID roomId, String userId, String text, String clientMessageId,
                                String correlationId) {
        String body = ChatMessageText.normalise(text, chatProperties.getMaxMessageLength());

        ChatRoomMember member = requireMember(roomId, userId);

        String clientId = blankToNull(clientMessageId);
        Optional<ChatRoomMessage> accepted = alreadyAccepted(roomId, userId, clientId);
        if (accepted.isPresent()) {
            return accepted.get();
        }

        Instant checkedAt = Instant.now();
        // Asked of every membership the person has, not only this room's: see activeMuteOf.
        Instant mutedUntil = members.activeMuteOf(userId, checkedAt);
        if (mutedUntil != null) {
            throw new MemberMutedException(mutedUntil);
        }

        UUID zoneId = rooms.zoneOf(roomId).orElseThrow(() -> new RoomNotFoundException(roomId));
        switch (checkDeliveryProof(member, zoneId, checkedAt)) {
            case NEEDS_DELIVERY -> throw new PostingLockedException();
            case UNVERIFIED -> throw new ProofUnavailableException(
                    "Posting is paused while deliveries cannot be checked", null);
            case OPEN -> {
                // Speaks.
            }
        }

        ChatRoom room = rooms.lockById(roomId).orElseThrow(() -> new RoomNotFoundException(roomId));

        // Again under the lock: two retries of one message can both have passed the look-up above.
        accepted = alreadyAccepted(roomId, userId, clientId);
        if (accepted.isPresent()) {
            return accepted.get();
        }

        Instant now = Instant.now();
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

    private Optional<ChatRoomMessage> alreadyAccepted(UUID roomId, String userId, String clientId) {
        return clientId == null
                ? Optional.empty()
                : messages.findByRoomIdAndSenderIdAndClientMessageId(roomId, userId, clientId);
    }

    private Placement placement(ChatRoom room, ChatRoomMember member, Instant moveBlockedUntil, Instant now) {
        PostingStatus posting = checkDeliveryProof(member, room.getZoneId(), now);
        // Counted after the caller's own proof is recorded, so the number they see includes them
        // exactly when they may speak.
        return new Placement(room, member, members.countProvenMembers(room.getId(), now),
                moveBlockedUntil, members.activeMuteOf(member.getUserId(), now), posting);
    }

    /**
     * Whether this member may speak in the room of {@code zoneId}: asked of Order Manager (through a
     * cache of minutes), recorded on the membership for the member count, and answered as what the
     * composer should do.
     *
     * <p>Only ever for the caller's own membership. The question goes out with the current request's
     * token, so the answer is about whoever is asking.
     */
    private PostingStatus checkDeliveryProof(ChatRoomMember member, UUID zoneId, Instant now) {
        Duration window = properties.getDeliveryProofWindow();
        Optional<Instant> lastDelivery;
        try {
            lastDelivery = deliveredAreas.lastDeliveryIn(member.getUserId(), zoneId, now.minus(window));
        } catch (ProofUnavailableException e) {
            // The membership keeps what was last known, so the member count does not lurch while
            // Order Manager is away; nobody speaks on it in the meantime.
            return PostingStatus.UNVERIFIED;
        }
        member.recordDeliveryProof(lastDelivery.map(at -> at.plus(window)).orElse(null));
        return member.isProvenAt(now) ? PostingStatus.OPEN : PostingStatus.NEEDS_DELIVERY;
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

    private static Instant later(Instant a, Instant b) {
        return b != null && b.isAfter(a) ? b : a;
    }

    /**
     * Where the caller is.
     *
     * @param memberCount      people in the room who may speak there — current members with a
     *                         delivery in its area within the proof window — which is what the header
     *                         shows instead of the design's invented "active" figure
     * @param moveBlockedUntil set only when the caller asked for a different area and must stay put
     *                         until then — the end of the move cooldown or of a mute, whichever is
     *                         later
     * @param mutedUntil       set only while a mute is in force on the caller, whichever of their
     *                         memberships it was recorded on
     * @param posting          whether the caller may speak here, and if not, why; a mute is reported
     *                         separately, in {@code mutedUntil}
     */
    public record Placement(ChatRoom room, ChatRoomMember member, long memberCount,
                            Instant moveBlockedUntil, Instant mutedUntil, PostingStatus posting) {
    }

    /** What the composer does in the room the caller is reading. */
    public enum PostingStatus {
        /** An order of theirs was delivered in the area within the proof window. */
        OPEN,
        /** None was, or none the platform can see: they read, and may post after a delivery there. */
        NEEDS_DELIVERY,
        /** Order Manager could not be asked just now. Nobody posts on a guess; asking again may help. */
        UNVERIFIED
    }

    /** @param more whether further messages exist beyond this page, in the direction asked */
    public record HistoryPage(List<ChatRoomMessage> messages, boolean more) {
    }
}
