package com.delivery.appnotification.service;

import java.time.Instant;
import java.util.UUID;

import com.delivery.appnotification.domain.ChatRoomMessage;

/**
 * One room message as a neighbour sees it — in a history page and in a live frame alike, so the two
 * cannot drift.
 *
 * <p><strong>What is not here is the point.</strong> No Keycloak sub, no username, no phone, no
 * email, no address: an author is a per-room {@code authorHandle} (random, meaningless outside this
 * room) and a display name of first name and last initial. A neighbour can tell two authors apart
 * and address a report or a block to one of them, and cannot take anything away that identifies the
 * person elsewhere on the platform.
 *
 * @param mine whether the viewer wrote it, computed per viewer — the same message is {@code mine} on
 *             the author's phone and not on anyone else's
 * @param kind {@value #TEXT}, or {@value #HIDDEN} for a message a moderator removed, whose
 *             {@code text} is then always null
 */
public record RoomMessageView(
        UUID id,
        UUID roomId,
        long sequence,
        UUID authorHandle,
        String authorName,
        boolean mine,
        String kind,
        String text,
        Instant sentAt) {

    public static final String TEXT = "TEXT";
    public static final String HIDDEN = "HIDDEN";

    public static RoomMessageView of(ChatRoomMessage message, String viewerId) {
        return new RoomMessageView(
                message.getId(),
                message.getRoomId(),
                message.getSequenceNo(),
                message.getSenderHandle(),
                message.getSenderName(),
                message.getSenderId().equals(viewerId),
                TEXT,
                message.getBody(),
                message.getCreatedAt());
    }
}
