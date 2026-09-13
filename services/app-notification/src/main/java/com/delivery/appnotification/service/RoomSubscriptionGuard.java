package com.delivery.appnotification.service;

import java.util.UUID;
import java.util.regex.Pattern;

import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.appnotification.domain.ChatRoomMemberRepository;

/**
 * Decides whether a socket may subscribe to a neighbourhood room's live feed.
 *
 * <p>Asked by {@code WebSocketConfiguration}'s inbound interceptor on every SUBSCRIBE. The rule is
 * the one the history and post endpoints apply — a current membership row for this room and this
 * principal — so the socket is not a side door into a room the REST API would refuse.
 *
 * <p>The check is repeated at send time by {@link RoomDelivery}, because a subscription outlives the
 * membership it was checked against. This guard stops a stranger from listening at all; that one
 * stops a former member from continuing to.
 */
@Component
public class RoomSubscriptionGuard {

    /** Everything in the room family, including malformed attempts at it. */
    static final String ROOM_FAMILY = "/user/queue/chat.rooms";

    /**
     * Canonical lower-case form only. {@code UUID.fromString} is lenient about what it parses, and a
     * guard that accepts two spellings of one room invites a destination the membership check and the
     * broker read differently.
     */
    private static final Pattern CANONICAL_UUID =
            Pattern.compile("[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}");

    private final ChatRoomMemberRepository members;

    public RoomSubscriptionGuard(ChatRoomMemberRepository members) {
        this.members = members;
    }

    /**
     * Whether this principal may listen to this destination.
     *
     * <p>Destinations outside the room family are not this guard's business and answer true. Inside
     * it, the destination must name exactly one room, in canonical form, and the principal must
     * currently be in that room.
     */
    @Transactional(readOnly = true)
    public boolean mayListen(String destination, String userId) {
        if (destination == null || !destination.startsWith(ROOM_FAMILY)) {
            return true;
        }
        String roomId = destination.startsWith(RoomDelivery.ROOM_SUBSCRIPTION_PREFIX)
                ? destination.substring(RoomDelivery.ROOM_SUBSCRIPTION_PREFIX.length())
                : "";
        if (userId == null || !CANONICAL_UUID.matcher(roomId).matches()) {
            return false;
        }
        return members.existsByRoomIdAndUserIdAndLeftAtIsNull(UUID.fromString(roomId), userId);
    }
}
