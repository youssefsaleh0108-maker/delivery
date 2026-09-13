package com.delivery.appnotification.service;

import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.function.Function;
import java.util.stream.Collectors;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

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

/**
 * Keeping rooms safe: what a neighbour can do about a message (report it, block its author), and what
 * a moderator can do about a report (hide the message, dismiss the report, mute the author here).
 *
 * <p><strong>Everything is enforced on the server.</strong> A block is a filter in the history query
 * and a skip at live delivery; a mute is a refusal in {@code NeighbourhoodRoomService.post}; a hidden
 * message is served as a tombstone to every member from the moment the moderator acts, and pushed as
 * one to anybody watching. None of it relies on a client that chooses to honour it.
 *
 * <p><strong>Staff act through messages and never handle account ids.</strong> A moderator mutes "the
 * author of this reported message", so the queue never needs to show who anybody is on the platform —
 * only the handle and first name the room already shows — and there is no endpoint that takes a user
 * id for a typo to point at the wrong person.
 *
 * <p>Every moderator action writes its audit row in the same transaction, before it changes anything.
 */
@Service
public class RoomModerationService {

    private static final Logger log = LoggerFactory.getLogger(RoomModerationService.class);

    /** How much of the queue one read returns; it is worked from the top. */
    static final int QUEUE_PAGE = 100;

    private final ChatRoomRepository rooms;
    private final ChatRoomMemberRepository members;
    private final ChatRoomMessageRepository messages;
    private final ChatRoomReportRepository reports;
    private final ChatBlockRepository blocks;
    private final ChatModerationActionRepository actions;
    private final RoomDelivery delivery;

    public RoomModerationService(ChatRoomRepository rooms,
                                 ChatRoomMemberRepository members,
                                 ChatRoomMessageRepository messages,
                                 ChatRoomReportRepository reports,
                                 ChatBlockRepository blocks,
                                 ChatModerationActionRepository actions,
                                 RoomDelivery delivery) {
        this.rooms = rooms;
        this.members = members;
        this.messages = messages;
        this.reports = reports;
        this.blocks = blocks;
        this.actions = actions;
        this.delivery = delivery;
    }

    // -------------------------------------------------------------------------- what a member does

    /**
     * Flags a message for a moderator. Idempotent: a second report by the same person is the first.
     *
     * <p>Only a member of the message's room can report it, and the refusal for anybody else is the
     * room's usual 404 — a report endpoint must not become a way to test which message ids exist.
     */
    @Transactional
    public void report(UUID messageId, String reporterId, ChatRoomReport.Reason reason) {
        ChatRoomMessage message = seenBy(messageId, reporterId);
        if (message.getSenderId().equals(reporterId)) {
            throw new MessageRejectedException("You can't report your own message");
        }
        if (message.isHidden()) {
            // Already removed; there is nothing left for a moderator to look at.
            return;
        }
        reports.insertIfAbsent(UUID.randomUUID(), messageId, message.getRoomId(), reporterId, reason.name());
        log.info("A message in room {} was reported ({})", message.getRoomId(), reason);
    }

    /**
     * Stops the caller seeing anything more from the author of this message, anywhere.
     *
     * <p>Addressed through a message, so the caller never holds the author's account id; what comes
     * back is an opaque block id and the name the author went by.
     */
    @Transactional
    public ChatBlock blockAuthor(UUID messageId, String blockerId) {
        ChatRoomMessage message = seenBy(messageId, blockerId);
        if (message.getSenderId().equals(blockerId)) {
            throw new MessageRejectedException("You can't block yourself");
        }
        blocks.insertIfAbsent(UUID.randomUUID(), blockerId, message.getSenderId(), message.getSenderName());
        return blocks.findByBlockerIdAndBlockedId(blockerId, message.getSenderId())
                .orElseThrow(() -> new IllegalStateException("A block vanished right after it was written"));
    }

    @Transactional(readOnly = true)
    public List<ChatBlock> blocksOf(String blockerId) {
        return blocks.findByBlockerIdOrderByCreatedAtDesc(blockerId);
    }

    /** Lifts one of the caller's own blocks; anybody else's block id is a 404. */
    @Transactional
    public void unblock(UUID blockId, String blockerId) {
        ChatBlock block = blocks.findByIdAndBlockerId(blockId, blockerId)
                .orElseThrow(() -> new RoomNotFoundException(blockId));
        blocks.delete(block);
    }

    // ----------------------------------------------------------------------- what a moderator does

    /** Reported messages still waiting for a decision, oldest wait first. */
    @Transactional(readOnly = true)
    public List<ReportedMessage> openQueue() {
        List<ChatRoomReportRepository.OpenTally> tallies = reports.openTallies(PageRequest.of(0, QUEUE_PAGE));
        if (tallies.isEmpty()) {
            return List.of();
        }

        List<UUID> ids = tallies.stream().map(ChatRoomReportRepository.OpenTally::getMessageId).toList();
        Map<UUID, ChatRoomMessage> byId = messages.findAllById(ids).stream()
                .collect(Collectors.toMap(ChatRoomMessage::getId, Function.identity()));
        Set<UUID> roomIds = byId.values().stream().map(ChatRoomMessage::getRoomId).collect(Collectors.toSet());
        Set<String> authorIds = byId.values().stream().map(ChatRoomMessage::getSenderId).collect(Collectors.toSet());

        Map<UUID, ChatRoom> roomsById = rooms.findAllById(roomIds).stream()
                .collect(Collectors.toMap(ChatRoom::getId, Function.identity()));
        Map<UUID, List<ChatRoomReport>> openByMessage = reports.findByMessageIdInAndResolvedAtIsNull(ids).stream()
                .collect(Collectors.groupingBy(ChatRoomReport::getMessageId));
        Map<String, ChatRoomMember> authors = roomIds.isEmpty() ? Map.of()
                : members.findByRoomIdInAndUserIdIn(roomIds, authorIds).stream()
                        .collect(Collectors.toMap(m -> m.getRoomId() + "|" + m.getUserId(),
                                Function.identity(), (first, second) -> first));

        Instant now = Instant.now();
        return tallies.stream()
                .filter(tally -> byId.containsKey(tally.getMessageId()))
                .map(tally -> {
                    ChatRoomMessage message = byId.get(tally.getMessageId());
                    ChatRoom room = roomsById.get(message.getRoomId());
                    ChatRoomMember author = authors.get(message.getRoomId() + "|" + message.getSenderId());
                    List<String> reasons = openByMessage.getOrDefault(message.getId(), List.of()).stream()
                            .map(report -> report.getReason().name())
                            .distinct()
                            .sorted()
                            .toList();
                    return new ReportedMessage(
                            message.getId(),
                            message.getRoomId(),
                            room == null ? null : room.getName(),
                            message.getSenderHandle(),
                            message.getSenderName(),
                            message.getBody(),
                            message.getCreatedAt(),
                            message.isHidden(),
                            tally.getReports(),
                            reasons,
                            tally.getFirstReportedAt(),
                            tally.getLastReportedAt(),
                            author != null && author.isMutedAt(now) ? author.getMutedUntil() : null);
                })
                .toList();
    }

    /**
     * Removes a message from the room and closes its reports.
     *
     * <p>Watching members get the tombstone live, so a harmful message does not stay on the screens
     * that already had it until they happen to refresh.
     */
    @Transactional
    public ChatRoomMessage hide(UUID messageId, String actorId, String reason, String correlationId) {
        ChatRoomMessage message = messages.findById(messageId)
                .orElseThrow(() -> new RoomNotFoundException(messageId));

        actions.save(new ChatModerationAction(actorId, ChatModerationAction.Type.HIDE_MESSAGE, message,
                null, null, reason, correlationId));

        Instant now = Instant.now();
        boolean newlyHidden = message.hide(actorId, now);
        resolveOpenReports(messageId, actorId, ChatRoomReport.Resolution.HIDDEN, now);
        log.info("Backoffice {} hid a message in room {}", actorId, message.getRoomId());

        if (newlyHidden) {
            broadcastAfterCommit(message);
        }
        return message;
    }

    /** Closes a message's reports without acting on it — the message stays. */
    @Transactional
    public void dismiss(UUID messageId, String actorId, String reason, String correlationId) {
        ChatRoomMessage message = messages.findById(messageId)
                .orElseThrow(() -> new RoomNotFoundException(messageId));

        actions.save(new ChatModerationAction(actorId, ChatModerationAction.Type.DISMISS_REPORTS, message,
                null, null, reason, correlationId));
        resolveOpenReports(messageId, actorId, ChatRoomReport.Resolution.DISMISSED, Instant.now());
        log.info("Backoffice {} dismissed reports on a message in room {}", actorId, message.getRoomId());
    }

    /**
     * Mutes the author of a message in that message's room, for a while.
     *
     * <p>Always bounded. A permanent mute is a ban, and a ban is a decision about an account that
     * belongs to a process with an appeal, not to a click in a queue. A mute also survives the member
     * moving away and back, because their membership row is kept.
     *
     * @return when the mute ends
     */
    @Transactional
    public Instant muteAuthor(UUID messageId, String actorId, Duration duration, String reason,
                              String correlationId) {
        ChatRoomMessage message = messages.findById(messageId)
                .orElseThrow(() -> new RoomNotFoundException(messageId));
        ChatRoomMember author = members.findByRoomIdAndUserId(message.getRoomId(), message.getSenderId())
                .orElseThrow(() -> new RoomNotFoundException(messageId));

        Instant until = Instant.now().plus(duration);
        actions.save(new ChatModerationAction(actorId, ChatModerationAction.Type.MUTE_MEMBER, message,
                author.getUserId(), until, reason, correlationId));
        author.muteUntil(until);
        log.info("Backoffice {} muted a member of room {} until {}", actorId, message.getRoomId(), until);
        return until;
    }

    /** Lifts a mute early — a mistake, or an appeal upheld. */
    @Transactional
    public void unmuteAuthor(UUID messageId, String actorId, String reason, String correlationId) {
        ChatRoomMessage message = messages.findById(messageId)
                .orElseThrow(() -> new RoomNotFoundException(messageId));
        ChatRoomMember author = members.findByRoomIdAndUserId(message.getRoomId(), message.getSenderId())
                .orElseThrow(() -> new RoomNotFoundException(messageId));

        actions.save(new ChatModerationAction(actorId, ChatModerationAction.Type.UNMUTE_MEMBER, message,
                author.getUserId(), null, reason, correlationId));
        author.unmute();
        log.info("Backoffice {} unmuted a member of room {}", actorId, message.getRoomId());
    }

    // ---------------------------------------------------------------------------------- internals

    /** The message, if the caller is currently in its room; the room's usual 404 otherwise. */
    private ChatRoomMessage seenBy(UUID messageId, String userId) {
        ChatRoomMessage message = messages.findById(messageId)
                .orElseThrow(() -> new RoomNotFoundException(messageId));
        if (!members.existsByRoomIdAndUserIdAndLeftAtIsNull(message.getRoomId(), userId)) {
            throw new RoomNotFoundException(messageId);
        }
        return message;
    }

    private void resolveOpenReports(UUID messageId, String actorId, ChatRoomReport.Resolution how,
                                    Instant at) {
        reports.findByMessageIdAndResolvedAtIsNull(messageId)
                .forEach(report -> report.resolve(actorId, how, at));
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

    /**
     * One line of the moderation queue.
     *
     * <p>The text is included even for a message already hidden — a moderator deciding whether to mute
     * needs to read what was said. No account ids: the author is the handle and name the room shows.
     *
     * @param authorMutedUntil present only while the author is muted in that room
     */
    public record ReportedMessage(
            UUID messageId,
            UUID roomId,
            String roomName,
            UUID authorHandle,
            String authorName,
            String text,
            Instant sentAt,
            boolean hidden,
            long reportCount,
            List<String> reasons,
            Instant firstReportedAt,
            Instant lastReportedAt,
            Instant authorMutedUntil) {
    }
}
