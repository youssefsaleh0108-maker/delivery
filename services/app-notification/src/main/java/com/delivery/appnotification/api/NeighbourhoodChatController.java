package com.delivery.appnotification.api;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import org.slf4j.MDC;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.delivery.appnotification.domain.ChatRoomMember;
import com.delivery.appnotification.service.ChatDisplayName;
import com.delivery.appnotification.service.NeighbourhoodRoomService;
import com.delivery.appnotification.service.RoomMessageView;
import com.delivery.platform.observability.CorrelationIdFilter;
import com.delivery.platform.security.CurrentUser;

/**
 * A customer's neighbourhood room.
 *
 * <p>Under {@code /api/chat} so the existing ingress routes carry it (a new prefix would need every
 * overlay and the Traefik file changed). Like {@code ChatController}, <strong>no parameter names a
 * user</strong>: the caller is the token's subject, and the only thing a client says about where it
 * belongs is its delivery area — never a room to join. Every room id in a path is checked against the
 * caller's membership, and a room that is not theirs is a 404, the same answer as a room that does
 * not exist.
 *
 * <p>CUSTOMER only. A neighbourhood room is for the people who live there; a rider's or a merchant's
 * account is a work account, and a merchant advertising into the room of the area they deliver to is
 * exactly what the room must not become.
 */
@RestController
@RequestMapping("/api/chat/rooms")
@PreAuthorize("hasRole('CUSTOMER')")
public class NeighbourhoodChatController {

    private final NeighbourhoodRoomService rooms;

    public NeighbourhoodChatController(NeighbourhoodRoomService rooms) {
        this.rooms = rooms;
    }

    /**
     * The caller's room, derived from the delivery area of their selected address.
     *
     * <p>404 with {@code reason} NO_ZONE when the address names no area and the caller is in no room
     * yet, UNKNOWN_ZONE when the area is not one the picker offers; 503 if that cannot be checked.
     */
    @GetMapping("/mine")
    public RoomView mine(@RequestParam(required = false) UUID zoneId) {
        String me = CurrentUser.requireId();
        NeighbourhoodRoomService.Placement placement =
                rooms.place(me, zoneId, ChatDisplayName.from(CurrentUser.jwt().orElse(null)));
        return RoomView.of(placement, Instant.now());
    }

    /** History, newest page first; see {@code NeighbourhoodRoomService.history} for the cursors. */
    @GetMapping("/{roomId}/messages")
    public PageView messages(@PathVariable UUID roomId,
                             @RequestParam(required = false) @Min(1) Long beforeSequence,
                             @RequestParam(required = false) @Min(0) Long afterSequence) {
        String me = CurrentUser.requireId();
        NeighbourhoodRoomService.HistoryPage page = rooms.history(roomId, me, beforeSequence, afterSequence);
        return new PageView(
                page.messages().stream().map(message -> RoomMessageView.of(message, me)).toList(),
                page.more());
    }

    /**
     * Says something. 201 with the stored message; 422 for refused text, 403 with {@code mutedUntil}
     * when a moderator has muted the caller here, 429 with Retry-After when they are sending too fast.
     */
    @PostMapping("/{roomId}/messages")
    public ResponseEntity<RoomMessageView> post(@PathVariable UUID roomId,
                                                @Valid @RequestBody PostMessageRequest request) {
        String me = CurrentUser.requireId();
        return ResponseEntity.status(HttpStatus.CREATED).body(RoomMessageView.of(
                rooms.post(roomId, me, request.text(), request.clientMessageId(),
                        MDC.get(CorrelationIdFilter.MDC_KEY)),
                me));
    }

    /** Same shape and limits as order chat's request, for the same reasons. */
    public record PostMessageRequest(
            @NotBlank @Size(max = 4000) String text,
            @Size(max = 64) String clientMessageId) {
    }

    /**
     * The room as its member sees it.
     *
     * @param memberCount      real membership, not presence — see {@code Placement}
     * @param lastSequence     the newest message's number, 0 for an empty room
     * @param yourHandle       lets the app recognise its own messages in live frames it did not send
     *                         from this device
     * @param mutedUntil       present only while a mute is in force
     * @param moveBlockedUntil present only when the caller's address is in another area they cannot
     *                         move to yet
     */
    public record RoomView(
            UUID id,
            UUID zoneId,
            String name,
            long memberCount,
            long lastSequence,
            UUID yourHandle,
            String yourName,
            Instant mutedUntil,
            Instant moveBlockedUntil) {

        static RoomView of(NeighbourhoodRoomService.Placement placement, Instant now) {
            ChatRoomMember member = placement.member();
            return new RoomView(
                    placement.room().getId(),
                    placement.room().getZoneId(),
                    placement.room().getName(),
                    placement.memberCount(),
                    placement.room().getNextSequence() - 1,
                    member.getHandle(),
                    member.getDisplayName(),
                    member.isMutedAt(now) ? member.getMutedUntil() : null,
                    placement.moveBlockedUntil());
        }
    }

    /** @param more whether there is more history in the direction asked */
    public record PageView(List<RoomMessageView> messages, boolean more) {
    }
}
